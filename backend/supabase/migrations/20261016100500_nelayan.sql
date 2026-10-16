-- Nelayan API (contracts/nelayan-api.openapi.yaml, docs/AGENTS.md 12.B adapted to this schema).
-- Tables are read-only to clients (select-own RLS). Every write goes through a security definer api_* RPC
-- that the Go service calls with the user's JWT, so each endpoint is one transaction.

create schema if not exists private;
revoke all on schema private from public;

alter table public.profiles add column onboarded boolean not null default false;

-- Ready for many boats; the API allows one per user for now (AGENTS.md 12.B.0)
create table public.boats (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text check (length(name) <= 60),
  engine_hp numeric not null check (engine_hp between 1 and 500),
  boat_length_m numeric not null check (boat_length_m between 2 and 30),
  fuel_type text not null default 'solar' check (fuel_type in ('solar', 'bensin')),
  home_port extensions.geography(Point, 4326) not null,
  is_default boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index boats_user_idx on public.boats (user_id);
create unique index boats_one_default on public.boats (user_id) where is_default and deleted_at is null;

create table public.recommendation_sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  boat_id uuid not null references public.boats (id) on delete cascade,
  source_trip_id uuid,
  for_date date not null,
  period text,                         -- cluster_predictions period the candidates came from
  window_start timestamptz not null,   -- for_date + departure_time (WIB); zone status is checked at this time
  max_range_km numeric not null,
  fuel_per_km numeric not null,
  avg_catch_kg numeric,
  baseline_fuel_liters numeric,
  departure_time time not null,
  return_time time not null,
  model_version text not null,
  is_fallback boolean not null,
  unavailable_types jsonb not null default '[]',
  generated_at timestamptz not null default now(),
  valid_until timestamptz not null
);
create index recommendation_sets_user_idx on public.recommendation_sets (user_id, for_date, generated_at desc);

create table public.recommendations (
  id uuid primary key default gen_random_uuid(),
  set_id uuid not null references public.recommendation_sets (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  type text not null check (type in ('fuel_saving', 'catch_max', 'balanced', 'habitual')),
  grid_id text not null references public.grid_cells (grid_id),
  point extensions.geography(Point, 4326) not null,
  zone jsonb not null,                 -- {id, name, status} at generation time
  zone_rules jsonb,
  distance_from_port_km numeric not null,
  predicted_fuel_liters numeric,
  fuel_efficiency_pct numeric,
  predicted_catch_kg numeric,
  predicted_catch_min numeric,
  predicted_catch_max numeric,
  confidence numeric not null,
  reason text not null,
  weather_summary jsonb
);
create unique index recommendations_set_type_uq on public.recommendations (set_id, type);
create index recommendations_user_idx on public.recommendations (user_id);

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  client_trip_id uuid not null,
  source text not null check (source in ('onboarding', 'manual', 'sailing')),
  boat_id uuid not null references public.boats (id),
  engine_hp_snapshot numeric not null,
  boat_length_m_snapshot numeric not null,
  departure extensions.geography(Point, 4326) not null,
  return_point extensions.geography(Point, 4326) not null,
  departed_at timestamptz not null,
  returned_at timestamptz not null,
  fuel_liters numeric not null check (fuel_liters > 0 and fuel_liters <= 500),
  catch_kg numeric not null check (catch_kg between 0 and 5000),
  distance_from_port_km numeric,
  total_distance_km numeric,
  duration_h numeric not null,
  fishing_hours numeric,
  fuel_per_km numeric,
  catch_per_liter numeric,
  fuel_efficiency_pct numeric,
  zone_violation boolean not null default false,
  selected_recommendation_id uuid references public.recommendations (id) on delete set null,
  notes text check (length(notes) <= 500),
  created_at timestamptz not null default now(),
  check (returned_at > departed_at),
  constraint trips_client_trip_uq unique (user_id, client_trip_id)
);
create index trips_user_departed_idx on public.trips (user_id, departed_at desc);
create unique index trips_one_onboarding on public.trips (user_id) where source = 'onboarding';

alter table public.recommendation_sets
  add constraint recommendation_sets_trip_fk foreign key (source_trip_id) references public.trips (id) on delete set null;

create table public.trip_points (
  trip_id uuid not null references public.trips (id) on delete cascade,
  seq int not null,
  location extensions.geography(Point, 4326) not null,
  recorded_at timestamptz not null,
  speed_ms numeric,
  accuracy_m numeric,
  primary key (trip_id, seq)
);

