-- Execute against the REEFISH database after applying
-- 20261016001628_restore_fixed_500m_grid.sql. Plain SQL for Supabase MCP
-- execute_sql; all synthetic auth and restriction rows roll back at the end.
begin;

-- Catalog and static-grid assertions run with the migration owner.
do $test$
declare
  v_geom extensions.geometry;
begin
  if to_regprocedure('public.create_grid_definition(text,integer,text)') is not null
     or to_regprocedure('public.preview_grid_definition(text,text)') is not null
     or to_regprocedure('public.publish_grid_definition(text,text,text,boolean)') is not null
     or to_regprocedure('reefish_private.impl_create_grid_definition(text,integer,text)') is not null
     or to_regprocedure('reefish_private.impl_preview_grid_definition(text,text)') is not null
     or to_regprocedure('reefish_private.impl_publish_grid_definition(text,text,text,boolean)') is not null then
    raise exception 'Dynamic grid creation, preview, or publishing RPCs remain installed';
  end if;
  if to_regprocedure('public.get_grid_lock_snapshot(text)') is null
     or to_regprocedure('public.set_grid_lock(text,text,boolean,text,text)') is null
     or to_regprocedure('public.validate_fishing_grid_selection(text,text)') is null then
    raise exception 'Fixed 500 m RPC signatures were not restored';
  end if;
  if (select a.active_grid_id from public.map_areas a where a.id='east-java-pilot')
       is distinct from 'tp-id-utm49s-500m:v2'
     or (select g.cell_size_m from public.grid_definitions g
       where g.area_id='east-java-pilot' and g.id='tp-id-utm49s-500m:v2') <> 500 then
    raise exception 'The original 500 m grid identity or active pointer changed';
  end if;

  begin
    insert into public.grid_definitions(area_id,id,cell_size_m,srid,origin_x_m,origin_y_m,bounds,state)
    values('east-java-pilot','fixed-grid-test-invalid',1000,32749,0,0,
      '[112.25,-9.15,113.10,-8.35]'::jsonb,'draft');
    raise exception 'A non-500 m or draft grid definition unexpectedly passed the fixed-grid check';
  exception when check_violation then null;
  end;

  v_geom := reefish_private.grid_cell_geom(
    'east-java-pilot','tp-id-utm49s-500m:v2','tp-id-utm49s-500m:v2:rp18134:cp1370');
  if extensions.ST_SRID(v_geom) <> 32749
     or abs(extensions.ST_XMax(v_geom)-extensions.ST_XMin(v_geom)-500) > 0.001
     or abs(extensions.ST_YMax(v_geom)-extensions.ST_YMin(v_geom)-500) > 0.001
     or not extensions.ST_Equals(v_geom,extensions.ST_MakeEnvelope(685000,9067000,685500,9067500,32749))
     or not reefish_private.cell_intersects_area('east-java-pilot','tp-id-utm49s-500m:v2',
       'tp-id-utm49s-500m:v2:rp18134:cp1370') then
    raise exception 'Legacy cell geometry must remain a 500 m EPSG:32749 square at origin 0';
  end if;
end
$test$;

insert into auth.users (
  id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
)
values(
  'd6000000-0000-4000-8000-000000000001','authenticated','authenticated',
  'fixed-grid-admin@example.invalid','',pg_catalog.now(),'{}'::jsonb,'{}'::jsonb,
  pg_catalog.now(),pg_catalog.now()
);
insert into public.map_area_admins(area_id,user_id)
values('east-java-pilot','d6000000-0000-4000-8000-000000000001');
select pg_catalog.set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000001',true);
set local role authenticated;

-- Since 20261016101000_rehab_lock the lock snapshot mirrors rehab zones and set_grid_lock is retired
-- (team decision 2026-10-16; rehab scenarios are tested in zones_heatmap.sql).
do $test$
declare
  v_cell_id text := 'tp-id-utm49s-500m:v2:rp18134:cp1370';
  v_snapshot jsonb;
begin
  v_snapshot := public.get_grid_lock_snapshot('east-java-pilot');
  if (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(v_snapshot)) <> 5
     or v_snapshot ? 'grid'
     or v_snapshot ->> 'version' !~ '^[0-9]+$'
     or v_snapshot ->> 'is_demo' <> 'false'
     -- only rehab cells may appear (e.g. from demo data); no legacy administrative locks
     or exists (select 1 from pg_catalog.jsonb_array_elements(v_snapshot -> 'locks') l
                where l ->> 'reason' not like 'Rehab: %')
     or (v_snapshot ->> 'expires_at') <= (v_snapshot ->> 'fetched_at') then
    raise exception 'Fixed snapshot must keep the legacy five-field contract: %',v_snapshot;
  end if;

  begin
    perform public.set_grid_lock('east-java-pilot',v_cell_id,true,'Reviewed closure','1');
    raise exception 'set_grid_lock must be retired';
  exception when raise_exception then
    if sqlerrm <> 'DEPRECATED_USE_ZONES' then raise; end if;
  end;

  if not public.validate_fishing_grid_selection('east-java-pilot',v_cell_id) then
    raise exception 'An in-area fixed 500 m cell outside any rehab zone should pass validation';
  end if;
  begin
    perform public.validate_fishing_grid_selection('east-java-pilot','tp-id-utm49s-500m:v2:rp1:cp1');
    raise exception 'A cell outside the map area unexpectedly passed validation';
  exception when invalid_parameter_value then null;
  end;
end
$test$;

rollback;
