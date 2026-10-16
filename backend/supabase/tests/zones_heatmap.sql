-- Smoke test for migration 0007 (zones, heatmap, flags, devices). Not a migration: run after the grid import with
-- psql "$SUPABASE_DB_URL" -f supabase/tests/zones_heatmap.sql   (or paste into the SQL Editor).
-- Everything is rolled back. Any failed check raises an exception.
begin;

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-8000-00000000c001', 'smoke-kons@phone.reefish.app', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000c002', 'smoke-nel@phone.reefish.app', 'authenticated', 'authenticated');
update public.profiles set role = 'konservatif' where id = '00000000-0000-4000-8000-00000000c001';

-- a 3x2 block of existing cells: g1..g3 on one row, g4..g6 on the row above
create temp table smoke_cells on commit drop as
select b.grid_x + dx as grid_x, b.grid_y + dy as grid_y,
       format('X%s_Y%s', lpad((b.grid_x + dx)::text, 3, '0'), lpad((b.grid_y + dy)::text, 3, '0')) as grid_id,
       dy * 3 + dx + 1 as n
from (
  select g.grid_x, g.grid_y from public.grid_cells g
  where (select count(*) from public.grid_cells n
         where n.grid_x between g.grid_x and g.grid_x + 2 and n.grid_y between g.grid_y and g.grid_y + 1) = 6
  order by g.grid_y, g.grid_x limit 1
) b, generate_series(0, 2) dx, generate_series(0, 1) dy;
create temp table smoke_state (k text primary key, val text) on commit drop;
grant select on smoke_cells to authenticated;
grant all on smoke_state to authenticated;