create table public.fishing_points (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  seq int not null,
  location extensions.geography(Point, 4326) not null,
  grid_id text references public.grid_cells (grid_id),
  started_at timestamptz,
  ended_at timestamptz,
  -- zone snapshot: history must not change when a konservatif edits or deletes the zone
  zone_id_at_time uuid references public.zones (id) on delete set null,
  zone_name_at_time text,
  zone_status_at_time text not null default 'normal',
  fishing_hours numeric,
  reported_catch_kg numeric,
  allocated_catch_kg numeric,
  flag_source text not null default 'manual'
    check (flag_source in ('manual', 'user_confirmed', 'auto_timeout', 'rec_radius')),
  recommendation_id uuid references public.recommendations (id) on delete set null,
  unique (trip_id, seq)
);
create index fishing_points_grid_idx on public.fishing_points (grid_id);

create table public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

insert into public.app_config (key, value) values
  ('rec.valid_hours', '6'),
  ('rec.max_range_km', '40'),
  ('rec.min_level', '3'),
  ('rec.default_fuel_per_km', '1.0'),
  ('rec.departure_time', '"04:30"'),
  ('rec.return_time', '"11:00"'),
  ('mobile', '{
    "version": 1,
    "sailing": {
      "poll_interval_s": 120,
      "poll_interval_near_target_s": 30,
      "near_target_distance_m": 2000,
      "stop_distance_m": 50,
      "stop_speed_ms": 0.5,
      "stop_confirm_timeout_s": 300,
      "rec_radius_m": 500,
      "rec_radius_exit_buffer_m": 100
    },
    "sync": { "heatmap_check_interval_sailing_s": 900 },
    "limits": { "max_track_points": 5000, "max_fishing_points": 50 }
  }');

alter table public.boats enable row level security;
alter table public.recommendation_sets enable row level security;
alter table public.recommendations enable row level security;
alter table public.trips enable row level security;
alter table public.trip_points enable row level security;
alter table public.fishing_points enable row level security;
alter table public.app_config enable row level security;

create policy "read own boats" on public.boats
  for select to authenticated using (user_id = (select auth.uid()));
create policy "read own recommendation sets" on public.recommendation_sets
  for select to authenticated using (user_id = (select auth.uid()));
create policy "read own recommendations" on public.recommendations
  for select to authenticated using (user_id = (select auth.uid()));
create policy "read own trips" on public.trips
  for select to authenticated using (user_id = (select auth.uid()));
create policy "read own trip points" on public.trip_points
  for select to authenticated
  using (exists (select 1 from public.trips t where t.id = trip_id and t.user_id = (select auth.uid())));
create policy "read own fishing points" on public.fishing_points
  for select to authenticated
  using (exists (select 1 from public.trips t where t.id = trip_id and t.user_id = (select auth.uid())));

-- ---------------------------------------------------------------------------------------------
-- Helpers (schema private: not reachable through PostgREST)
-- ---------------------------------------------------------------------------------------------

-- Raises an API error. PostgREST returns {code: "P0001", message: <code>, details: <json>, hint: <message>}.
create function private.fail(p_code text, p_message text, p_details jsonb default null)
returns void
language plpgsql
as $$
begin
  raise exception using message = p_code, hint = p_message, detail = coalesce(p_details::text, '');
end;
$$;

create function private.require_nelayan()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
begin
  if v_uid is null then
    perform private.fail('UNAUTHORIZED', 'Silakan login ulang');
  end if;
  select role into v_role from public.profiles where id = v_uid;
  if v_role is distinct from 'nelayan' then
    perform private.fail('FORBIDDEN', 'Fitur ini hanya untuk nelayan');
  end if;
  return v_uid;
end;
$$;

