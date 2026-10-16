-- Reduce repeated zone lookups in api_rec_context. First use the geography index to
-- restrict the grid to the boat's range, then filter by latest period, level, and
-- critical fatigue before evaluating the zone helper once per remaining cell.
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
    -- Reuse only while no recommended cell changed on the map since the set was made.
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
    'candidates', coalesce((
      with nearby_grid as materialized (
        select g.grid_id, g.geom
        from grid_cells g
        where st_dwithin(g.geom, v_boat.home_port,
          (private.config('rec.max_range_km') #>> '{}')::float8 * 1000)
      ), filtered_candidates as materialized (
        select n.grid_id, n.geom, p.potential_score, p.level,
               hcc.fatigue, hcc.fatigue_level
        from nearby_grid n
        join cluster_predictions p on p.grid_id = n.grid_id
        left join heatmap_cells hcc on hcc.grid_id = n.grid_id
        where p.period = (select max(period) from cluster_predictions)
          and p.level >= (private.config('rec.min_level') #>> '{}')::int
          and not exists (
            select 1 from heatmap_cells hc
            where hc.grid_id = n.grid_id and hc.fatigue_level = 'critical'
          )
      ), zoned_candidates as materialized (
        select c.*, private.zone_json(c.geom, v_window) as zone
        from filtered_candidates c
      ), crowd_by_grid as materialized (
        select r2.grid_id, count(*) as n
        from recommendations r2
        join recommendation_sets s2 on s2.id = r2.set_id
        join filtered_candidates c on c.grid_id = r2.grid_id
        where s2.for_date = v_date
        group by r2.grid_id
      )
      select jsonb_agg(jsonb_build_object(
        'grid_id', c.grid_id,
        'lat', round(st_y(c.geom::geometry)::numeric, 6),
        'lng', round(st_x(c.geom::geometry)::numeric, 6),
        'dist_m', round(st_distance(c.geom, v_boat.home_port)::numeric),
        'potential_score', c.potential_score, 'level', c.level, 'zone', c.zone,
        'fatigue', c.fatigue, 'fatigue_level', c.fatigue_level, 'crowd_today', coalesce(cr.n, 0)
      ))
      from zoned_candidates c
      left join crowd_by_grid cr on cr.grid_id = c.grid_id
      where not (c.zone ->> 'closed')::boolean
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