create function pg_temp.as_user(p_id text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.g(p_n int) returns text language sql as $$ select grid_id from smoke_cells where n = p_n $$;
create function pg_temp.expect_error(p_sql text, p_code text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'expected % from %', p_code, p_sql;
exception when raise_exception then
  if sqlerrm <> p_code then raise; end if;
end;
$$;

set local role authenticated;

do $$
declare
  kons text := '00000000-0000-4000-8000-00000000c001';
  nel text := '00000000-0000-4000-8000-00000000c002';
  v jsonb;
  z1 jsonb;
  z2 jsonb;
  v_ver bigint;
  v_port jsonb;
  v_poly jsonb;
begin
  if (select count(*) from smoke_cells) <> 6 then raise exception 'import grid_cells first'; end if;
  perform pg_temp.as_user(kons);

  v := public.api_grid_meta();
  if (v ->> 'cols')::int <> 187 or (v ->> 'epsg')::int <> 32749 then raise exception 'grid meta %', v; end if;
  v := public.api_sea_mask();
  if (v ->> 'length')::int <> 187 * 177 or length(v ->> 'bits') <> 4 * ceil(ceil(187 * 177 / 8.0) / 3) then
    raise exception 'sea mask %', v - 'bits';
  end if;

  v := public.api_admin_preview_zone(jsonb_build_object('grid_ids', jsonb_build_array(pg_temp.g(1), pg_temp.g(2), 'X999_Y999')));
  if jsonb_array_length(v -> 'valid_grid_ids') <> 2 or v -> 'invalid_grid_ids' <> '["X999_Y999"]'
     or not (v ->> 'is_contiguous')::boolean then
    raise exception 'preview %', v - 'outline';
  end if;

  -- polygon input: a polygon just inside g1 + g2 picks exactly those two cell centres
  select st_asgeojson(st_buffer(st_union(cell), -0.0001))::jsonb into v_poly
  from public.grid_cells where grid_id in (pg_temp.g(1), pg_temp.g(2));
  v := public.api_admin_preview_zone(jsonb_build_object('polygon', v_poly));
  if v -> 'valid_grid_ids' <> jsonb_build_array(pg_temp.g(1), pg_temp.g(2)) then raise exception 'polygon preview %', v - 'outline'; end if;
  perform pg_temp.expect_error(format('select public.api_admin_preview_zone(%L)',
    jsonb_build_object('polygon', v_poly, 'grid_ids', jsonb_build_array(pg_temp.g(1)))), 'VALIDATION_ERROR');
  perform pg_temp.expect_error($q$select public.api_admin_preview_zone('{"polygon": {"type": "Polygon", "coordinates": [[[1, 2]]]}}')$q$, 'VALIDATION_ERROR');
  perform pg_temp.expect_error($q$select public.api_admin_preview_zone('{"polygon": {"type": "Polygon", "coordinates": [[[0, 0], [0.001, 0], [0.001, 0.001], [0, 0]]]}}')$q$, 'VALIDATION_ERROR');

  perform pg_temp.expect_error(format($q$select public.api_admin_create_zone('{"name":"Uji","status":"restricted","grid_ids":["%s"],"reason":"uji smoke"}')$q$, pg_temp.g(1)), 'RULES_REQUIRED');
  z1 := public.api_admin_create_zone(jsonb_build_object(
    'name', 'Zona Uji Satu', 'status', 'restricted', 'grid_ids', jsonb_build_array(pg_temp.g(1), pg_temp.g(2)),
    'rules', jsonb_build_object('max_catch_kg_per_period', 30, 'period', 'weekly'), 'reason', 'uji smoke',
    'effective_from', to_char(now() - interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  if z1 ->> 'status' <> 'restricted' or jsonb_array_length(z1 -> 'grid_ids') <> 2
     or z1 -> 'entry' -> 'quota' ->> 'remaining_kg' <> '30' or z1 -> 'notification' ->> 'change' <> 'created' then
    raise exception 'create z1 %', z1 - 'outline';
  end if;
  insert into smoke_state values ('z1', z1 ->> 'id');

  perform pg_temp.expect_error(format($q$select public.api_admin_create_zone('{"name":"zona uji satu","status":"rehab","grid_ids":["%s"],"reason":"uji smoke"}')$q$, pg_temp.g(3)), 'ZONE_NAME_TAKEN');
  perform pg_temp.expect_error(format($q$select public.api_admin_create_zone('{"name":"Zona Dua","status":"rehab","grid_ids":["%s","%s"],"reason":"uji smoke"}')$q$, pg_temp.g(2), pg_temp.g(3)), 'GRID_CONFLICT');
  z2 := public.api_admin_create_zone(jsonb_build_object('name', 'Zona Dua', 'status', 'rehab', 'on_conflict', 'skip',
    'grid_ids', jsonb_build_array(pg_temp.g(2), pg_temp.g(3)), 'reason', 'uji smoke',
    'effective_from', to_char(now() - interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  if z2 -> 'skipped_grid_ids' <> jsonb_build_array(pg_temp.g(2)) or z2 -> 'grid_ids' <> jsonb_build_array(pg_temp.g(3)) then
    raise exception 'skip %', z2 - 'outline';
  end if;
  insert into smoke_state values ('z2', z2 ->> 'id');

  -- move g1 out of z1 into a new zone: z1 keeps g2 and gets a new version
  v := public.api_admin_create_zone(jsonb_build_object('name', 'Zona Tiga', 'status', 'rehab', 'on_conflict', 'move',
    'grid_ids', jsonb_build_array(pg_temp.g(1)), 'reason', 'uji smoke'));
  if v -> 'moved_grid_ids' <> jsonb_build_array(pg_temp.g(1)) then raise exception 'move %', v - 'outline'; end if;
  z1 := public.api_admin_zone_detail((z1 ->> 'id')::uuid);
  if (z1 ->> 'version')::int <> 2 or z1 -> 'grid_ids' <> jsonb_build_array(pg_temp.g(2)) then
    raise exception 'z1 after move %', z1 - 'outline';
  end if;

  perform pg_temp.expect_error(format($q$select public.api_admin_edit_zone('%s', '{"name":"Baru","reason":"uji smoke","version":1}')$q$, z1 ->> 'id'), 'VERSION_CONFLICT');
  v := public.api_admin_edit_zone((z1 ->> 'id')::uuid, '{"name": "Zona Uji Satu B", "reason": "uji smoke", "version": 2}');
  if v ->> 'name' <> 'Zona Uji Satu B' or (v ->> 'version')::int <> 3 then raise exception 'edit %', v - 'outline'; end if;

  select st_asgeojson(st_buffer(st_union(cell), -0.0001))::jsonb into v_poly
  from public.grid_cells where grid_id in (pg_temp.g(4), pg_temp.g(5));
  v := public.api_admin_edit_zone_grids((z1 ->> 'id')::uuid,
    jsonb_build_object('add_polygon', v_poly, 'reason', 'uji smoke', 'version', 3));
  if jsonb_array_length(v -> 'grid_ids') <> 3 or (v ->> 'version')::int <> 4 then raise exception 'edit grids %', v - 'outline'; end if;
  perform pg_temp.expect_error(format($q$select public.api_admin_edit_zone_grids('%s', '{"remove":["%s","%s","%s"],"reason":"uji smoke","version":4}')$q$,
    z1 ->> 'id', pg_temp.g(2), pg_temp.g(4), pg_temp.g(5)), 'ZONE_EMPTY');

  v := public.api_admin_list_zones(null, 'zona', '-grid_count', 1, 20, false);
  if (v -> 'meta' ->> 'total')::int <> 3 or v -> 'data' -> 0 ->> 'name' <> 'Zona Uji Satu B' then raise exception 'list %', v; end if;
  v := public.api_admin_zone_history((z1 ->> 'id')::uuid, null, 1, 20);
  if (v -> 'meta' ->> 'total')::int < 4 then raise exception 'history %', v; end if;

  v := public.api_zones(null, false);
  if jsonb_array_length(v -> 'zones') <> 3 then raise exception 'zones %', v; end if;
  v := public.api_heatmap();
  if jsonb_array_length(v -> 'cells') < 5 or not (v -> 'zones' ? (z1 ->> 'id')) then raise exception 'heatmap %', v - 'cells'; end if;
  insert into smoke_state values ('ver_before_trip', v ->> 'heatmap_version');

  -- nelayan side
  perform pg_temp.as_user(nel);
  perform pg_temp.expect_error('select public.api_admin_list_zones()', 'FORBIDDEN');
  select jsonb_build_object('lat', st_y(geom::geometry), 'lng', st_x(geom::geometry)) into v_port
  from public.grid_cells where grid_id = pg_temp.g(6);
  perform public.api_create_boat(jsonb_build_object('engine_hp', 15, 'boat_length_m', 7, 'home_port', v_port));
  -- fish in z1 (restricted, g4) and z2 (rehab, g3), both in force since yesterday:
  -- quota is used and the trip is a violation
  v := public.api_post_trip(jsonb_build_object(
    'client_trip_id', 'c0ffee00-0000-4000-8000-0000000000c1', 'source', 'onboarding',
    'departed_at', to_char(now() - interval '10 hours', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'returned_at', to_char(now() - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'fuel_liters', 20, 'catch_kg', 40,
    'fishing_points', jsonb_build_array(
      (select jsonb_build_object('lat', st_y(geom::geometry), 'lng', st_x(geom::geometry)) from public.grid_cells where grid_id = pg_temp.g(4)),
      (select jsonb_build_object('lat', st_y(geom::geometry), 'lng', st_x(geom::geometry)) from public.grid_cells where grid_id = pg_temp.g(3)))));
  if not (v -> 'trip' ->> 'zone_violation')::boolean
     or v -> 'trip' -> 'fishing_points' -> 0 -> 'zone_at_time' ->> 'status' <> 'restricted' then
    raise exception 'trip %', v -> 'trip';
  end if;

  v_ver := (select val::bigint from smoke_state where k = 'ver_before_trip');
  v := public.api_heatmap_changes(v_ver);
  if not (v -> 'zones_upserted' ? (z1 ->> 'id'))
     or not exists (select 1 from jsonb_array_elements(v -> 'upserts') c where c ->> 0 = pg_temp.g(4) and (c ->> 1)::numeric > 0) then
    raise exception 'changes after trip %', v;
  end if;
  v := public.api_zones(null, false);
  if (select (e -> 'quota' ->> 'remaining_kg')::numeric from jsonb_array_elements(v -> 'zones') e where e ->> 'id' = z1 ->> 'id') <> 10 then
    raise exception 'quota after trip %', v;
  end if;

  v := public.api_register_device('{"fcm_token": "smoke-token-1234567890", "app_version": "1.0.0"}');
  perform public.api_unregister_device((v ->> 'device_id')::uuid);
  perform pg_temp.expect_error(format('select public.api_unregister_device(%L)', v ->> 'device_id'), 'DEVICE_NOT_FOUND');
  v := public.api_sync_seen((public.api_heatmap_version() ->> 'heatmap_version')::bigint);
  -- rehab cells are never recommendation candidates
  v := public.api_rec_context(null, false);
  if exists (select 1 from jsonb_array_elements(v -> 'candidates') c where c ->> 'grid_id' = pg_temp.g(3)) then
    raise exception 'rehab cell offered';
  end if;

  -- konservatif: dissolve z2 and check the change feed
  perform pg_temp.as_user(kons);
  v_ver := (public.api_heatmap_version() ->> 'heatmap_version')::bigint;
  z2 := public.api_admin_zone_detail((select val::uuid from smoke_state where k = 'z2'));
  v := public.api_admin_edit_zone_status((z2 ->> 'id')::uuid,
    jsonb_build_object('status', 'normal', 'reason', 'pulih', 'version', (z2 ->> 'version')::int));
  if (v ->> 'is_active')::boolean or v -> 'released_grid_ids' <> jsonb_build_array(pg_temp.g(3)) then
    raise exception 'dissolve %', v;
  end if;
  v := public.api_heatmap_changes(v_ver);
  if not (v -> 'zones_removed' ? (z2 ->> 'id')) then raise exception 'removed not reported %', v; end if;

  v := public.api_admin_refresh_heatmap('{"scope": "all", "reason": "uji smoke"}');
  if v ->> 'status' <> 'done' or public.api_admin_refresh_status((v ->> 'job_id')::uuid) ->> 'status' <> 'done' then
    raise exception 'refresh %', v;
  end if;
  v := public.api_admin_grid_detail(pg_temp.g(4));
  if v -> 'zone' ->> 'id' <> z1 ->> 'id' or (v -> 'stats' ->> 'trip_count_30d')::int <> 1 then raise exception 'grid detail %', v; end if;
  perform pg_temp.expect_error('select public.api_admin_grid_detail(''nope'')', 'GRID_INVALID');
  v := public.api_admin_stats_summary('30d');
  if (v -> 'trips' ->> 'count')::int < 1 or (v -> 'violations' ->> 'count')::int < 1 then raise exception 'stats %', v; end if;

  raise notice 'zones/heatmap part 1 passed';
end;
$$;

-- auto-flag is a system job: authenticated users cannot call it
do $$
begin
  perform public.api_internal_auto_flag(null, true);
  raise exception 'authenticated must not run the auto-flag job';
exception when insufficient_privilege then
  null;
end;
$$;

reset role;
update public.grid_stats set fatigue_index = 0.9 where grid_id = (select grid_id from smoke_cells where n = 6);
select public.api_internal_auto_flag((select array_agg(grid_id) from smoke_cells where n = 6), false);
set local role authenticated;

do $$
declare
  v jsonb;
begin
  perform pg_temp.as_user('00000000-0000-4000-8000-00000000c001');
  v := public.api_admin_list_flags();
  if not exists (select 1 from jsonb_array_elements(v -> 'data') f where f ->> 'grid_id' = pg_temp.g(6)) then
    raise exception 'flag not listed %', v;
  end if;
  v := public.api_admin_dismiss_flags(jsonb_build_object('grid_ids', jsonb_build_array(pg_temp.g(6), pg_temp.g(1)), 'reason', 'musiman'));
  if v -> 'dismissed_grid_ids' <> jsonb_build_array(pg_temp.g(6)) or v -> 'skipped_grid_ids' <> jsonb_build_array(pg_temp.g(1)) then
    raise exception 'dismiss %', v;
  end if;
  raise notice 'zones/heatmap smoke test passed';
end;
$$;

rollback;
