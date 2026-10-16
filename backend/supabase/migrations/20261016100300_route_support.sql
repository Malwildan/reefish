-- Sea grid nodes for the Go route service as [[grid_id, lon, lat], ...].
-- One jsonb value avoids PostgREST max-rows paging over 31k rows.
create function public.grid_points()
returns jsonb
language sql
stable
set search_path = public, extensions
as $$
  select coalesce(jsonb_agg(jsonb_build_array(grid_id, st_x(geom::geometry), st_y(geom::geometry))), '[]'::jsonb)
  from grid_cells;
$$;

revoke execute on function public.grid_points() from public, anon;
grant execute on function public.grid_points() to authenticated;
