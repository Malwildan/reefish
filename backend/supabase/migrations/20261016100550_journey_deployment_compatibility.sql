-- Forward compatibility fixes for projects that already applied the original Journey migrations.
-- This does not change grid definitions, locks, authentication providers, or role assignments.

-- Backfill profiles only for auth users missed before the signup trigger was installed.
-- Native auth phone only: remove leading plus characters, then retain valid E.164 digits.
insert into public.profiles (id, phone, full_name)
select
  u.id,
  case
    when ltrim(coalesce(u.phone, ''), '+') ~ '^[1-9][0-9]{7,14}$'
      then ltrim(u.phone, '+')
    else null
  end,
  nullif(btrim(u.raw_user_meta_data ->> 'full_name'), '')
from auth.users as u
left join public.profiles as p on p.id = u.id
where p.id is null
on conflict (id) do nothing;

create or replace function public.api_post_trip(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
  v_profile profiles;
  v_boat boats;
  v_trip trips;
  v_existing uuid;
  v_errors jsonb;
  v_item jsonb;
  v_bad jsonb;
  v_fps jsonb := p -> 'fishing_points';
  v_track jsonb := p -> 'track';
  v_has_track boolean;
  v_prev_seq numeric;
  v_dep_at timestamptz;
  v_ret_at timestamptz;
  v_dep geography;
  v_ret geography;
  v_line geometry;
  v_first geography;
  v_cut int;
  v_total_km numeric;
  v_port_km numeric;
  v_baseline numeric;
  v_constraint text;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    perform private.fail('VALIDATION_ERROR', 'Body harus objek JSON');
  end if;
  v_errors := jsonb_strip_nulls(jsonb_build_object('client_trip_id', private.bad_uuid(p -> 'client_trip_id', true)));
  if v_errors <> '{}' then
    perform private.fail('VALIDATION_ERROR', 'Data trip tidak valid', jsonb_build_object('fields', v_errors));
  end if;

  -- Idempotent replay: same client_trip_id returns the stored result and writes nothing
  select id into v_existing from trips where user_id = v_uid and client_trip_id = (p ->> 'client_trip_id')::uuid;
  if v_existing is not null then
    return private.post_trip_result(v_existing, true);
  end if;

  v_errors := jsonb_strip_nulls(jsonb_build_object(
    'source', case when coalesce(p ->> 'source', '') not in ('onboarding', 'manual', 'sailing')
      then 'onboarding, manual, atau sailing' end,
    'departure', private.bad_point(p -> 'departure', false),
    'return_point', private.bad_point(p -> 'return_point', false),
    'departed_at', private.bad_time(p -> 'departed_at', true),
    'returned_at', private.bad_time(p -> 'returned_at', true),
    'fuel_liters', private.bad_num(p, 'fuel_liters', 0, 500, true, true),
    'catch_kg', private.bad_num(p, 'catch_kg', 0, 5000, true),
    'fishing_points', case
      when coalesce(jsonb_typeof(v_fps), '') <> 'array' then 'wajib array 1 sampai 50 titik'
      when jsonb_array_length(v_fps) not between 1 and 50 then 'wajib array 1 sampai 50 titik' end,
    'track', case
      when coalesce(jsonb_typeof(v_track), 'null') not in ('array', 'null') then 'harus array'
      when p ->> 'source' = 'sailing' and coalesce(jsonb_typeof(v_track), '') <> 'array' then 'wajib untuk sailing'
      when p ->> 'source' = 'sailing' and jsonb_array_length(v_track) < 2 then 'minimal 2 titik'
      when jsonb_typeof(v_track) = 'array' and jsonb_array_length(v_track) > 5000 then 'maks 5000 titik' end,
    'selected_recommendation_id', private.bad_uuid(p -> 'selected_recommendation_id', false),
    'notes', case
      when jsonb_typeof(p -> 'notes') not in ('string', 'null') then 'harus teks'
      when length(p ->> 'notes') > 500 then 'maks 500 karakter' end
  ));

  if jsonb_typeof(v_fps) = 'array' and jsonb_array_length(v_fps) <= 50 then
    for i in 0 .. jsonb_array_length(v_fps) - 1 loop
      v_item := v_fps -> i;
      v_bad := jsonb_strip_nulls(jsonb_build_object(
        'point', private.bad_point(v_item, true),
        'started_at', private.bad_time(v_item -> 'started_at', false),
        'ended_at', private.bad_time(v_item -> 'ended_at', false),
        'flag_source', case when coalesce(v_item ->> 'flag_source', 'manual')
          not in ('manual', 'user_confirmed', 'auto_timeout', 'rec_radius')
          then 'manual, user_confirmed, auto_timeout, atau rec_radius' end,
        'recommendation_id', private.bad_uuid(v_item -> 'recommendation_id',
          coalesce(v_item ->> 'flag_source' = 'rec_radius', false)),
        'reported_catch_kg', private.bad_num(v_item, 'reported_catch_kg', 0, 5000, false)
      ));
      if v_bad <> '{}' then
        v_errors := v_errors || jsonb_build_object(format('fishing_points[%s]', i), v_bad);
      end if;
    end loop;
  end if;

  v_has_track := jsonb_typeof(v_track) = 'array' and jsonb_array_length(v_track) between 1 and 5000;
  if v_has_track then
    for i in 0 .. jsonb_array_length(v_track) - 1 loop
      v_item := v_track -> i;
      v_bad := jsonb_strip_nulls(jsonb_build_object(
        'seq', case
          when coalesce(jsonb_typeof(v_item -> 'seq'), '') <> 'number' then 'harus bilangan bulat'
          when (v_item ->> 'seq')::numeric % 1 <> 0 or abs((v_item ->> 'seq')::numeric) > 1000000000
            then 'harus bilangan bulat'
          when (v_item ->> 'seq')::numeric <= v_prev_seq then 'harus unik dan naik' end,
        'point', private.bad_point(v_item, true),
        'recorded_at', private.bad_time(v_item -> 'recorded_at', true),
        'speed_ms', private.bad_num(v_item, 'speed_ms', 0, 100, false),
        'accuracy_m', private.bad_num(v_item, 'accuracy_m', 0, 100000, false)
      ));
      if v_bad <> '{}' then
        v_errors := v_errors || jsonb_build_object(format('track[%s]', i), v_bad);
        exit when (select count(*) from jsonb_object_keys(v_errors)) >= 20;  -- keep the error body small
      end if;
      if jsonb_typeof(v_item -> 'seq') = 'number' then
        v_prev_seq := (v_item ->> 'seq')::numeric;
      end if;
    end loop;
  end if;

  if v_errors <> '{}' then
    perform private.fail('VALIDATION_ERROR', 'Data trip tidak valid', jsonb_build_object('fields', v_errors));
  end if;

  -- Source rules (AGENTS.md 12.B.4)
  select * into v_profile from profiles where id = v_uid;
  select * into v_boat from boats where user_id = v_uid and is_default and deleted_at is null;
  if v_boat.id is null then
    perform private.fail('BOAT_REQUIRED', 'Isi data kapal terlebih dahulu');
  end if;
  if p ->> 'source' = 'onboarding' and v_profile.onboarded then
    perform private.fail('ALREADY_ONBOARDED', 'Trip pertama sudah pernah dikirim');
  end if;
  if p ->> 'source' <> 'onboarding' and not v_profile.onboarded then
    perform private.fail('ONBOARDING_REQUIRED', 'Kirim trip pertama (onboarding) terlebih dahulu');
  end if;

  -- Time range
  v_dep_at := (p ->> 'departed_at')::timestamptz;
  v_ret_at := (p ->> 'returned_at')::timestamptz;
  if v_ret_at <= v_dep_at or v_ret_at - v_dep_at > interval '72 hours' or v_ret_at > now() + interval '10 minutes' then
    perform private.fail('INVALID_TIME_RANGE',
      'Jam pulang harus setelah jam berangkat, maksimal 72 jam, dan tidak di masa depan');
  end if;
  select coalesce(jsonb_agg(e.i - 1), '[]') into v_bad
  from jsonb_array_elements(v_fps) with ordinality e (v, i)
  where (e.v ->> 'started_at')::timestamptz not between v_dep_at and v_ret_at
     or (e.v ->> 'ended_at')::timestamptz not between v_dep_at and v_ret_at
     or (e.v ->> 'ended_at')::timestamptz <= (e.v ->> 'started_at')::timestamptz;
  if v_bad <> '[]' then
    perform private.fail('INVALID_TIME_RANGE', 'Waktu titik tangkap harus di dalam rentang trip',
      jsonb_build_object('points', v_bad));
  end if;
  if v_has_track then
    select coalesce(jsonb_agg(e.i - 1), '[]') into v_bad
    from jsonb_array_elements(v_track) with ordinality e (v, i)
    where (e.v ->> 'recorded_at')::timestamptz
      not between v_dep_at - interval '10 minutes' and v_ret_at + interval '10 minutes';
    if v_bad <> '[]' then
      perform private.fail('INVALID_TIME_RANGE', 'Waktu track harus di dalam rentang trip',
        jsonb_build_object('track', v_bad));
    end if;
  end if;

  -- Pilot area
  v_dep := coalesce(private.pt(p -> 'departure'), v_boat.home_port);
  v_ret := coalesce(private.pt(p -> 'return_point'), v_dep);
  select coalesce(jsonb_agg(e.i - 1), '[]') into v_bad
  from jsonb_array_elements(v_fps) with ordinality e (v, i)
  where not private.in_pilot(private.pt(e.v), 1000);
  if v_bad <> '[]' or not private.in_pilot(v_dep, 5000) or not private.in_pilot(v_ret, 5000) then
    perform private.fail('OUT_OF_PILOT', 'Ada titik di luar area pilot', jsonb_build_object(
      'points', v_bad,
      'departure', not private.in_pilot(v_dep, 5000),
      'return_point', not private.in_pilot(v_ret, 5000)
    ));
  end if;

  -- Recommendations referenced by the trip must belong to the user
  if exists (
    select 1 from (
      select (p ->> 'selected_recommendation_id')::uuid as id
      union all
      select (e ->> 'recommendation_id')::uuid from jsonb_array_elements(v_fps) e
    ) x
    where x.id is not null and not exists (select 1 from recommendations r where r.id = x.id and r.user_id = v_uid)
  ) then
    perform private.fail('VALIDATION_ERROR', 'Rekomendasi tidak ditemukan',
      jsonb_build_object('fields', jsonb_build_object('recommendation_id', 'tidak ditemukan')));
  end if;

  select avg(fuel_liters) into v_baseline from trips where user_id = v_uid;

  begin
    insert into trips (
      user_id, client_trip_id, source, boat_id, engine_hp_snapshot, boat_length_m_snapshot,
      departure, return_point, departed_at, returned_at, fuel_liters, catch_kg, duration_h,
      fuel_efficiency_pct, selected_recommendation_id, notes
    ) values (
      v_uid, (p ->> 'client_trip_id')::uuid, p ->> 'source', v_boat.id, v_boat.engine_hp, v_boat.boat_length_m,
      v_dep, v_ret, v_dep_at, v_ret_at, (p ->> 'fuel_liters')::numeric, (p ->> 'catch_kg')::numeric,
      extract(epoch from v_ret_at - v_dep_at) / 3600,
      -- AGENTS.md 12.B.2: against the average of earlier trips; the first trip is 0
      case when v_baseline > 0 then (v_baseline - (p ->> 'fuel_liters')::numeric) / v_baseline * 100 else 0 end,
      (p ->> 'selected_recommendation_id')::uuid, nullif(p ->> 'notes', '')
    )
    returning * into v_trip;
  exception when unique_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint in ('trips_client_trip_uq', 'trips_one_onboarding') then
      -- A concurrent request with the same client_trip_id committed first.
      select id into v_existing
      from trips
      where user_id = v_uid and client_trip_id = (p ->> 'client_trip_id')::uuid;
      if v_existing is not null then
        return private.post_trip_result(v_existing, true);
      end if;
      if v_constraint = 'trips_one_onboarding' then
        perform private.fail('ALREADY_ONBOARDED', 'Trip pertama sudah pernah dikirim');
      end if;
    end if;
    -- Preserve every unexpected unique violation with its original SQLSTATE and constraint.
    raise;
  end;

  insert into fishing_points (
    trip_id, seq, location, grid_id, started_at, ended_at, zone_id_at_time, zone_name_at_time, zone_status_at_time,
    fishing_hours, reported_catch_kg, flag_source, recommendation_id
  )
  select v_trip.id, e.i, x.g, private.nearest_grid(x.g), x.st, x.en, z.id, z.name, coalesce(z.status, 'normal'),
    extract(epoch from x.en - x.st) / 3600,
    (e.v ->> 'reported_catch_kg')::numeric,
    coalesce(e.v ->> 'flag_source', 'manual'),
    (e.v ->> 'recommendation_id')::uuid
  from jsonb_array_elements(v_fps) with ordinality e (v, i)
  cross join lateral (
    select private.pt(e.v) as g, (e.v ->> 'started_at')::timestamptz as st, (e.v ->> 'ended_at')::timestamptz as en
  ) x
  left join lateral private.zone_at(x.g, coalesce(x.st, v_dep_at)) z on true;

  if v_has_track then
    insert into trip_points (trip_id, seq, location, recorded_at, speed_ms, accuracy_m)
    select v_trip.id, (e ->> 'seq')::int, private.pt(e), (e ->> 'recorded_at')::timestamptz,
      (e ->> 'speed_ms')::numeric, (e ->> 'accuracy_m')::numeric
    from jsonb_array_elements(v_track) e;
  end if;

  -- Catch allocation: reported per point if every point has it, else by duration, else evenly
  update fishing_points f set allocated_catch_kg = round(case
      when a.all_reported then f.reported_catch_kg
      when a.all_timed then v_trip.catch_kg * f.fishing_hours / a.total_hours
      else v_trip.catch_kg / a.n
    end, 3)
  from (
    select bool_and(reported_catch_kg is not null) as all_reported,
      bool_and(coalesce(fishing_hours > 0, false)) as all_timed, sum(fishing_hours) as total_hours, count(*) as n
    from fishing_points where trip_id = v_trip.id
  ) a
  where f.trip_id = v_trip.id;

  -- Distances: along the track when present, else straight lines port -> points -> return
  select location into v_first from fishing_points where trip_id = v_trip.id order by seq limit 1;
  select st_makeline(location::geometry order by seq) into v_line from trip_points where trip_id = v_trip.id;
  if v_line is not null and st_npoints(v_line) >= 2 then
    v_total_km := st_length(v_line::geography) / 1000;
    select seq into v_cut from trip_points where trip_id = v_trip.id order by location <-> v_first limit 1;
    select case when count(*) >= 2
        then st_length(st_makeline(location::geometry order by seq)::geography) / 1000 else 0 end
      into v_port_km
    from trip_points where trip_id = v_trip.id and seq <= v_cut;
  else
    select st_length(st_makeline(array[v_dep::geometry]
        || array_agg(location::geometry order by seq)
        || array[v_ret::geometry])::geography) / 1000
      into v_total_km
    from fishing_points where trip_id = v_trip.id;
    v_port_km := st_distance(v_dep, v_first) / 1000;
  end if;

  update trips set
    total_distance_km = v_total_km,
    distance_from_port_km = v_port_km,
    fishing_hours = (select sum(fishing_hours) from fishing_points where trip_id = v_trip.id),
    fuel_per_km = fuel_liters / nullif(v_total_km, 0),
    catch_per_liter = catch_kg / fuel_liters,
    zone_violation = exists (
      select 1 from fishing_points where trip_id = v_trip.id and zone_status_at_time = 'closed'
    )
  where id = v_trip.id;

  if p ->> 'source' = 'onboarding' then
    update profiles set onboarded = true where id = v_uid;
  end if;
  return private.post_trip_result(v_trip.id, false);
end;
$$;

-- Explicitly keep the private schema and its existing objects inaccessible to API roles.
revoke all on schema private from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

-- Trigger functions are called by their triggers, not directly by API clients.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.handle_user_phone_change() from public, anon, authenticated;

-- Strip broad/default API table privileges, then grant SELECT where the RLS policies
-- already define the intended own-row or read-only visibility.
revoke all privileges on table
  public.profiles,
  public.boats,
  public.recommendation_sets,
  public.recommendations,
  public.trips,
  public.trip_points,
  public.fishing_points,
  public.app_config,
  public.cluster_levels,
  public.grid_cells,
  public.cluster_predictions,
  public.zones
from anon, authenticated;

grant select on table
  public.profiles,
  public.boats,
  public.recommendation_sets,
  public.recommendations,
  public.trips,
  public.trip_points,
  public.fishing_points,
  public.cluster_levels,
  public.grid_cells,
  public.cluster_predictions,
  public.zones
to authenticated;

-- Preserve the existing konservatif zone insert/update/delete policies.
-- Table privileges permit the operations; those RLS policies still authorize rows.
grant insert, update, delete on table public.zones to authenticated;

-- These helpers use qualified application objects and pg_catalog built-ins.
alter function private.boat_errors(jsonb, boolean) set search_path = '';
alter function private.fail(text, text, jsonb) set search_path = '';
alter function private.bad_num(jsonb, text, numeric, numeric, boolean, boolean) set search_path = '';
alter function private.bad_point(jsonb, boolean) set search_path = '';
alter function private.bad_uuid(jsonb, boolean) set search_path = '';
alter function private.bad_time(jsonb, boolean) set search_path = '';
alter function private.check_for_date(date) set search_path = '';
revoke execute on function public.is_konservatif() from public, anon;
grant execute on function public.is_konservatif() to authenticated;

notify pgrst, 'reload schema';
