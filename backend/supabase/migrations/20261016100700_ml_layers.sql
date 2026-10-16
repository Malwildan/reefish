-- ML and habitat map layers (contracts/map-zones-api.openapi.yaml: api_layers, api_habitat).
-- Every numeric layer shares the grid of grid_cells (guide section 7):
--   cluster_predictions per period: level, potential_score, sst, chlor_a, depth_m (24 monthly periods)
--   grid_layers: potensi_ikan.csv, a dataset separate from potential_score (numerical audit 16-10-2026)
-- Units, observation time and the coral codebook are still unconfirmed (guide section 5), so values are
-- returned as-is and the client labels them "nilai".

create table public.grid_layers (
  grid_id text primary key references public.grid_cells (grid_id),
  potensi_ikan numeric
);

create table public.mangrove_areas (
  id int primary key,
  gridcode int,
  year int,
  area_km2 numeric,
  area_clip_km2 numeric,
  geom extensions.geometry(MultiPolygon, 4326) not null
);
create index mangrove_areas_geom_idx on public.mangrove_areas using gist (geom);

alter table public.grid_layers enable row level security;
alter table public.mangrove_areas enable row level security;
-- No policies: read through the RPCs below.

-- One tuple per cell for a period, same style as api_heatmap. Period null = the latest one.
create function public.api_layers(
  p_period text default null,
  p_bbox float8[] default null,
  p_x_min int default null,
  p_x_max int default null,
  p_y_min int default null,
  p_y_max int default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_periods jsonb := (select coalesce(jsonb_agg(period order by period), '[]')
                      from (select distinct period from cluster_predictions) p);
  v_period text := coalesce(p_period, v_periods ->> -1);
begin
  perform private.require_member();
  perform private.check_view('30d', p_bbox);
  if v_period is not null and not v_periods ? v_period then
    perform private.fail('VALIDATION_ERROR', 'Periode tidak tersedia',
      jsonb_build_object('fields', jsonb_build_object('p_period', 'salah satu dari periods'), 'periods', v_periods));
  end if;

  return jsonb_build_object(
    'period', v_period,
    'periods', v_periods,
    'columns', '["grid_id", "level", "potential_score", "sst", "chlor_a", "depth_m", "potensi_ikan", "imputed"]'::jsonb,
    'cells', coalesce((
      select jsonb_agg(jsonb_build_array(
        g.grid_id, p.level, p.potential_score, p.sst, p.chlor_a, p.depth_m, l.potensi_ikan, p.imputed
      ) order by g.grid_id)
      from grid_cells g
      left join cluster_predictions p on p.grid_id = g.grid_id and p.period = v_period
      left join grid_layers l on l.grid_id = g.grid_id
      where private.in_view(g, p_bbox, p_x_min, p_x_max, p_y_min, p_y_max)
        and (p.grid_id is not null or l.grid_id is not null)
    ), '[]'),
    'levels', coalesce((select jsonb_agg(jsonb_build_object('level', level, 'label', label, 'color', color) order by level)
                        from cluster_levels), '[]'),
    'units', '{"potential_score": null, "sst": null, "chlor_a": null, "depth_m": null, "potensi_ikan": null}'::jsonb
  );
end;
$$;

-- Habitat polygons as GeoJSON FeatureCollections. Coral keeps both codes 0 and 1: the codebook is unconfirmed,
-- the client shows value = 1 with a provisional label (guide section 3).
create function public.api_habitat()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  perform private.require_member();
  return jsonb_build_object(
    'coral', jsonb_build_object('type', 'FeatureCollection', 'features', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', 'Feature', 'id', c.id, 'geometry', st_asgeojson(c.geom, 7)::jsonb,
        'properties', jsonb_build_object('value', c.value)) order by c.id)
      from coral_areas c), '[]')),
    'mangrove', jsonb_build_object('type', 'FeatureCollection', 'features', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', 'Feature', 'id', m.id, 'geometry', st_asgeojson(m.geom, 7)::jsonb,
        'properties', jsonb_build_object('gridcode', m.gridcode, 'year', m.year,
                                         'area_km2', m.area_km2, 'area_clip_km2', m.area_clip_km2)) order by m.id)
      from mangrove_areas m), '[]')),
    'coral_codebook_confirmed', false
  );
end;
$$;

revoke execute on function public.api_layers(text, float8[], int, int, int, int), public.api_habitat()
from public, anon;
grant execute on function public.api_layers(text, float8[], int, int, int, int), public.api_habitat()
to authenticated;
