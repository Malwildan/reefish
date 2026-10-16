-- Smoke test for migration 0006 (nelayan RPCs). Not a migration: run it in the SQL editor or with
-- psql "$SUPABASE_DB_URL" -f supabase/tests/nelayan.sql after `db push` and the grid import.
-- Everything runs in one transaction and is rolled back. Any failed check raises an exception.
begin;

insert into auth.users (id, email, aud, role)
values ('00000000-0000-4000-8000-0000000000aa', 'smoke@phone.reefish.app', 'authenticated', 'authenticated');

create temp table smoke_port on commit drop as
select st_y(geom::geometry) as lat, st_x(geom::geometry) as lng from public.grid_cells limit 1;
grant select on smoke_port to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000aa", "role": "authenticated"}';

do $$
declare
  v_port jsonb := (select jsonb_build_object('lat', lat, 'lng', lng) from smoke_port);
  v jsonb;
  v_trip jsonb;
  v_ok boolean;
begin
  if v_port is null then raise exception 'import grid_cells first'; end if;

  v := public.api_me();
  if v ->> 'next_step' <> 'boat' then raise exception 'me before boat: %', v; end if;

  -- validation errors carry the code in the message
  begin
    perform public.api_create_boat('{"engine_hp": 0}');
    raise exception 'expected VALIDATION_ERROR';
  exception when raise_exception then
    if sqlerrm <> 'VALIDATION_ERROR' then raise; end if;
  end;

  v := public.api_create_boat(jsonb_build_object('name', 'KM Uji', 'engine_hp', 15, 'boat_length_m', 7, 'home_port', v_port));
  if (v ->> 'is_default')::boolean is not true then raise exception 'boat: %', v; end if;

  begin
    perform public.api_create_boat(jsonb_build_object('engine_hp', 15, 'boat_length_m', 7, 'home_port', v_port));
    raise exception 'expected BOAT_LIMIT_REACHED';
  exception when raise_exception then
    if sqlerrm <> 'BOAT_LIMIT_REACHED' then raise; end if;
  end;

  if public.api_me() ->> 'next_step' <> 'first_trip' then raise exception 'me after boat'; end if;

  v_trip := jsonb_build_object(
    'client_trip_id', 'c0ffee00-0000-4000-8000-000000000001', 'source', 'onboarding',
    'departed_at', to_char(now() - interval '10 hours', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'returned_at', to_char(now() - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'fuel_liters', 25.5, 'catch_kg', 40,
    'fishing_points', jsonb_build_array(v_port || jsonb_build_object('reported_catch_kg', null))
  );
  v := public.api_post_trip(v_trip);
  if (v ->> 'replay')::boolean or (v -> 'user' ->> 'onboarded')::boolean is not true
     or (v -> 'trip' -> 'fishing_points' -> 0 ->> 'allocated_catch_kg')::numeric <> 40 then
    raise exception 'onboarding trip: %', v;
  end if;

  v := public.api_post_trip(v_trip);
  if not (v ->> 'replay')::boolean then raise exception 'replay not detected: %', v; end if;

  begin
    perform public.api_post_trip(v_trip || '{"client_trip_id": "c0ffee00-0000-4000-8000-000000000002"}');
    raise exception 'expected ALREADY_ONBOARDED';
  exception when raise_exception then
    if sqlerrm <> 'ALREADY_ONBOARDED' then raise; end if;
  end;

  v := public.api_post_trip(v_trip || '{"client_trip_id": "c0ffee00-0000-4000-8000-000000000003", "source": "manual", "fuel_liters": 20}');
  if (v -> 'trip' ->> 'fuel_efficiency_pct')::numeric <= 0 then raise exception 'efficiency vs baseline: %', v; end if;

  v := public.api_list_trips();
  if (v -> 'meta' ->> 'total')::int <> 2 or jsonb_array_length(v -> 'data') <> 2 then raise exception 'list: %', v; end if;

  v := public.api_trip_detail((v -> 'data' -> 0 ->> 'id')::uuid, 'none');
  if v -> 'track' <> 'null'::jsonb and v -> 'track' is not null then raise exception 'detail: %', v; end if;

  v := public.api_rec_context(null, false);
  if v -> 'cached' <> 'null'::jsonb or v -> 'boat' is null then raise exception 'rec context: %', v; end if;

  if jsonb_array_length(v -> 'candidates') > 0 then
    v := public.api_save_recommendations(jsonb_build_object(
      'for_date', v ->> 'for_date', 'fuel_per_km', 1, 'unavailable_types', '[]',
      'items', jsonb_build_array(jsonb_build_object(
        'type', 'fuel_saving', 'grid_id', v -> 'candidates' -> 0 ->> 'grid_id',
        'predicted_fuel_liters', 10, 'confidence', 0.3, 'reason', 'uji'))
    ));
    if jsonb_array_length(v -> 'items') <> 1 then raise exception 'save recs: %', v; end if;
    if public.api_rec_context(null, false) -> 'cached' = 'null'::jsonb then raise exception 'cache not used'; end if;
  else
    raise notice 'no candidates near the test port: recommendation save not exercised';
  end if;

  v_ok := public.api_in_pilot((v_port ->> 'lat')::float8, (v_port ->> 'lng')::float8);
  if not v_ok then raise exception 'port should be in pilot'; end if;
  if public.api_mobile_config() -> 'sailing' is null then raise exception 'mobile config'; end if;

  raise notice 'nelayan smoke test passed';
end;
$$;

rollback;
