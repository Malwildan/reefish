-- Run only against a disposable local Supabase database with the migration applied:
--   psql "$LOCAL_DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/supabase/tests/grid_locks.sql
-- The test uses one existing local auth.users identity, creates all fixtures in a
-- transaction, and rolls the transaction back. It sends no OTP and changes no hosted data.
\set ON_ERROR_STOP on

begin;

select id as grid_lock_test_user_id
  from auth.users
 order by created_at nulls last, id
 limit 1
\gset

\if :{?grid_lock_test_user_id}
\else
  \echo 'A local auth.users fixture is required to run grid_locks.sql.'
  \quit 3
\endif

create temporary table grid_lock_test_fixture (cell_id text not null);

do $test$
declare
  v_postgis_schema text;
  v_x double precision;
  v_y double precision;
  v_row bigint;
  v_col bigint;
  v_cell_id text;
begin
  select n.nspname into v_postgis_schema
    from pg_catalog.pg_extension e
    join pg_catalog.pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'postgis';
  if v_postgis_schema is null then raise exception 'PostGIS is required'; end if;

  execute pg_catalog.format(
    'select %1$I.ST_X(p), %1$I.ST_Y(p)
       from (select %1$I.ST_Transform(%1$I.ST_SetSRID(%1$I.ST_Point(112.70, -8.70), 4326), 32749) p) q',
    v_postgis_schema
  ) into v_x, v_y;

  v_row := pg_catalog.floor(v_y / 500)::bigint;
  v_col := pg_catalog.floor(v_x / 500)::bigint;
  v_cell_id := 'tp-id-utm49s-500m:v2:r'
    || case when v_row < 0 then 'n' || pg_catalog.abs(v_row)::text else 'p' || v_row::text end
    || ':c'
    || case when v_col < 0 then 'n' || pg_catalog.abs(v_col)::text else 'p' || v_col::text end;
  insert into grid_lock_test_fixture (cell_id) values (v_cell_id);
end
$test$;

select cell_id as grid_lock_test_cell_id from grid_lock_test_fixture \gset

insert into public.map_areas (id, bounds, version)
values ('grid-lock-test', '[112.25, -9.15, 113.10, -8.35]'::jsonb, 1);

do $test$
begin
  if not public.grid_lock_cell_intersects_area('grid-lock-test', (select cell_id from grid_lock_test_fixture)) then
    raise exception 'Generated test cell must intersect the pilot bounds';
  end if;
end
$test$;

insert into public.map_area_admins (area_id, user_id)
values ('grid-lock-test', :'grid_lock_test_user_id'::uuid);

select pg_catalog.set_config('request.jwt.claim.sub', :'grid_lock_test_user_id', true);
select pg_catalog.set_config('test.grid_lock_cell_id', :'grid_lock_test_cell_id', true);
set local role authenticated;

do $test$
declare
  v_snapshot jsonb;
begin
  v_snapshot := public.get_grid_lock_snapshot('grid-lock-test');
  if v_snapshot ->> 'version' <> '1'
     or v_snapshot ->> 'is_demo' <> 'false'
     or pg_catalog.jsonb_array_length(v_snapshot -> 'locks') <> 0
     or (v_snapshot ->> 'expires_at') <= (v_snapshot ->> 'fetched_at') then
    raise exception 'Initial snapshot shape or freshness is incorrect: %', v_snapshot;
  end if;
end
$test$;

-- A signed-in non-admin has no mutation authority even with a valid cell/version.
reset role;
delete from public.map_area_admins
 where area_id = 'grid-lock-test' and user_id = :'grid_lock_test_user_id'::uuid;
set local role authenticated;

do $test$
begin
  begin
    perform public.set_grid_lock(
      'grid-lock-test', pg_catalog.current_setting('test.grid_lock_cell_id'), true, 'Unauthorized', '1'
    );
    raise exception 'Non-admin unexpectedly changed a grid lock';
  exception when insufficient_privilege then
    null;
  end;
end
$test$;

reset role;
insert into public.map_area_admins (area_id, user_id)
values ('grid-lock-test', :'grid_lock_test_user_id'::uuid);
set local role authenticated;

-- Authenticated users cannot mutate the private lock table directly.
do $test$
begin
  begin
    insert into public.grid_locks (area_id, cell_id, reason, updated_by)
    values ('grid-lock-test', pg_catalog.current_setting('test.grid_lock_cell_id'), 'direct write', auth.uid());
    raise exception 'Direct grid_locks write unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end
$test$;

select public.set_grid_lock(
  'grid-lock-test', :'grid_lock_test_cell_id', true, 'Administrative review', '1'
);

-- Reusing the observed version models a second writer that raced the first.
do $test$
begin
  begin
    perform public.set_grid_lock(
      'grid-lock-test', pg_catalog.current_setting('test.grid_lock_cell_id'), true, 'Second writer', '1'
    );
    raise exception 'Stale version unexpectedly succeeded';
  exception when serialization_failure then
    null;
  end;
end
$test$;

do $test$
declare
  v_snapshot jsonb;
begin
  v_snapshot := public.get_grid_lock_snapshot('grid-lock-test');
  if v_snapshot ->> 'version' <> '2'
     or pg_catalog.jsonb_array_length(v_snapshot -> 'locks') <> 1
     or v_snapshot #>> '{locks,0,reason}' <> 'Administrative review' then
    raise exception 'Locked cell must stay present in the snapshot: %', v_snapshot;
  end if;

  begin
    perform public.validate_fishing_grid_selection('grid-lock-test', pg_catalog.current_setting('test.grid_lock_cell_id'));
    raise exception 'A locked cell unexpectedly passed fishing-location validation';
  exception when check_violation then
    null;
  end;
end
$test$;

select public.set_grid_lock(
  'grid-lock-test', :'grid_lock_test_cell_id', false, 'Review complete', '2'
);

do $test$
declare
  v_snapshot jsonb;
begin
  v_snapshot := public.get_grid_lock_snapshot('grid-lock-test');
  if v_snapshot ->> 'version' <> '3'
     or pg_catalog.jsonb_array_length(v_snapshot -> 'locks') <> 0 then
    raise exception 'Unlock must remove the active lock and advance the version: %', v_snapshot;
  end if;
  if not public.validate_fishing_grid_selection('grid-lock-test', pg_catalog.current_setting('test.grid_lock_cell_id')) then
    raise exception 'An unlocked in-area cell should pass authoritative validation';
  end if;

  begin
    perform public.validate_fishing_grid_selection('grid-lock-test', 'not-a-canonical-cell');
    raise exception 'Malformed cell ID unexpectedly passed validation';
  exception when invalid_parameter_value then
    null;
  end;

  begin
    perform public.validate_fishing_grid_selection('grid-lock-test', 'tp-id-utm49s-500m:v2:rp0:cp0');
    raise exception 'Out-of-area cell unexpectedly passed validation';
  exception when invalid_parameter_value then
    null;
  end;

  begin
    perform public.set_grid_lock('unknown-test-area', pg_catalog.current_setting('test.grid_lock_cell_id'), true, 'Unknown area', '1');
    raise exception 'Unknown area unexpectedly accepted a lock';
  exception when no_data_found then
    null;
  end;
end
$test$;

reset role;

do $test$
begin
  if (select pg_catalog.count(*) from public.grid_lock_audit where area_id = 'grid-lock-test') <> 2 then
    raise exception 'Lock and unlock must each append an audit event';
  end if;
end
$test$;

rollback;
