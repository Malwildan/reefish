-- Execute against a disposable database after applying
-- 20261016000020_dynamic_grid_definitions.sql. This is plain SQL suitable for
-- Supabase MCP execute_sql: it uses no psql commands and rolls every fixture back.
begin;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  'd6000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
  'grid-test-admin@example.invalid', '', pg_catalog.now(), '{}'::jsonb, '{}'::jsonb,
  pg_catalog.now(), pg_catalog.now()
);

insert into public.map_area_admins(area_id,user_id)
values('east-java-pilot','d6000000-0000-4000-8000-000000000001');

select pg_catalog.set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000001',true);
set local role authenticated;

do $test$
declare
  v_snapshot jsonb;
  v_cell_1 text := 'tp-id-utm49s-500m:v2:rp18134:cp1370';
  v_cell_2 text := 'tp-id-utm49s-500m:v2:rp18135:cp1370';
  v_neighbor text := 'tp-id-utm49s-500m:v2:rp18134:cp1371';
  v_1000_cell text := 'tp-id-utm49s-1000m:v1:rp9067:cp685';
  v_new_grid_id text;
  v_result jsonb;
begin
  v_snapshot := public.get_grid_lock_snapshot('east-java-pilot');
  if (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(v_snapshot)) <> 6
     or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(v_snapshot -> 'grid')) <> 7
     or v_snapshot #>> '{grid,id}' <> 'tp-id-utm49s-500m:v2'
     or v_snapshot #>> '{grid,cell_size_m}' <> '500'
     or v_snapshot ->> 'version' <> '1'
     or v_snapshot ->> 'is_demo' <> 'false'
     or pg_catalog.jsonb_array_length(v_snapshot -> 'locks') <> 0
     or (v_snapshot ->> 'expires_at') <= (v_snapshot ->> 'fetched_at') then
    raise exception 'Initial snapshot does not match the grid contract: %',v_snapshot;
  end if;

  if public.set_grid_lock('east-java-pilot',v_cell_1,true,'North closure','1') <> '2'
     or public.set_grid_lock('east-java-pilot',v_cell_2,true,'South closure','2') <> '3' then
    raise exception 'Expected two source-cell restriction mutations to advance the version';
  end if;

  -- A shared edge is not a positive-area intersection. The east neighbor must
  -- remain absent from the 500 m snapshot even though both source cells are locked.
  v_snapshot := public.get_grid_lock_snapshot('east-java-pilot');
  if pg_catalog.jsonb_array_length(v_snapshot -> 'locks') <> 2
     or exists (select 1 from pg_catalog.jsonb_array_elements(v_snapshot -> 'locks') as elem(lock_json)
        where lock_json ->> 'cell_id' = v_neighbor) then
    raise exception 'Grid lock derivation included a shared-edge neighbor: %',v_snapshot;
  end if;

  begin
    perform public.set_grid_lock('east-java-pilot',v_cell_1,true,'Stale writer','1');
    raise exception 'Stale area version unexpectedly succeeded';
  exception when serialization_failure then null;
  end;

  v_result := public.create_grid_definition('east-java-pilot',1500,'3');
  v_new_grid_id := v_result #>> '{grid,id}';
  if v_new_grid_id is null or v_new_grid_id !~ '^grid-[0-9a-f-]{36}$'
     or (v_result #>> '{grid,cell_size_m}') <> '1500'
     or v_result ->> 'version' <> '4' then
    raise exception 'Grid creation must return a new opaque draft definition: %',v_result;
  end if;

  v_result := public.preview_grid_definition('east-java-pilot',v_new_grid_id);
  if v_result #>> '{grid,id}' <> v_new_grid_id
     or v_result ->> 'version' <> '4'
     or (v_result ->> 'candidate_cell_count')::bigint < (v_result ->> 'in_area_cell_count')::bigint
     or (v_result ->> 'affected_lock_count')::bigint < 1 then
    raise exception 'Draft preview must report bounded cell and derived-lock counts: %',v_result;
  end if;

  -- Publishing with active restrictions requires an explicit reviewed confirmation.
  begin
    perform public.publish_grid_definition('east-java-pilot','tp-id-utm49s-1000m:v1','4',false);
    raise exception 'Publishing active restrictions without confirmation unexpectedly succeeded';
  exception when invalid_parameter_value then null;
  end;
  v_result := public.publish_grid_definition('east-java-pilot','tp-id-utm49s-1000m:v1','4',true);
  if v_result ->> 'version' <> '5'
     or v_result ->> 'previous_grid_id' <> 'tp-id-utm49s-500m:v2' then
    raise exception 'Publishing must activate the new grid and archive the previous immutable definition: %',v_result;
  end if;
  if public.get_grid_lock_snapshot('east-java-pilot') #>> '{grid,id}' <> 'tp-id-utm49s-1000m:v1' then
    raise exception 'The default snapshot must follow the active 1000 m definition';
  end if;

  v_snapshot := public.get_grid_lock_snapshot('east-java-pilot','tp-id-utm49s-1000m:v1');
  if pg_catalog.jsonb_array_length(v_snapshot -> 'locks') <> 1
     or v_snapshot #>> '{locks,0,cell_id}' <> v_1000_cell
     or position('North closure' in (v_snapshot #>> '{locks,0,reason}')) = 0
     or position('South closure' in (v_snapshot #>> '{locks,0,reason}')) = 0 then
    raise exception 'Both 500 m restrictions must derive to the same 1000 m cell: %',v_snapshot;
  end if;

  begin
    perform public.set_grid_lock('east-java-pilot',v_1000_cell,false,'Remove one','5','tp-id-utm49s-1000m:v1');
    raise exception 'Unlocking a cell that ambiguously covers two source restrictions unexpectedly succeeded';
  exception when invalid_parameter_value then null;
  end;

  -- Exact source removal removes only its own polygon; its neighbor source remains.
  if public.set_grid_lock('east-java-pilot',v_cell_1,false,'Source reviewed','5','tp-id-utm49s-500m:v2') <> '6' then
    raise exception 'Exact source unlock should advance the area version';
  end if;
  begin
    perform public.validate_fishing_grid_selection('east-java-pilot',v_cell_2,'tp-id-utm49s-500m:v2');
    raise exception 'The second source restriction was removed with the first';
  exception when check_violation then null;
  end;
  if not public.validate_fishing_grid_selection('east-java-pilot',v_cell_1,'tp-id-utm49s-500m:v2') then
    raise exception 'Exact source unlock should leave its non-overlapping 500 m cell selectable';
  end if;
  if public.set_grid_lock('east-java-pilot',v_cell_2,false,'Source reviewed','6','tp-id-utm49s-500m:v2') <> '7' then
    raise exception 'Second exact source unlock should advance the area version';
  end if;

  -- A 1000 m restriction covers multiple 500 m cells. Trying to unlock it by
  -- selecting one 500 m child must fail without deleting the larger polygon.
  if public.set_grid_lock('east-java-pilot',v_1000_cell,true,'Reviewed coarse restriction','7','tp-id-utm49s-1000m:v1') <> '8' then
    raise exception 'Expected a 1000 m source restriction';
  end if;
  begin
    perform public.set_grid_lock('east-java-pilot',v_cell_1,false,'Partial child unlock','8','tp-id-utm49s-500m:v2');
    raise exception 'A child-cell unlock unexpectedly removed a larger source restriction';
  exception when invalid_parameter_value then null;
  end;
  v_snapshot := public.get_grid_lock_snapshot('east-java-pilot','tp-id-utm49s-1000m:v1');
  if v_snapshot ->> 'version' <> '8' or pg_catalog.jsonb_array_length(v_snapshot -> 'locks') <> 1 then
    raise exception 'A rejected derived unlock must preserve the source restriction: %',v_snapshot;
  end if;

  v_result := public.publish_grid_definition('east-java-pilot',v_new_grid_id,'8',true);
  if v_result ->> 'version' <> '9'
     or v_result ->> 'previous_grid_id' <> 'tp-id-utm49s-1000m:v1' then
    raise exception 'Second publish must archive the previous published grid: %',v_result;
  end if;
  if public.get_grid_lock_snapshot('east-java-pilot') #>> '{grid,id}' <> v_new_grid_id then
    raise exception 'The default snapshot must follow the newly active 1500 m definition';
  end if;

  if public.set_grid_lock('east-java-pilot',v_1000_cell,false,'Exact coarse source removal','9','tp-id-utm49s-1000m:v1') <> '10' then
    raise exception 'Unlocking the exact coarse source should remove the original polygon';
  end if;
  v_snapshot := public.get_grid_lock_snapshot('east-java-pilot','tp-id-utm49s-500m:v2');
  if v_snapshot ->> 'version' <> '10' or pg_catalog.jsonb_array_length(v_snapshot -> 'locks') <> 0 then
    raise exception 'Removing the exact source should clear its derived locks in every grid: %',v_snapshot;
  end if;

  begin
    perform public.validate_fishing_grid_selection('east-java-pilot','tp-id-utm49s-500m:v2:rp0:cp0','tp-id-utm49s-500m:v2');
    raise exception 'Out-of-area cell unexpectedly passed selection validation';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.validate_fishing_grid_selection('east-java-pilot','tp-id-utm49s-500m:v2:rp01:cp0','tp-id-utm49s-500m:v2');
    raise exception 'Non-canonical cell ID unexpectedly passed validation';
  exception when invalid_parameter_value then null;
  end;
end
$test$;

-- An authenticated user without trusted area membership cannot mutate, even when
-- the requested grid and version are otherwise valid.
select pg_catalog.set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000002',true);
do $test$
begin
  begin
    perform public.set_grid_lock('east-java-pilot','tp-id-utm49s-500m:v2:rp18134:cp1370',true,'Non-admin','10');
    raise exception 'Non-admin unexpectedly changed a restriction';
  exception when insufficient_privilege then null;
  end;
end
$test$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub','',true);
set local role anon;
do $test$
begin
  begin
    perform public.set_grid_lock('east-java-pilot','tp-id-utm49s-500m:v2:rp18134:cp1370',true,'Anonymous','10');
    raise exception 'Anonymous caller unexpectedly executed an admin RPC';
  exception when insufficient_privilege then null;
  end;
end
$test$;
reset role;

do $test$
begin
  begin
    update public.grid_definitions set id=id || '-mutated'
      where area_id='east-java-pilot' and id='tp-id-utm49s-500m:v2';
    raise exception 'Grid identity unexpectedly changed';
  exception when object_not_in_prerequisite_state then null;
  end;
end
$test$;

rollback;
