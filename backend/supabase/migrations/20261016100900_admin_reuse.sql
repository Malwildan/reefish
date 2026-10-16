-- Admin (konservatif) reuses the nelayan/shared endpoints instead of duplicating them:
--   api_me and api_in_pilot (and so Go GET /api/v1/weather) now accept both roles.
-- New: api_admin_suggestions (restrict + reopen suggestions); api_admin_grid_detail gains the reopen fields.
-- Bodies of the replaced functions are copied from 20261016100500_nelayan / 20261016100600_zones_heatmap.

create or replace function public.api_me()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_member();
  v_profile profiles;
  v_boat boats;
  v_stats jsonb;
begin
  select * into v_profile from profiles where id = v_uid;
  -- AGENTS.md 12.A.3: an admin gets the same shape with the nelayan-only parts empty
  if v_profile.role = 'konservatif' then
    return jsonb_build_object(
      'id', v_uid, 'name', v_profile.full_name, 'phone', v_profile.phone, 'role', v_profile.role,
      'onboarded', true, 'next_step', 'done', 'boat', null, 'stats', null);
  end if;
  select * into v_boat from boats where user_id = v_uid and is_default and deleted_at is null;
  select jsonb_build_object(
    'trip_count', count(*),
    'baseline_fuel_liters', round(avg(fuel_liters), 2),
    'baseline_catch_kg', round(avg(catch_kg), 2),
    'last_trip_at', max(returned_at)
  ) into v_stats
  from trips where user_id = v_uid;

  return jsonb_build_object(
    'id', v_uid, 'name', v_profile.full_name, 'phone', v_profile.phone, 'role', v_profile.role,
    'onboarded', v_profile.onboarded,
    'next_step', case when v_boat.id is null then 'boat' when not v_profile.onboarded then 'first_trip' else 'done' end,
    'boat', case when v_boat.id is not null then private.boat_json(v_boat) end,
    'stats', v_stats
  );
end;
$$;

create or replace function public.api_in_pilot(p_lat float8, p_lng float8)
returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  perform private.require_member();
  return private.in_pilot(st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, 5000);
end;
$$;

create or replace function public.api_admin_grid_detail(p_grid_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_grid grid_cells;
  v_cell heatmap_cells;
  v_zone zones;
  v_stats grid_stats;
begin
  perform private.require_konservatif();
  if coalesce(p_grid_id, '') !~ '^X\d{3}_Y\d{3}$' then
    perform private.fail('GRID_INVALID', 'Format grid_id harus X149_Y001');
  end if;
  select * into v_grid from grid_cells where grid_id = p_grid_id;
  if v_grid.grid_id is null then
    perform private.fail('GRID_NOT_FOUND', 'Grid tidak ditemukan');
  end if;
  select * into v_cell from heatmap_cells where grid_id = p_grid_id;
  select * into v_zone from zones where id = v_cell.zone_id and is_active;
  select * into v_stats from grid_stats where grid_id = p_grid_id;

  return jsonb_build_object(
    'grid_id', v_grid.grid_id, 'cell_id', v_grid.cell_id, 'grid_x', v_grid.grid_x, 'grid_y', v_grid.grid_y,
    'centroid', private.latlng(v_grid.geom),
    'is_sea', v_grid.is_sea, 'has_coral', v_grid.has_coral, 'coral_cover_pct', v_grid.coral_cover_pct,
    'heatmap_version', private.current_version(),
    'zone', case when v_zone.id is not null then private.zone_entry(v_zone, false) end,
    'auto_flag', v_cell.auto_flag, 'auto_flagged_at', v_cell.auto_flagged_at,
    'flag_dismissed_until', v_cell.flag_dismissed_until,
    'suggestion', v_stats.suggestion, 'days_low_fatigue', v_stats.days_low_fatigue,
    'stats', jsonb_build_object(
      'fatigue_index', v_cell.fatigue, 'fatigue_level', v_cell.fatigue_level, 'pressure_index', v_cell.pressure_index,
      'trip_count_7d', v_cell.trip_count_7d, 'trip_count_30d', v_cell.trip_count_30d,
      'fishing_hours_30d', v_cell.fishing_hours_30d, 'catch_kg_30d', v_cell.catch_kg_30d,
      'cpue_30d', v_cell.cpue_30d, 'last_visited_at', v_cell.last_visited_at),
    'fatigue_trend_30d', coalesce((
      select jsonb_agg(jsonb_build_array(l.day, l.fatigue) order by l.day)
      from grid_daily_load l
      where l.grid_id = p_grid_id and l.fatigue is not null
        and l.day > (now() at time zone 'Asia/Jakarta')::date - 30
    ), '[]')
  );
end;
$$;

-- "Saran sistem" (AGENTS.md 4.2 #7, 5.3) in one feed:
--   restrict = active auto-flags (the same rows as api_admin_list_flags, called rather than re-queried)
--   reopen   = rehab zones whose grids stayed below flag.reopen_below for flag.reopen_days (daily_refresh)
create function public.api_admin_suggestions(p_type text default null, p_page int default 1, p_limit int default 20)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_page int := greatest(coalesce(p_page, 1), 1);
  v_limit int := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_restrict jsonb;
  v_reopen jsonb;
begin
  perform private.require_konservatif();
  if p_type is not null and p_type not in ('restrict', 'reopen') then
    perform private.fail('VALIDATION_ERROR', 'type harus restrict atau reopen');
  end if;

  if p_type is distinct from 'reopen' then
    v_restrict := public.api_admin_list_flags('active', null, null, '-fatigue', v_page, v_limit);
  end if;

  if p_type is distinct from 'restrict' then
    with z as (
      select z.id, z.name,
        count(*) as grid_count,
        count(*) filter (where s.suggestion = 'reopen') as suggested_count,
        coalesce(jsonb_agg(zg.grid_id order by zg.grid_id) filter (where s.suggestion = 'reopen'), '[]') as grid_ids,
        round(avg(h.fatigue), 3) as fatigue_avg,
        min(s.days_low_fatigue) filter (where s.suggestion = 'reopen') as days_low_min,
        z.version
      from zones z
      join zone_grids zg on zg.zone_id = z.id
      left join grid_stats s on s.grid_id = zg.grid_id
      left join heatmap_cells h on h.grid_id = zg.grid_id
      where z.is_active and z.status = 'rehab'
      group by z.id, z.name, z.version
      having count(*) filter (where s.suggestion = 'reopen') > 0
    )
    select jsonb_build_object(
      'data', coalesce((
        select jsonb_agg(jsonb_build_object(
          'zone_id', id, 'name', name, 'grid_ids', grid_ids,
          'suggested_count', suggested_count, 'grid_count', grid_count,
          'suggested_pct', round(100.0 * suggested_count / grid_count, 1),
          'fatigue_avg', fatigue_avg, 'days_low_min', days_low_min, 'version', version
        ) order by suggested_count::numeric / grid_count desc, name)
        from (select * from z order by suggested_count::numeric / grid_count desc, name
              offset (v_page - 1) * v_limit limit v_limit) p
      ), '[]'),
      'meta', jsonb_build_object('page', v_page, 'limit', v_limit, 'total', (select count(*) from z))
    ) into v_reopen;
  end if;

  return jsonb_build_object(
    'restrict', v_restrict,
    'reopen', v_reopen,
    'heatmap_version', private.current_version()
  );
end;
$$;

revoke execute on function public.api_admin_suggestions(text, int, int) from public, anon;
grant execute on function public.api_admin_suggestions(text, int, int) to authenticated;
