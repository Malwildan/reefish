-- Recommendation ranking inputs and cache freshness (docs/AGENTS.md 10.4, 12.B.5).
-- api_rec_context: per-candidate fatigue and crowding (recommendations already given for that cell and date)
--   so the Go ranker can apply the K and P penalties; the cache is reused only while no recommended cell
--   changed on the map (heatmap_cells.updated_version) since the set was made.
-- api_save_recommendations: accepts departure/return times chosen from the forecast, stores heatmap_version.
-- Bodies are copied from 20261016100600_zones_heatmap with only those changes.

alter table public.recommendation_sets add column heatmap_version bigint;
create index recommendations_grid_idx on public.recommendations (grid_id);
create index recommendation_sets_for_date_idx on public.recommendation_sets (for_date);

create or replace function public.api_rec_context(p_for_date date default null, p_refresh boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
  v_date date := private.check_for_date(p_for_date);
  v_boat boats := private.onboarded_boat(v_uid);
  v_window timestamptz := (v_date + (private.config('rec.departure_time') #>> '{}')::time) at time zone 'Asia/Jakarta';
  v_cached uuid;
begin
  if not coalesce(p_refresh, false) then
    -- reuse only while no recommended cell changed on the map since the set was made (12.B.5)
    select s.id into v_cached from recommendation_sets s
    where s.user_id = v_uid and s.for_date = v_date and s.valid_until > now()
      and not exists (
        select 1 from recommendations r join heatmap_cells hc on hc.grid_id = r.grid_id
        where r.set_id = s.id and hc.updated_version > coalesce(s.heatmap_version, 0))
    order by s.generated_at desc
    limit 1;
    if v_cached is not null then
      return jsonb_build_object('cached', private.set_json(v_cached));
    end if;
  end if;

  return jsonb_build_object(
    'cached', null,
    'for_date', v_date,
    'window_start', v_window,
    'boat', jsonb_build_object(
      'id', v_boat.id, 'home_port', private.latlng(v_boat.home_port),
      'engine_hp', v_boat.engine_hp, 'boat_length_m', v_boat.boat_length_m
    ),
    'stats', (
      select jsonb_build_object(
        'trip_count', count(*),
        'fuel_per_km', avg(fuel_per_km) filter (where fuel_per_km > 0),
        'avg_catch_kg', avg(catch_kg),
        'baseline_fuel_liters', avg(fuel_liters)
      ) from trips where user_id = v_uid
    ),
    'config', jsonb_build_object(
      'max_range_km', private.config('rec.max_range_km'),
      'default_fuel_per_km', private.config('rec.default_fuel_per_km'),
      'departure_time', private.config('rec.departure_time'),
      'return_time', private.config('rec.return_time')
    ),
    -- predicted cells in range of the home port, outside rehab zones and exhausted quotas at departure
    'candidates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'grid_id', g.grid_id,
        'lat', round(st_y(g.geom::geometry)::numeric, 6), 'lng', round(st_x(g.geom::geometry)::numeric, 6),
        'dist_m', round(st_distance(g.geom, v_boat.home_port)::numeric),
        'potential_score', p.potential_score, 'level', p.level, 'zone', zz.z,
        'fatigue', hcc.fatigue, 'fatigue_level', hcc.fatigue_level, 'crowd_today', coalesce(cr.n, 0)
      ))
      from cluster_predictions p
      join grid_cells g on g.grid_id = p.grid_id
      left join heatmap_cells hcc on hcc.grid_id = g.grid_id
      -- AGENTS.md 10.4 crowding: recommendations already given for this cell and date, all users
      left join (
        select r2.grid_id, count(*) as n
        from recommendations r2 join recommendation_sets s2 on s2.id = r2.set_id
        where s2.for_date = v_date
        group by r2.grid_id
      ) cr on cr.grid_id = g.grid_id
      cross join lateral (select private.zone_json(g.geom, v_window) as z) zz
      where p.period = (select max(period) from cluster_predictions)
        and p.level >= (private.config('rec.min_level') #>> '{}')::int
        and st_dwithin(g.geom, v_boat.home_port, (private.config('rec.max_range_km') #>> '{}')::float8 * 1000)
        and not (zz.z ->> 'closed')::boolean
        and not exists (select 1 from heatmap_cells hc where hc.grid_id = g.grid_id and hc.fatigue_level = 'critical')
    ), '[]'),
    'habitual', (
      select jsonb_build_object(
        'grid_id', g.grid_id,
        'lat', round(st_y(g.geom::geometry)::numeric, 6), 'lng', round(st_x(g.geom::geometry)::numeric, 6),
        'dist_m', round(st_distance(g.geom, v_boat.home_port)::numeric),
        'visits', h.visits, 'zone', private.zone_json(g.geom, v_window),
        'critical', exists (select 1 from heatmap_cells hc where hc.grid_id = g.grid_id and hc.fatigue_level = 'critical'),
        'fatigue', (select hc.fatigue from heatmap_cells hc where hc.grid_id = g.grid_id),
        'fatigue_level', (select hc.fatigue_level from heatmap_cells hc where hc.grid_id = g.grid_id)
      )
      from (
        select f.grid_id, count(*) as visits, max(t.departed_at) as last_at
        from fishing_points f join trips t on t.id = f.trip_id
        where t.user_id = v_uid and f.grid_id is not null
        group by f.grid_id
        order by count(*) desc, max(t.departed_at) desc
        limit 1
      ) h
      join grid_cells g on g.grid_id = h.grid_id
    )
  );
end;
$$;

create or replace function public.api_save_recommendations(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
  v_boat boats := private.onboarded_boat(v_uid);
  v_date date;
  v_window timestamptz;
  v_set uuid;
  v_item jsonb;
  v_geom geography;
  v_zone jsonb;
  v_dep time := (private.config('rec.departure_time') #>> '{}')::time;
  v_ret time := (private.config('rec.return_time') #>> '{}')::time;
begin
  if jsonb_typeof(p) is distinct from 'object' or coalesce(jsonb_typeof(p -> 'items'), '') <> 'array'
     or coalesce(p ->> 'for_date', '') !~ '^\d{4}-\d{2}-\d{2}$' then
    perform private.fail('VALIDATION_ERROR', 'Data rekomendasi tidak valid');
  end if;
  v_date := private.check_for_date((p ->> 'for_date')::date);
  -- departure/return chosen by the Go service from the forecast (AGENTS.md 10.4); config times otherwise
  if coalesce(p ->> 'departure_time', '') ~ '^([01]\d|2[0-3]):[0-5]\d$'
     and coalesce(p ->> 'return_time', '') ~ '^([01]\d|2[0-3]):[0-5]\d$'
     and (p ->> 'return_time')::time > (p ->> 'departure_time')::time then
    v_dep := (p ->> 'departure_time')::time;
    v_ret := (p ->> 'return_time')::time;
  end if;
  v_window := (v_date + v_dep) at time zone 'Asia/Jakarta';

  insert into recommendation_sets (
    user_id, boat_id, source_trip_id, for_date, period, window_start, max_range_km, fuel_per_km,
    avg_catch_kg, baseline_fuel_liters, departure_time, return_time, model_version, is_fallback,
    unavailable_types, valid_until, heatmap_version
  ) values (
    v_uid, v_boat.id,
    (select id from trips where user_id = v_uid order by returned_at desc limit 1),
    v_date, (select max(period) from cluster_predictions), v_window,
    (private.config('rec.max_range_km') #>> '{}')::numeric,
    (p ->> 'fuel_per_km')::numeric, (p ->> 'avg_catch_kg')::numeric, (p ->> 'baseline_fuel_liters')::numeric,
    v_dep, v_ret,
    coalesce(p ->> 'model_version', 'heuristic-0.1'), coalesce((p ->> 'is_fallback')::boolean, true),
    coalesce(p -> 'unavailable_types', '[]'),
    now() + make_interval(hours => (private.config('rec.valid_hours') #>> '{}')::int),
    private.current_version()
  )
  returning id into v_set;

  for v_item in select * from jsonb_array_elements(p -> 'items') loop
    if coalesce(v_item ->> 'type', '') not in ('fuel_saving', 'catch_max', 'balanced', 'habitual') then
      perform private.fail('VALIDATION_ERROR', 'Tipe rekomendasi tidak valid');
    end if;
    v_geom := null;
    select c.geom into v_geom from grid_cells c where c.grid_id = v_item ->> 'grid_id';
    if v_geom is null then
      perform private.fail('VALIDATION_ERROR', 'Grid rekomendasi tidak ditemukan');
    end if;
    v_zone := private.zone_json(v_geom, v_window);
    if exists (select 1 from heatmap_cells hc where hc.grid_id = v_item ->> 'grid_id' and hc.fatigue_level = 'critical') then
      perform private.fail('VALIDATION_ERROR', 'Rekomendasi tidak boleh di grid dengan kelelahan kritis');
    end if;
    if (v_zone ->> 'closed')::boolean then
      perform private.fail('VALIDATION_ERROR', 'Rekomendasi tidak boleh di zona tertutup');
    end if;

    insert into recommendations (
      set_id, user_id, type, grid_id, point, zone, zone_rules, distance_from_port_km,
      predicted_fuel_liters, fuel_efficiency_pct, predicted_catch_kg, predicted_catch_min, predicted_catch_max,
      confidence, reason, weather_summary, area_condition
    ) values (
      v_set, v_uid, v_item ->> 'type', v_item ->> 'grid_id', v_geom,
      jsonb_build_object('id', v_zone -> 'id', 'name', v_zone -> 'name', 'status', v_zone -> 'status'),
      case when v_zone ->> 'status' = 'restricted' then jsonb_build_object(
        'quota_remaining_kg', v_zone -> 'quota_remaining_kg', 'open_schedule', v_zone -> 'open_schedule') end,
      round((st_distance(v_geom, v_boat.home_port) / 1000)::numeric, 2),
      (v_item ->> 'predicted_fuel_liters')::numeric, (v_item ->> 'fuel_efficiency_pct')::numeric,
      (v_item ->> 'predicted_catch_kg')::numeric, (v_item ->> 'predicted_catch_min')::numeric,
      (v_item ->> 'predicted_catch_max')::numeric,
      coalesce((v_item ->> 'confidence')::numeric, 0.3), coalesce(v_item ->> 'reason', ''),
      v_item -> 'weather_summary',
      coalesce((select case when hc.fatigue_level = 'tired' then 'tired' end
                from heatmap_cells hc where hc.grid_id = v_item ->> 'grid_id'), 'healthy')
    );
  end loop;
  return private.set_json(v_set);
exception when unique_violation then
  perform private.fail('VALIDATION_ERROR', 'Satu tipe rekomendasi hanya boleh sekali');
end;
$$;

create or replace function private.set_json(p_set uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'for_date', s.for_date, 'generated_at', s.generated_at, 'valid_until', s.valid_until,
    'source_trip_id', s.source_trip_id, 'boat_id', s.boat_id, 'baseline_fuel_liters', s.baseline_fuel_liters,
    'heatmap_version', s.heatmap_version, 'model_version', s.model_version, 'is_fallback', s.is_fallback,
    'items', coalesce((
      select jsonb_agg(private.rec_json(r, s)
        order by array_position(array['fuel_saving', 'catch_max', 'balanced', 'habitual'], r.type))
      from public.recommendations r where r.set_id = s.id
    ), '[]'),
    'unavailable_types', s.unavailable_types
  )
  from public.recommendation_sets s
  where s.id = p_set;
$$;