create function private.config(p_key text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select value from public.app_config where key = p_key;
$$;

-- Field validators return an Indonesian message, or null when the value is acceptable.
create function private.bad_num(p jsonb, k text, lo numeric, hi numeric, required boolean, lo_exclusive boolean default false)
returns text
language sql
immutable
as $$
  select case
    when p -> k is null or jsonb_typeof(p -> k) = 'null' then case when required then 'wajib diisi' end
    when jsonb_typeof(p -> k) <> 'number' then 'harus angka'
    when (p ->> k)::numeric > hi or (p ->> k)::numeric < lo or (lo_exclusive and (p ->> k)::numeric = lo)
      then format('harus %s%s sampai %s', case when lo_exclusive then 'lebih dari ' else '' end, lo, hi)
  end;
$$;

create function private.bad_point(v jsonb, required boolean)
returns text
language sql
immutable
as $$
  select case
    when v is null or jsonb_typeof(v) = 'null' then case when required then 'wajib diisi' end
    when jsonb_typeof(v) <> 'object'
      or coalesce(jsonb_typeof(v -> 'lat'), '') <> 'number'
      or coalesce(jsonb_typeof(v -> 'lng'), '') <> 'number' then 'harus { lat, lng }'
    when abs((v ->> 'lat')::numeric) > 90 or abs((v ->> 'lng')::numeric) > 180 then 'koordinat tidak valid'
  end;
$$;

create function private.bad_uuid(v jsonb, required boolean)
returns text
language sql
immutable
as $$
  select case
    when v is null or jsonb_typeof(v) = 'null' then case when required then 'wajib diisi' end
    when jsonb_typeof(v) <> 'string'
      or (v #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then 'harus UUID'
  end;
$$;

-- Requires an explicit offset so the instant never depends on the session time zone.
create function private.bad_time(v jsonb, required boolean)
returns text
language plpgsql
stable
as $$
begin
  if v is null or jsonb_typeof(v) = 'null' then
    return case when required then 'wajib diisi' end;
  end if;
  if jsonb_typeof(v) <> 'string'
     or (v #>> '{}') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$' then
    return 'harus waktu ISO-8601 dengan zona waktu';
  end if;
  perform (v #>> '{}')::timestamptz;
  return null;
exception when others then
  return 'harus waktu ISO-8601 dengan zona waktu';
end;
$$;

-- Call only after bad_point accepted the value.
create function private.pt(v jsonb)
returns extensions.geography
language sql
immutable
set search_path = ''
as $$
  select case when jsonb_typeof(v) = 'object' then
    extensions.st_setsrid(extensions.st_makepoint((v ->> 'lng')::float8, (v ->> 'lat')::float8), 4326)::extensions.geography
  end;
$$;

create function private.latlng(g extensions.geography)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when g is not null then jsonb_build_object(
    'lat', round(extensions.st_y(g::extensions.geometry)::numeric, 6),
    'lng', round(extensions.st_x(g::extensions.geometry)::numeric, 6)
  ) end;
$$;

-- shortcut: the pilot is "near a grid_cells cell" (1 km at sea, 5 km for ports); replace with the real
-- pilot polygon once AGENTS.md 5.1 grid origin is decided.
create function private.in_pilot(g extensions.geography, tolerance_m float8)
returns boolean
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  select exists (select 1 from grid_cells c where st_dwithin(c.geom, g, tolerance_m));
$$;

create function private.nearest_grid(g extensions.geography)
returns text
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  select c.grid_id from grid_cells c where st_dwithin(c.geom, g, 500) order by c.geom <-> g limit 1;
$$;

-- Most restrictive zone active at that moment (WIB date), same rule as get_fishing_spots.
create function private.zone_at(g extensions.geography, at timestamptz)
returns table (id uuid, name text, status text, max_catch_kg numeric)
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  select z.id, z.name, z.status, z.max_catch_kg
  from zones z
  where st_intersects(z.geom, g)
    and z.valid_from <= (at at time zone 'Asia/Jakarta')::date
    and (z.valid_to is null or z.valid_to >= (at at time zone 'Asia/Jakarta')::date)
  order by case z.status when 'closed' then 0 when 'limited' then 1 else 2 end
  limit 1;
$$;

create function private.boat_json(b public.boats)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', b.id, 'name', b.name, 'engine_hp', b.engine_hp, 'boat_length_m', b.boat_length_m,
    'fuel_type', b.fuel_type, 'home_port', private.latlng(b.home_port), 'is_default', b.is_default,
    'created_at', b.created_at, 'updated_at', b.updated_at
  );
$$;

create function private.boat_errors(p jsonb, creating boolean)
returns jsonb
language sql
immutable
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'name', case
      when jsonb_typeof(p -> 'name') not in ('string', 'null') then 'harus teks'
      when length(p ->> 'name') > 60 then 'maks 60 karakter' end,
    'engine_hp', private.bad_num(p, 'engine_hp', 1, 500, creating),
    'boat_length_m', private.bad_num(p, 'boat_length_m', 2, 30, creating),
    'fuel_type', case when p ->> 'fuel_type' not in ('solar', 'bensin') then 'solar atau bensin' end,
    'home_port', private.bad_point(p -> 'home_port', creating)
  ));
$$;

create function private.rec_json(r public.recommendations, s public.recommendation_sets)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id, 'type', r.type, 'grid_id', r.grid_id, 'point', private.latlng(r.point),
    'zone', r.zone, 'zone_rules', r.zone_rules,
    'area_condition', 'healthy',
    'predicted_fuel_liters', r.predicted_fuel_liters, 'fuel_efficiency_pct', r.fuel_efficiency_pct,
    'predicted_catch_kg', r.predicted_catch_kg,
    'predicted_catch_range_kg', case when r.predicted_catch_kg is not null
      then jsonb_build_array(r.predicted_catch_min, r.predicted_catch_max) end,
    'departure_time', to_char(s.departure_time, 'HH24:MI'), 'return_time', to_char(s.return_time, 'HH24:MI'),
    'for_date', s.for_date, 'distance_from_port_km', r.distance_from_port_km,
    'weather_summary', r.weather_summary, 'confidence', r.confidence, 'reason', r.reason
  );
