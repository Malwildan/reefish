-- Focused rollback-only integration test for the Journey RPCs.
-- Run after migrations 20261016100000..20261016100500 and grid_cells import.
-- This intentionally stops before recommendation/heatmap behavior, which is
-- introduced by later migrations. No fixture account, boat, or trip is kept.
begin;
set local search_path = public, extensions, pg_temp;

insert into auth.users (id, email, aud, role, raw_user_meta_data, phone)
values
  ('00000000-0000-4000-8000-0000000000a1', 'journey-a@phone.reefish.test',
   'authenticated', 'authenticated', '{"role":"konservatif","full_name":"Journey A"}', '6280000000001'),
  ('00000000-0000-4000-8000-0000000000b2', 'journey-b@phone.reefish.test',
   'authenticated', 'authenticated', '{"role":"konservatif","full_name":"Journey B"}', '6280000000002');

create temp table journey_test_port on commit drop as
select st_y(geom::geometry) as lat, st_x(geom::geometry) as lng
from public.grid_cells
order by grid_id
limit 1;
grant select on journey_test_port to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}';

do $test$
declare
  v_port jsonb := (select jsonb_build_object('lat', lat, 'lng', lng) from journey_test_port);
  v_me jsonb;
  v_boat jsonb;
  v_trip_input jsonb;
  v_post jsonb;
  v_replay jsonb;
  v_list jsonb;
  v_detail jsonb;
  v_trip_id uuid;
  v_own_count integer;
  v_other_count integer;
begin
  if v_port is null then
    raise exception 'Journey test requires imported grid_cells';
  end if;

  -- Signup metadata cannot assign the privileged role.
  if (select role from public.profiles where id = auth.uid()) <> 'nelayan' then
    raise exception 'signup role metadata promoted Journey A';
  end if;

  v_me := public.api_me();
  if v_me ->> 'next_step' <> 'boat' or v_me ->> 'role' <> 'nelayan' then
    raise exception 'api_me before boat returned unexpected state: %', v_me;
  end if;

  -- Authenticated clients can read only their own profile and cannot write
  -- directly around the RPC validation path.
  if (select count(*) from public.profiles) <> 1 then
    raise exception 'profile RLS exposed another user profile';
  end if;

  begin
    insert into public.boats (user_id, name, engine_hp, boat_length_m, fuel_type, home_port, is_default)
    values (auth.uid(), 'direct write must fail', 15, 7, 'solar',
      st_setsrid(st_makepoint((v_port ->> 'lng')::float8, (v_port ->> 'lat')::float8), 4326)::extensions.geography,
      true);
    raise exception 'direct client boat write unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_boat := public.api_create_boat(jsonb_build_object(
    'name', 'KM Journey Test', 'engine_hp', 15, 'boat_length_m', 7,
    'fuel_type', 'solar', 'home_port', v_port));
  if (v_boat ->> 'is_default')::boolean is not true then
    raise exception 'api_create_boat did not return the default boat: %', v_boat;
  end if;
  if public.api_me() ->> 'next_step' <> 'first_trip' then
    raise exception 'api_me after boat did not advance to first_trip';
  end if;

  v_trip_input := jsonb_build_object(
    'client_trip_id', 'c0ffee00-0000-4000-8000-0000000000a1',
    'source', 'onboarding',
    'departed_at', to_char((now() - interval '10 hours') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'returned_at', to_char((now() - interval '2 hours') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'fuel_liters', 25.5,
    'catch_kg', 40,
    'fishing_points', jsonb_build_array(v_port || jsonb_build_object('reported_catch_kg', null)));

  v_post := public.api_post_trip(v_trip_input);
  if coalesce((v_post ->> 'replay')::boolean, true)
     or (v_post -> 'user' ->> 'onboarded')::boolean is not true
     or (v_post -> 'trip' -> 'fishing_points' -> 0 ->> 'allocated_catch_kg')::numeric <> 40 then
    raise exception 'api_post_trip onboarding result was unexpected: %', v_post;
  end if;
  v_trip_id := (v_post -> 'trip' ->> 'id')::uuid;

  v_replay := public.api_post_trip(v_trip_input);
  if (v_replay ->> 'replay')::boolean is not true
     or (v_replay -> 'trip' ->> 'id')::uuid <> v_trip_id then
    raise exception 'stable client_trip_id did not replay the stored trip: %', v_replay;
  end if;

  v_list := public.api_list_trips(p_page := 1, p_limit := 20, p_sort := '-departed_at');
  if (v_list -> 'meta' ->> 'total')::integer <> 1
     or jsonb_array_length(v_list -> 'data') <> 1 then
    raise exception 'api_list_trips did not return exactly the submitted trip: %', v_list;
  end if;

  v_detail := public.api_trip_detail(v_trip_id, 'none');
  if (v_detail ->> 'id')::uuid <> v_trip_id
     or v_detail -> 'track' <> 'null'::jsonb then
    raise exception 'api_trip_detail returned unexpected data: %', v_detail;
  end if;

  -- A second authenticated user sees no rows and cannot fetch the first
  -- user's detail through the definer RPC.
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-0000000000b2","role":"authenticated"}', true);
  if (select count(*) from public.profiles) <> 1 then
    raise exception 'profile RLS did not scope reads to the second user';
  end if;
  select count(*) into v_own_count from public.trips;
  if v_own_count <> 0 then
    raise exception 'trip RLS exposed the first user trip to the second user';
  end if;
  v_list := public.api_list_trips(p_page := 1, p_limit := 20, p_sort := '-departed_at');
  if (v_list -> 'meta' ->> 'total')::integer <> 0 then
    raise exception 'api_list_trips exposed another user trip: %', v_list;
  end if;
  begin
    perform public.api_trip_detail(v_trip_id, 'none');
    raise exception 'api_trip_detail unexpectedly returned another user trip';
  exception when raise_exception then
    if sqlerrm <> 'TRIP_NOT_FOUND' then raise; end if;
  end;

  raise notice 'Journey RPC integration test passed';
end;
$test$;

rollback;
select 'Journey RPC integration passed; all fixtures rolled back' as result;
