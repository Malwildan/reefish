-- All cluster points of one period as a GeoJSON FeatureCollection (dashboard map)
create function public.get_clusters(p_period text, p_min_level int default 1)
returns jsonb
language sql
stable
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(jsonb_agg(jsonb_build_object(
      'type', 'Feature',
      'id', g.grid_id,
      'geometry', st_asgeojson(g.geom)::jsonb,
      'properties', jsonb_build_object(
        'grid_id', g.grid_id,
        'cluster_id', p.cluster_id,
        'level', p.level,
        'potential_score', p.potential_score,
        'sst', p.sst,
        'chlor_a', p.chlor_a,
        'depth_m', p.depth_m,
        'imputed', p.imputed
      )
    )), '[]'::jsonb)
  )
  from cluster_predictions p
  join grid_cells g using (grid_id)
  where p.period = p_period and p.level >= p_min_level;
$$;

-- Fishing spots for nelayan: drops points inside active closed zones,
-- tags points inside active limited zones with their catch limit
create function public.get_fishing_spots(p_period text, p_min_level int default 4)
returns jsonb
language sql
stable
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(jsonb_agg(jsonb_build_object(
      'type', 'Feature',
      'id', g.grid_id,
      'geometry', st_asgeojson(g.geom)::jsonb,
      'properties', jsonb_build_object(
        'grid_id', g.grid_id,
        'level', p.level,
        'potential_score', p.potential_score,
        'sst', p.sst,
        'chlor_a', p.chlor_a,
        'depth_m', p.depth_m,
        'zone_status', coalesce(z.status, 'open'),
        'max_catch_kg', z.max_catch_kg
      )
    ) order by p.potential_score desc), '[]'::jsonb)
  )
  from cluster_predictions p
  join grid_cells g using (grid_id)
  -- most restrictive active zone wins when zones overlap
  left join lateral (
    select zz.status, zz.max_catch_kg
    from zones zz
    where st_intersects(zz.geom, g.geom)
      and zz.valid_from <= current_date
      and (zz.valid_to is null or zz.valid_to >= current_date)
    order by case zz.status when 'closed' then 0 when 'limited' then 1 else 2 end
    limit 1
  ) z on true
  where p.period = p_period
    and p.level >= p_min_level
    and z.status is distinct from 'closed';
$$;

revoke execute on function public.get_clusters(text, int) from public, anon;
revoke execute on function public.get_fishing_spots(text, int) from public, anon;
grant execute on function public.get_clusters(text, int) to authenticated;
grant execute on function public.get_fishing_spots(text, int) to authenticated;