$$;

create function private.set_json(p_set uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'for_date', s.for_date, 'generated_at', s.generated_at, 'valid_until', s.valid_until,
    'source_trip_id', s.source_trip_id, 'boat_id', s.boat_id, 'baseline_fuel_liters', s.baseline_fuel_liters,
    'heatmap_version', null, 'model_version', s.model_version, 'is_fallback', s.is_fallback,
    'items', coalesce((
      select jsonb_agg(private.rec_json(r, s)
        order by array_position(array['fuel_saving', 'catch_max', 'balanced', 'habitual'], r.type))
      from public.recommendations r where r.set_id = s.id
    ), '[]'),
    'unavailable_types', s.unavailable_types
  )
  from public.recommendation_sets s
  where s.id = p_set;
$$;

create function private.trip_summary(t public.trips)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id, 'source', t.source, 'departed_at', t.departed_at, 'returned_at', t.returned_at,
    'duration_h', round(t.duration_h, 2), 'fuel_liters', t.fuel_liters, 'catch_kg', t.catch_kg,
    'distance_from_port_km', round(t.distance_from_port_km, 2), 'total_distance_km', round(t.total_distance_km, 2),
    'fuel_efficiency_pct', round(t.fuel_efficiency_pct, 1), 'catch_per_liter', round(t.catch_per_liter, 2),
    'fishing_point_count', (select count(*) from public.fishing_points f where f.trip_id = t.id),
    'main_grid_id', (
      select f.grid_id from public.fishing_points f
      where f.trip_id = t.id and f.grid_id is not null
      order by f.allocated_catch_kg desc nulls last, f.seq limit 1
    ),
    'followed_recommendation_type', (select r.type from public.recommendations r where r.id = t.selected_recommendation_id),
    'zone_violation', t.zone_violation,
    'boat', (select jsonb_build_object('id', b.id, 'name', b.name) from public.boats b where b.id = t.boat_id)
  );
$$;

create function private.trip_detail(p_trip uuid, p_track text)
returns jsonb
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  select private.trip_summary(t) || jsonb_build_object(
    'client_trip_id', t.client_trip_id,
    'departure', private.latlng(t.departure),
    'return_point', private.latlng(t.return_point),
    'fishing_hours', round(t.fishing_hours, 2),
    'fuel_per_km', round(t.fuel_per_km, 3),
    'boat_snapshot', jsonb_build_object('engine_hp', t.engine_hp_snapshot, 'boat_length_m', t.boat_length_m_snapshot),
    'fishing_points', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'lat', (private.latlng(f.location) -> 'lat'), 'lng', (private.latlng(f.location) -> 'lng'),
        'grid_id', f.grid_id,
        'zone_at_time', jsonb_build_object('id', f.zone_id_at_time, 'name', f.zone_name_at_time, 'status', f.zone_status_at_time),
        'started_at', f.started_at, 'ended_at', f.ended_at, 'fishing_hours', round(f.fishing_hours, 2),
        'allocated_catch_kg', f.allocated_catch_kg, 'reported_catch_kg', f.reported_catch_kg,
        'flag_source', f.flag_source, 'recommendation_id', f.recommendation_id
      ) order by f.seq)
      from fishing_points f where f.trip_id = t.id
    ), '[]'),
    'track', case when p_track <> 'none' then (
      select st_asgeojson(case when p_track = 'full' then l
        -- ~20 m at these latitudes (AGENTS.md 12.B.4)
        else st_simplifypreservetopology(l, 0.0002) end, 6)::jsonb
      from (
        select st_makeline(tp.location::geometry order by tp.seq) l
        from trip_points tp where tp.trip_id = t.id
      ) x where l is not null
    ) end,
    'selected_recommendation', (
      select jsonb_build_object('id', r.id, 'type', r.type, 'distance_to_point_m', (
        select round(min(st_distance(r.point, f.location))::numeric) from fishing_points f where f.trip_id = t.id
      ))
      from recommendations r where r.id = t.selected_recommendation_id
    ),
    'notes', t.notes,
    'created_at', t.created_at
  )
  from trips t
  where t.id = p_trip;
$$;

create function private.zone_json(g extensions.geography, at timestamptz)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select jsonb_build_object('id', z.id, 'name', z.name, 'status', z.status, 'max_catch_kg', z.max_catch_kg)
     from private.zone_at(g, at) z),
    jsonb_build_object('id', null, 'name', null, 'status', 'normal', 'max_catch_kg', null)
  );
$$;

create function private.check_for_date(p date)
returns date
language plpgsql
stable
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if coalesce(p, v_today) not between v_today and v_today + 2 then
    perform private.fail('VALIDATION_ERROR', 'Tanggal maksimal 2 hari ke depan',
      jsonb_build_object('fields', jsonb_build_object('for_date', 'hari ini sampai +2 hari (WIB)')));
  end if;
  return coalesce(p, v_today);
end;
$$;

-- Default boat of an onboarded user, else ONBOARDING_REQUIRED.
create function private.onboarded_boat(p_uid uuid)
returns public.boats
language plpgsql
stable
set search_path = ''
as $$
declare
  v_boat public.boats;
begin
  select b.* into v_boat from public.boats b
  join public.profiles pr on pr.id = b.user_id and pr.onboarded
  where b.user_id = p_uid and b.is_default and b.deleted_at is null;
  if v_boat.id is null then
    perform private.fail('ONBOARDING_REQUIRED', 'Selesaikan onboarding terlebih dahulu');
  end if;
  return v_boat;
end;
$$;

create function private.post_trip_result(p_trip uuid, p_replay boolean)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'trip', private.trip_detail(p_trip, 'simplified'),
    'recommendations', (
      select private.set_json(s.id) from public.recommendation_sets s
      where s.source_trip_id = p_trip order by s.generated_at desc limit 1
    ),
    'user', jsonb_build_object('onboarded', (
      select p.onboarded from public.profiles p join public.trips t on t.user_id = p.id where t.id = p_trip
    )),
    'replay', p_replay
  );
$$;

-- ---------------------------------------------------------------------------------------------
-- API (called by the Go service as POST /rest/v1/rpc/<name> with the user's JWT)
-- ---------------------------------------------------------------------------------------------

create function public.api_me()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
  v_profile profiles;
  v_boat boats;
  v_stats jsonb;
begin
  select * into v_profile from profiles where id = v_uid;
  select * into v_boat from boats where user_id = v_uid and is_default and deleted_at is null;
  select jsonb_build_object(
    'trip_count', count(*),
    'baseline_fuel_liters', round(avg(fuel_liters), 2),
    'baseline_catch_kg', round(avg(catch_kg), 2),
    'last_trip_at', max(returned_at)
  ) into v_stats
  from trips where user_id = v_uid;

  return jsonb_build_object(
    'id', v_uid, 'name', v_profile.full_name, 'phone', v_profile.phone, 'role', v_profile.role,
    'onboarded', v_profile.onboarded,
    'next_step', case when v_boat.id is null then 'boat' when not v_profile.onboarded then 'first_trip' else 'done' end,
    'boat', case when v_boat.id is not null then private.boat_json(v_boat) end,
    'stats', v_stats
  );
end;
$$;

create function public.api_create_boat(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
  v_errors jsonb := private.boat_errors(p, true);
  v_boat boats;
begin
  if v_errors <> '{}' then
    perform private.fail('VALIDATION_ERROR', 'Data kapal tidak valid', jsonb_build_object('fields', v_errors));
  end if;
  if exists (select 1 from boats where user_id = v_uid and deleted_at is null) then
    perform private.fail('BOAT_LIMIT_REACHED', 'Akun ini sudah punya kapal');
  end if;
  if not private.in_pilot(private.pt(p -> 'home_port'), 5000) then
    perform private.fail('OUT_OF_PILOT', 'Dermaga di luar area pilot',
      jsonb_build_object('fields', jsonb_build_object('home_port', 'di luar area pilot')));
  end if;

  insert into boats (user_id, name, engine_hp, boat_length_m, fuel_type, home_port, is_default)
  values (
    v_uid, nullif(trim(p ->> 'name'), ''), (p ->> 'engine_hp')::numeric, (p ->> 'boat_length_m')::numeric,
    coalesce(p ->> 'fuel_type', 'solar'), private.pt(p -> 'home_port'), true
  )
  returning * into v_boat;
  return private.boat_json(v_boat);
exception when unique_violation then
  -- concurrent create lost the race on boats_one_default
  perform private.fail('BOAT_LIMIT_REACHED', 'Akun ini sudah punya kapal');
end;
$$;

create function public.api_update_boat(p_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
  v_errors jsonb := private.boat_errors(p, false);
  v_boat boats;
begin
  if v_errors <> '{}' then
    perform private.fail('VALIDATION_ERROR', 'Data kapal tidak valid', jsonb_build_object('fields', v_errors));
  end if;
  perform 1 from boats where id = p_id and user_id = v_uid and deleted_at is null for update;
  if not found then
    perform private.fail('BOAT_NOT_FOUND', 'Kapal tidak ditemukan');
  end if;
  if private.pt(p -> 'home_port') is not null and not private.in_pilot(private.pt(p -> 'home_port'), 5000) then
    perform private.fail('OUT_OF_PILOT', 'Dermaga di luar area pilot',
      jsonb_build_object('fields', jsonb_build_object('home_port', 'di luar area pilot')));
  end if;

  -- absent or null keeps the old value; name accepts null to clear it
  update boats set
    name = case when p ? 'name' then nullif(trim(p ->> 'name'), '') else name end,
    engine_hp = coalesce((p ->> 'engine_hp')::numeric, engine_hp),
    boat_length_m = coalesce((p ->> 'boat_length_m')::numeric, boat_length_m),
    fuel_type = coalesce(p ->> 'fuel_type', fuel_type),
    home_port = coalesce(private.pt(p -> 'home_port'), home_port),
    updated_at = now()
  where id = p_id
  returning * into v_boat;

  -- recommendations used the old specs; expire them so the next request regenerates
  update recommendation_sets set valid_until = now() where user_id = v_uid and valid_until > now();
  return private.boat_json(v_boat);
end;
$$;

-- Recommendations are not generated here: the client calls the Go GET /api/v1/recommendations next.
create function public.api_post_trip(p jsonb)
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
    if v_constraint = 'trips_one_onboarding' then
      perform private.fail('ALREADY_ONBOARDED', 'Trip pertama sudah pernah dikirim');
    end if;
    -- a concurrent request with the same client_trip_id committed first
    select id into v_existing from trips where user_id = v_uid and client_trip_id = (p ->> 'client_trip_id')::uuid;
    return private.post_trip_result(v_existing, true);
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

create function public.api_list_trips(
  p_page int default 1,
  p_limit int default 20,
  p_from date default null,
  p_to date default null,
  p_source text default null,
  p_sort text default '-departed_at'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
  -- clamp: the RPC is also reachable directly through PostgREST
  v_page int := greatest(coalesce(p_page, 1), 1);
  v_limit int := least(greatest(coalesce(p_limit, 20), 1), 100);
begin
  return (
    with f as (
      select * from trips t
      where t.user_id = v_uid
        and (p_from is null or (t.departed_at at time zone 'Asia/Jakarta')::date >= p_from)
        and (p_to is null or (t.departed_at at time zone 'Asia/Jakarta')::date <= p_to)
        and (p_source is null or t.source = p_source)
    ),
    ranked as (
      select f.*, row_number() over (order by
        case when p_sort = 'departed_at' then f.departed_at end asc,
        case when p_sort = '-catch_kg' then f.catch_kg end desc nulls last,
        case when p_sort = '-fuel_efficiency_pct' then f.fuel_efficiency_pct end desc nulls last,
        f.departed_at desc, f.id
      ) as rn
      from f
    )
    select jsonb_build_object(
      'data', coalesce((
        select jsonb_agg(private.trip_summary(t) order by r.rn)
        from ranked r join trips t on t.id = r.id
        where r.rn > (v_page - 1) * v_limit and r.rn <= v_page * v_limit
      ), '[]'),
      'meta', jsonb_build_object('page', v_page, 'limit', v_limit, 'total', (select count(*) from f)),
      'summary', (
        select jsonb_build_object(
          'trip_count', count(*),
          'total_catch_kg', coalesce(sum(catch_kg), 0),
          'total_fuel_liters', coalesce(sum(fuel_liters), 0),
          'avg_catch_per_liter', round(sum(catch_kg) / nullif(sum(fuel_liters), 0), 2)
        ) from f
      )
    )
  );
end;
$$;

create function public.api_trip_detail(p_id uuid, p_track text default 'simplified')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
begin
  if not exists (select 1 from trips where id = p_id and user_id = v_uid) then
    perform private.fail('TRIP_NOT_FOUND', 'Trip tidak ditemukan');
  end if;
  return private.trip_detail(p_id, coalesce(p_track, 'simplified'));
end;
$$;

-- Input for the Go recommendation service (ranking and fuel prediction live in Go).
-- Returns {cached} when a valid set exists, else everything Go needs to build one.
create function public.api_rec_context(p_for_date date default null, p_refresh boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
  v_date date := private.check_for_date(p_for_date);
  v_boat boats := private.onboarded_boat(v_uid);
  v_window timestamptz := (v_date + (private.config('rec.departure_time') #>> '{}')::time) at time zone 'Asia/Jakarta';
  v_cached uuid;
begin
  if not coalesce(p_refresh, false) then
    select id into v_cached from recommendation_sets
    where user_id = v_uid and for_date = v_date and valid_until > now()
    order by generated_at desc
    limit 1;
    if v_cached is not null then
      return jsonb_build_object('cached', private.set_json(v_cached));
    end if;
  end if;

  return jsonb_build_object(
    'cached', null,
    'for_date', v_date,
    'window_start', v_window,
    'boat', jsonb_build_object(
      'id', v_boat.id, 'home_port', private.latlng(v_boat.home_port),
      'engine_hp', v_boat.engine_hp, 'boat_length_m', v_boat.boat_length_m
    ),
    'stats', (
      select jsonb_build_object(
        'trip_count', count(*),
        'fuel_per_km', avg(fuel_per_km) filter (where fuel_per_km > 0),
        'avg_catch_kg', avg(catch_kg),
        'baseline_fuel_liters', avg(fuel_liters)
      ) from trips where user_id = v_uid
    ),
    'config', jsonb_build_object(
      'max_range_km', private.config('rec.max_range_km'),
      'default_fuel_per_km', private.config('rec.default_fuel_per_km'),
      'departure_time', private.config('rec.departure_time'),
      'return_time', private.config('rec.return_time')
    ),
    -- predicted cells in range of the home port, outside zones closed at departure
    'candidates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'grid_id', g.grid_id,
        'lat', round(st_y(g.geom::geometry)::numeric, 6), 'lng', round(st_x(g.geom::geometry)::numeric, 6),
        'dist_m', round(st_distance(g.geom, v_boat.home_port)::numeric),
        'potential_score', p.potential_score, 'level', p.level, 'zone', zz.z
      ))
      from cluster_predictions p
      join grid_cells g on g.grid_id = p.grid_id
      cross join lateral (select private.zone_json(g.geom, v_window) as z) zz
      where p.period = (select max(period) from cluster_predictions)
        and p.level >= (private.config('rec.min_level') #>> '{}')::int
        and st_dwithin(g.geom, v_boat.home_port, (private.config('rec.max_range_km') #>> '{}')::float8 * 1000)
        and zz.z ->> 'status' <> 'closed'
    ), '[]'),
    'habitual', (
      select jsonb_build_object(
        'grid_id', g.grid_id,
        'lat', round(st_y(g.geom::geometry)::numeric, 6), 'lng', round(st_x(g.geom::geometry)::numeric, 6),
        'dist_m', round(st_distance(g.geom, v_boat.home_port)::numeric),
        'visits', h.visits, 'zone', private.zone_json(g.geom, v_window)
      )
      from (
        select f.grid_id, count(*) as visits, max(t.departed_at) as last_at
        from fishing_points f join trips t on t.id = f.trip_id
        where t.user_id = v_uid and f.grid_id is not null
        group by f.grid_id
        order by count(*) desc, max(t.departed_at) desc
        limit 1
      ) h
      join grid_cells g on g.grid_id = h.grid_id
    )
  );
end;
$$;

-- Stores a set ranked by Go. Callable directly through PostgREST, so ownership, grid existence and
-- closed zones are re-checked here; point, distance and zone always come from the database.
create function public.api_save_recommendations(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
  v_boat boats := private.onboarded_boat(v_uid);
  v_date date;
  v_window timestamptz;
  v_set uuid;
  v_item jsonb;
  v_geom geography;
  v_zone jsonb;
begin
  if jsonb_typeof(p) is distinct from 'object' or coalesce(jsonb_typeof(p -> 'items'), '') <> 'array'
     or coalesce(p ->> 'for_date', '') !~ '^\d{4}-\d{2}-\d{2}$' then
    perform private.fail('VALIDATION_ERROR', 'Data rekomendasi tidak valid');
  end if;
  v_date := private.check_for_date((p ->> 'for_date')::date);
  v_window := (v_date + (private.config('rec.departure_time') #>> '{}')::time) at time zone 'Asia/Jakarta';

  insert into recommendation_sets (
    user_id, boat_id, source_trip_id, for_date, period, window_start, max_range_km, fuel_per_km,
    avg_catch_kg, baseline_fuel_liters, departure_time, return_time, model_version, is_fallback,
    unavailable_types, valid_until
  ) values (
    v_uid, v_boat.id,
    (select id from trips where user_id = v_uid order by returned_at desc limit 1),
    v_date, (select max(period) from cluster_predictions), v_window,
    (private.config('rec.max_range_km') #>> '{}')::numeric,
    (p ->> 'fuel_per_km')::numeric, (p ->> 'avg_catch_kg')::numeric, (p ->> 'baseline_fuel_liters')::numeric,
    (private.config('rec.departure_time') #>> '{}')::time, (private.config('rec.return_time') #>> '{}')::time,
    coalesce(p ->> 'model_version', 'heuristic-0.1'), coalesce((p ->> 'is_fallback')::boolean, true),
    coalesce(p -> 'unavailable_types', '[]'),
    now() + make_interval(hours => (private.config('rec.valid_hours') #>> '{}')::int)
  )
  returning id into v_set;

  for v_item in select * from jsonb_array_elements(p -> 'items') loop
    if coalesce(v_item ->> 'type', '') not in ('fuel_saving', 'catch_max', 'balanced', 'habitual') then
      perform private.fail('VALIDATION_ERROR', 'Tipe rekomendasi tidak valid');
    end if;
    v_geom := null;
    select c.geom into v_geom from grid_cells c where c.grid_id = v_item ->> 'grid_id';
    if v_geom is null then
      perform private.fail('VALIDATION_ERROR', 'Grid rekomendasi tidak ditemukan');
    end if;
    v_zone := private.zone_json(v_geom, v_window);
    if v_zone ->> 'status' = 'closed' then
      perform private.fail('VALIDATION_ERROR', 'Rekomendasi tidak boleh di zona tertutup');
    end if;

    insert into recommendations (
      set_id, user_id, type, grid_id, point, zone, zone_rules, distance_from_port_km,
      predicted_fuel_liters, fuel_efficiency_pct, predicted_catch_kg, predicted_catch_min, predicted_catch_max,
      confidence, reason, weather_summary
    ) values (
      v_set, v_uid, v_item ->> 'type', v_item ->> 'grid_id', v_geom,
      v_zone - 'max_catch_kg',
      case when v_zone ->> 'status' = 'limited' then jsonb_build_object(
        'max_catch_kg', v_zone -> 'max_catch_kg', 'quota_remaining_kg', null, 'open_schedule', null) end,
      round((st_distance(v_geom, v_boat.home_port) / 1000)::numeric, 2),
      (v_item ->> 'predicted_fuel_liters')::numeric, (v_item ->> 'fuel_efficiency_pct')::numeric,
      (v_item ->> 'predicted_catch_kg')::numeric, (v_item ->> 'predicted_catch_min')::numeric,
      (v_item ->> 'predicted_catch_max')::numeric,
      coalesce((v_item ->> 'confidence')::numeric, 0.3), coalesce(v_item ->> 'reason', ''),
      v_item -> 'weather_summary'
    );
  end loop;
  return private.set_json(v_set);
exception when unique_violation then
  perform private.fail('VALIDATION_ERROR', 'Satu tipe rekomendasi hanya boleh sekali');
end;
$$;

create function public.api_mobile_config()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.config('mobile');
$$;

create function public.api_in_pilot(p_lat float8, p_lng float8)
returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  perform private.require_nelayan();
  return private.in_pilot(st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, 5000);
end;
$$;

revoke execute on all functions in schema private from public;
revoke execute on function
  public.api_me(), public.api_create_boat(jsonb), public.api_update_boat(uuid, jsonb),
  public.api_post_trip(jsonb), public.api_list_trips(int, int, date, date, text, text),
  public.api_trip_detail(uuid, text), public.api_rec_context(date, boolean),
  public.api_save_recommendations(jsonb), public.api_mobile_config(), public.api_in_pilot(float8, float8)
from public, anon;
grant execute on function
  public.api_me(), public.api_create_boat(jsonb), public.api_update_boat(uuid, jsonb),
  public.api_post_trip(jsonb), public.api_list_trips(int, int, date, date, text, text),
  public.api_trip_detail(uuid, text), public.api_rec_context(date, boolean),
  public.api_save_recommendations(jsonb), public.api_mobile_config(), public.api_in_pilot(float8, float8)
to authenticated;
grant execute on function public.api_mobile_config() to anon;
