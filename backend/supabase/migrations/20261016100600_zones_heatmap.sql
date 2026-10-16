-- Map, zone and heatmap API (docs/AGENTS.md 12.A + 12.B.6/7/10) on Supabase.
-- Zones switch to the spec model: a zone is a set of grid cells with status restricted | rehab,
-- rules, quota, optimistic version and history. Heatmap metrics (fatigue, pressure, CPUE, auto-flag)
-- are computed here in SQL and published with a monotonic heatmap_version.
-- Grid: the real data grid (EPSG:32749, origin 637500/8988000, 500 m, 187 x 177, ids X{xxx}_Y{yyy}),
-- see docs/frontend/panduan-implementasi-flutter-peta-laut-v2.md section 7.
-- Written with create or replace so it applies on top of the nelayan migration (20261016100500).

create extension if not exists pg_cron with schema pg_catalog;

-- ---------------------------------------------------------------------------------------------
-- Grid
-- ---------------------------------------------------------------------------------------------

create function private.grid_meta()
returns jsonb
language sql
immutable
as $$
  select '{"epsg": 32749, "origin_x": 637500, "origin_y": 8988000, "cell_size_m": 500,
           "cols": 187, "rows": 177, "indices_start_at": 1, "id_format": "X{grid_x:03}_Y{grid_y:03}",
           "coordinate_role": "cell_center", "bounds_lon_lat": [112.25, -9.15, 113.10, -8.35], "version": 1,
           "canonical_id_format": "tp-id-utm49s-500m:v2:rp{grid_y + 17975}:cp{grid_x + 1274}"}'::jsonb;
$$;

-- Same constants as private.grid_meta(); corners are computed in UTM then projected (guide section 7).
create function private.cell_polygon(x int, y int)
returns extensions.geometry
language sql
immutable
set search_path = ''
as $$
  select extensions.st_transform(extensions.st_makeenvelope(
    637500 + (x - 1) * 500, 8988000 + (y - 1) * 500, 637500 + x * 500, 8988000 + y * 500, 32749), 4326);
$$;

alter table public.grid_cells
  add column grid_x smallint,
  add column grid_y smallint,
  add column cell extensions.geometry(Polygon, 4326),
  add column is_sea boolean not null default true,
  add column has_coral boolean not null default false,
  add column coral_cover_pct numeric,
  add column coral_sensitivity numeric not null default 0.5 check (coral_sensitivity between 0 and 1);

create function private.grid_cell_fill()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_m text[] := regexp_match(new.grid_id, '^X(\d+)_Y(\d+)$');
begin
  if v_m is null then
    raise exception 'grid_id % must look like X149_Y001', new.grid_id;
  end if;
  new.grid_x := v_m[1]::int;
  new.grid_y := v_m[2]::int;
  new.cell := private.cell_polygon(new.grid_x, new.grid_y);
  return new;
end;
$$;

create trigger grid_cells_fill
  before insert or update of grid_id on public.grid_cells
  for each row execute function private.grid_cell_fill();

update public.grid_cells set grid_id = grid_id;  -- back-fill rows imported before this migration

alter table public.grid_cells
  alter column grid_x set not null,
  alter column grid_y set not null,
  alter column cell set not null;
create unique index grid_cells_xy_uq on public.grid_cells (grid_x, grid_y);

-- Same cell in main's grid-lock contract (contracts/grid-locks.md): both grids are 500 m squares in EPSG:32749
-- aligned to multiples of 500 m, so row = N / 500 = grid_y + 17975 and col = E / 500 = grid_x + 1274.
alter table public.grid_cells add column cell_id text generated always as (
  'tp-id-utm49s-500m:v2:rp' || (grid_y + 17975)::text || ':cp' || (grid_x + 1274)::text
) stored;
create unique index grid_cells_cell_id_uq on public.grid_cells (cell_id);
create index grid_cells_cell_idx on public.grid_cells using gist (cell);

-- Habitat source (coral.geojson after make_valid + AOI clip); value 1 = coral (codebook unconfirmed)
create table public.coral_areas (
  id int primary key,
  value numeric not null,
  geom extensions.geometry(MultiPolygon, 4326) not null
);
create index coral_areas_geom_idx on public.coral_areas using gist (geom);

create function private.refresh_coral()
returns int
language plpgsql
set search_path = public, extensions, pg_temp
as $$
declare
  v_n int;
begin
  update grid_cells g set has_coral = x.coral
  from (
    select c.grid_id, exists (
      select 1 from coral_areas a where a.value = 1 and st_intersects(a.geom, c.cell)
    ) as coral
    from grid_cells c
  ) x
  where x.grid_id = g.grid_id and g.has_coral is distinct from x.coral;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Zones (AGENTS.md 6, 13): the old polygon model is replaced
-- ---------------------------------------------------------------------------------------------

drop table public.zones cascade;

create table public.zones (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 3 and 100),
  status text not null check (status in ('restricted', 'rehab')),
  max_catch_kg_per_period numeric check (max_catch_kg_per_period > 0),
  max_trips_per_period int check (max_trips_per_period > 0),
  period text check (period in ('weekly', 'monthly')),
  open_schedule jsonb,
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  reason text not null,
  note text check (length(note) <= 2000),
  is_active boolean not null default true,
  archived_at timestamptz,
  version int not null default 1,
  outline extensions.geometry(MultiPolygon, 4326),
  bbox numeric[],
  changed_in_heatmap_version bigint,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_until is null or effective_until > effective_from)
);
create unique index zones_name_active_uq on public.zones (lower(name)) where is_active;
create index zones_outline_idx on public.zones using gist (outline);

-- A grid belongs to at most one active zone; archived zones keep no rows here
create table public.zone_grids (
  grid_id text primary key references public.grid_cells (grid_id),
  zone_id uuid not null references public.zones (id) on delete cascade,
  added_at timestamptz not null default now()
);
create index zone_grids_zone_idx on public.zone_grids (zone_id);

create table public.zone_history (
  id bigserial primary key,
  zone_id uuid not null references public.zones (id) on delete cascade,
  action text not null check (action in
    ('create', 'update_meta', 'update_rules', 'add_grids', 'remove_grids', 'update_status', 'archive')),
  before jsonb,
  after jsonb,
  reason text,
  changed_by uuid references auth.users (id) on delete set null,
  changed_at timestamptz not null default now()
);
create index zone_history_zone_idx on public.zone_history (zone_id, changed_at desc);

create table public.zone_quota_usage (
  zone_id uuid not null references public.zones (id) on delete cascade,
  period_start date not null,
  used_kg numeric not null default 0,
  used_trips int not null default 0,
  primary key (zone_id, period_start)
);

alter table public.fishing_points
  add constraint fishing_points_zone_fk foreign key (zone_id_at_time) references public.zones (id) on delete set null;

-- ---------------------------------------------------------------------------------------------
-- Heatmap, flags, sync (AGENTS.md 5.3, 12.A.4-12.A.8, 12.B.10)
-- ---------------------------------------------------------------------------------------------

create table public.grid_daily_load (
  grid_id text not null references public.grid_cells (grid_id),
  day date not null,
  visits int not null default 0,
  fishing_hours numeric not null default 0,
  catch_kg numeric not null default 0,
  fatigue numeric,  -- end-of-day snapshot written by the daily job, for fatigue_trend_30d
  primary key (grid_id, day)
);

-- Working table; clients only ever see the published heatmap_cells
create table public.grid_stats (
  grid_id text primary key references public.grid_cells (grid_id),
  trip_count_7d int not null default 0,
  trip_count_30d int not null default 0,
  fishing_hours_7d numeric not null default 0,
  fishing_hours_30d numeric not null default 0,
  catch_kg_7d numeric not null default 0,
  catch_kg_30d numeric not null default 0,
  cpue_7d numeric,
  cpue_30d numeric,
  pressure_7d numeric not null default 0,
  pressure_30d numeric not null default 0,
  fatigue_index numeric not null default 0,
  fatigue_level text not null default 'healthy' check (fatigue_level in ('healthy', 'tired', 'critical')),
  fatigue_smooth numeric,
  pressure_30d_smooth numeric,
  cpue_30d_smooth numeric,
  fatigue_updated_at timestamptz,
  days_low_fatigue int not null default 0,
  auto_flag text check (auto_flag in ('restricted')),
  auto_flagged_at timestamptz,
  flag_dismissed_until timestamptz,
  suggestion text check (suggestion in ('reopen')),
  last_visited_at timestamptz,
  has_data boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.heatmap_cells (
  grid_id text primary key references public.grid_cells (grid_id),
  fatigue numeric,
  fatigue_level text,
  pressure_7d numeric,
  pressure_30d numeric,
  cpue_7d numeric,
  cpue_30d numeric,
  fatigue_smooth numeric,
  pressure_30d_smooth numeric,
  cpue_30d_smooth numeric,
  has_coral boolean not null,
  zone_id uuid references public.zones (id) on delete set null,
  auto_flag text,
  auto_flagged_at timestamptz,
  flag_dismissed_until timestamptz,
  pressure_index numeric,
  trip_count_7d int,
  trip_count_30d int,
  fishing_hours_30d numeric,
  catch_kg_30d numeric,
  last_visited_at timestamptz,
  has_data boolean not null default false,
  -- AGENTS.md 12.A.2: a cell is sent when it has data, is in a zone, or is flagged
  is_relevant boolean generated always as (has_data or zone_id is not null or auto_flag is not null) stored,
  was_relevant boolean not null default false,  -- relevance before the last change, so changes can clear a cell
  updated_version bigint not null
);
create index heatmap_cells_version_idx on public.heatmap_cells (updated_version);

create sequence public.heatmap_version_seq;

create table public.heatmap_versions (
  version bigint primary key,
  trigger text not null,
  changed_cells int not null,
  changed_zone_ids uuid[] not null default '{}',
  removed_zone_ids uuid[] not null default '{}',
  created_by uuid references auth.users (id) on delete set null,
  reason text,
  created_at timestamptz not null default now()
);

create table public.heatmap_refresh_jobs (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('all', 'grids', 'zone')),
  params jsonb,
  status text not null default 'queued' check (status in ('queued', 'running', 'done', 'failed')),
  progress_pct int not null default 0,
  result_version bigint,
  changed_cells int,
  error text,
  requested_by uuid references auth.users (id) on delete set null,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index one_full_refresh_running on public.heatmap_refresh_jobs ((true))
  where scope = 'all' and status in ('queued', 'running');

create table public.flag_dismissals (
  id bigserial primary key,
  grid_id text not null references public.grid_cells (grid_id),
  dismissed_until timestamptz not null,
  reason text not null,
  dismissed_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index flag_dismissals_grid_idx on public.flag_dismissals (grid_id, dismissed_until);

create table public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  fcm_token text not null unique,
  platform text not null default 'android' check (platform in ('android', 'ios', 'web')),
  app_version text,
  last_used_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index user_devices_user_idx on public.user_devices (user_id);

-- Push queue (12.B.10). shortcut: nothing sends it yet; a sender needs FCM credentials.
create table public.push_outbox (
  id bigserial primary key,
  zone_id uuid references public.zones (id) on delete cascade,
  change text not null check (change in
    ('created', 'status_changed', 'grids_added', 'rules_changed', 'quota_exhausted', 'dissolved')),
  heatmap_version bigint not null,
  recipient_count int not null,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  attempts int not null default 0,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index push_outbox_status_idx on public.push_outbox (status, created_at);

alter table public.profiles
  add column last_heatmap_version bigint,
  add column last_seen_at timestamptz;

insert into public.app_config (key, value) values
  ('fatigue', '{"w_hours": 0.4, "w_catch": 0.4, "w_visits": 0.2, "alpha_base": 0.15,
                "half_life_coral_days": 60, "half_life_other_days": 21, "window_days": 180,
                "tired": 0.4, "critical": 0.7}'),
  ('flag', '{"threshold_on": 0.7, "threshold_off": 0.5, "dismiss_default_days": 30, "dismiss_max_days": 180,
             "reopen_below": 0.2, "reopen_days": 30}'),
  ('heatmap', '{"changes_max_versions": 50, "changes_max_age_days": 7}'),
  ('push', '{"coalesce_minutes": 10, "recent_fishing_days": 30, "range_km": 40}'),
  ('sync', '{"active_days": 7}');

alter table public.coral_areas enable row level security;
alter table public.zones enable row level security;
alter table public.zone_grids enable row level security;
alter table public.zone_history enable row level security;
alter table public.zone_quota_usage enable row level security;
alter table public.grid_daily_load enable row level security;
alter table public.grid_stats enable row level security;
alter table public.heatmap_cells enable row level security;
alter table public.heatmap_versions enable row level security;
alter table public.heatmap_refresh_jobs enable row level security;
alter table public.flag_dismissals enable row level security;
alter table public.user_devices enable row level security;
alter table public.push_outbox enable row level security;
-- No policies: every read and write goes through the security definer api_* RPCs below.

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

create function private.require_konservatif()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    perform private.fail('UNAUTHORIZED', 'Silakan login ulang');
  end if;
  if not exists (select 1 from public.profiles where id = v_uid and role = 'konservatif') then
    perform private.fail('FORBIDDEN', 'Fitur ini hanya untuk konservatif');
  end if;
  return v_uid;
end;
$$;

-- Map data is shared by both roles (AGENTS.md 12.A.4)
create function private.require_member()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    perform private.fail('UNAUTHORIZED', 'Silakan login ulang');
  end if;
  if not exists (select 1 from public.profiles where id = v_uid and role in ('nelayan', 'konservatif')) then
    perform private.fail('FORBIDDEN', 'Akun belum punya peran');
  end if;
  return v_uid;
end;
$$;

create function private.bad_text(v jsonb, lo int, hi int, required boolean)
returns text
language sql
immutable
as $$
  select case
    when v is null or jsonb_typeof(v) = 'null' then case when required then 'wajib diisi' end
    when jsonb_typeof(v) <> 'string' then 'harus teks'
    when length(trim(v #>> '{}')) not between lo and hi then format('%s sampai %s karakter', lo, hi)
  end;
$$;

create function private.bad_schedule(v jsonb)
returns text
language plpgsql
immutable
as $$
declare
  v_days int[];
  v_hours text[];
  v_msg text := 'harus {"days": [1..7], "hours": ["HH:mm", "HH:mm"]}';
begin
  if v is null or jsonb_typeof(v) = 'null' then
    return null;
  end if;
  select array_agg(x::int) into v_days from jsonb_array_elements_text(v -> 'days') x;
  select array_agg(x) into v_hours from jsonb_array_elements_text(v -> 'hours') x;
  if v_days is null or exists (select 1 from unnest(v_days) d where d not between 1 and 7)
     or coalesce(array_length(v_hours, 1), 0) <> 2
     or v_hours[1] !~ '^([01]\d|2[0-3]):[0-5]\d$' or v_hours[2] !~ '^([01]\d|2[0-3]):[0-5]\d$'
     or v_hours[1] >= v_hours[2] then
    return v_msg;
  end if;
  return null;
exception when others then
  return v_msg;
end;
$$;

-- ZoneRules (12.A.2); null input is accepted (required-ness is decided by the caller)
create function private.bad_rules(r jsonb)
returns text
language sql
immutable
as $$
  select case
    when r is null or jsonb_typeof(r) = 'null' then null
    when jsonb_typeof(r) <> 'object' then 'harus objek ZoneRules'
    when private.bad_num(r, 'max_catch_kg_per_period', 0.001, 100000000, false) is not null
      then 'max_catch_kg_per_period ' || private.bad_num(r, 'max_catch_kg_per_period', 0.001, 100000000, false)
    when private.bad_num(r, 'max_trips_per_period', 1, 1000000, false) is not null
      then 'max_trips_per_period ' || private.bad_num(r, 'max_trips_per_period', 1, 1000000, false)
    when jsonb_typeof(r -> 'max_trips_per_period') = 'number' and (r ->> 'max_trips_per_period')::numeric % 1 <> 0
      then 'max_trips_per_period harus bilangan bulat'
    when coalesce(jsonb_typeof(r -> 'max_catch_kg_per_period'), 'null') = 'null'
      and coalesce(jsonb_typeof(r -> 'max_trips_per_period'), 'null') = 'null'
      then 'isi max_catch_kg_per_period atau max_trips_per_period'
    when coalesce(r ->> 'period', '') not in ('weekly', 'monthly') then 'period harus weekly atau monthly'
    when private.bad_schedule(r -> 'open_schedule') is not null then 'open_schedule ' || private.bad_schedule(r -> 'open_schedule')
  end;
$$;

-- Validates a JSON array of grid ids: shape -> VALIDATION_ERROR, unknown or land cells -> GRID_INVALID
create function private.grid_ids(v jsonb, p_field text, p_min int, p_max int)
returns text[]
language plpgsql
stable
set search_path = public, extensions, pg_temp
as $$
declare
  v_ids text[];
  v_bad text[];
begin
  if (v is null or jsonb_typeof(v) = 'null') and p_min = 0 then
    return '{}';
  end if;
  if coalesce(jsonb_typeof(v), '') <> 'array'
     or exists (select 1 from jsonb_array_elements(v) e where jsonb_typeof(e) <> 'string') then
    perform private.fail('VALIDATION_ERROR', 'Daftar grid tidak valid',
      jsonb_build_object('fields', jsonb_build_object(p_field, 'harus array grid_id')));
  end if;
  select array_agg(distinct x) into v_ids from jsonb_array_elements_text(v) x;
  if coalesce(cardinality(v_ids), 0) not between p_min and p_max then
    perform private.fail('VALIDATION_ERROR', 'Jumlah grid tidak valid',
      jsonb_build_object('fields', jsonb_build_object(p_field, format('%s sampai %s grid unik', p_min, p_max))));
  end if;
  select array_agg(x order by x) into v_bad
  from unnest(v_ids) x
  where not exists (select 1 from grid_cells g where g.grid_id = x and g.is_sea);
  if v_bad is not null then
    perform private.fail('GRID_INVALID', 'Ada grid di luar area pilot atau daratan', jsonb_build_object('grid_ids', v_bad));
  end if;
  return coalesce(v_ids, '{}');
end;
$$;

-- Polygon input for zones: the konservatif draws a GeoJSON Polygon/MultiPolygon [lng, lat] and gets the sea
-- cells whose centre lies inside it. Zones stay grid sets; this is only a way to pick the grids.
create function private.polygon_grids(v jsonb, p_field text)
returns text[]
language plpgsql
stable
set search_path = public, extensions, pg_temp
as $$
declare
  v_geom geometry;
  v_ids text[];
  v_msg text;
begin
  if coalesce(v ->> 'type', '') not in ('Polygon', 'MultiPolygon') then
    v_msg := 'harus GeoJSON Polygon atau MultiPolygon dengan koordinat [lng, lat]';
  else
    begin
      v_geom := st_collectionextract(st_makevalid(st_setsrid(st_geomfromgeojson(v::text), 4326)), 3);
    exception when others then
      v_msg := 'GeoJSON polygon tidak valid';
    end;
    if v_msg is null and (v_geom is null or st_isempty(v_geom) or st_area(v_geom) = 0) then
      v_msg := 'luas polygon nol';
    end if;
  end if;
  if v_msg is not null then
    perform private.fail('VALIDATION_ERROR', 'Polygon tidak valid', jsonb_build_object('fields', jsonb_build_object(p_field, v_msg)));
  end if;

  select array_agg(g.grid_id order by g.grid_id) into v_ids
  from grid_cells g
  where g.is_sea and st_covers(v_geom, g.geom::geometry);
  if v_ids is null or cardinality(v_ids) > 5000 then
    perform private.fail('VALIDATION_ERROR', 'Polygon harus mencakup 1 sampai 5000 pusat grid',
      jsonb_build_object('fields', jsonb_build_object(p_field, format('mencakup %s pusat grid', coalesce(cardinality(v_ids), 0)))));
  end if;
  return v_ids;
end;
$$;

-- Zone members from either `grid_ids` or `polygon`, never both
create function private.zone_grid_input(p jsonb)
returns text[]
language plpgsql
stable
as $$
begin
  if coalesce(jsonb_typeof(p -> 'polygon'), 'null') <> 'null' then
    if coalesce(jsonb_typeof(p -> 'grid_ids'), 'null') <> 'null' then
      perform private.fail('VALIDATION_ERROR', 'Isi grid_ids atau polygon, bukan keduanya',
        jsonb_build_object('fields', jsonb_build_object('polygon', 'tidak boleh bersama grid_ids')));
    end if;
    return private.polygon_grids(p -> 'polygon', 'polygon');
  end if;
  return private.grid_ids(p -> 'grid_ids', 'grid_ids', 1, 5000);
end;
$$;

create function private.uuid_minus(a uuid[], b uuid[])
returns uuid[]
language sql
immutable
as $$
  select coalesce(array_agg(x), '{}') from (select unnest(a) except select unnest(b)) t (x);
$$;

create function private.current_version()
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(max(version), 0) from public.heatmap_versions;
$$;

create function private.fatigue_level(f numeric)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when f >= (private.config('fatigue') ->> 'critical')::numeric then 'critical'
    when f >= (private.config('fatigue') ->> 'tired')::numeric then 'tired'
    else 'healthy'
  end;
$$;

-- First day (WIB) of the quota period containing `at`: Monday for weekly, the 1st for monthly
create function private.period_start(p_period text, at timestamptz)
returns date
language sql
stable
as $$
  select case p_period
    when 'weekly' then d - (extract(isodow from d)::int - 1)
    when 'monthly' then date_trunc('month', d)::date
  end
  from (select (at at time zone 'Asia/Jakarta')::date as d) x;
$$;

create function private.zone_rules(z public.zones)
returns jsonb
language sql
immutable
as $$
  select case
    when z.max_catch_kg_per_period is null and z.max_trips_per_period is null and z.period is null
      and z.open_schedule is null then null
    else jsonb_build_object(
      'max_catch_kg_per_period', z.max_catch_kg_per_period, 'max_trips_per_period', z.max_trips_per_period,
      'period', z.period, 'open_schedule', z.open_schedule)
  end;
$$;

-- ZoneQuota for the period containing `at`; null for rehab or zones without a period
create function private.zone_quota(z public.zones, at timestamptz default now())
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select case when z.status = 'restricted' and z.period is not null then (
    select jsonb_build_object(
      'period_start', (p.ps::timestamp at time zone 'Asia/Jakarta'),
      'period_end', ((p.ps + case z.period when 'weekly' then interval '7 days' else interval '1 month' end)
                     at time zone 'Asia/Jakarta'),
      'used_kg', coalesce(u.used_kg, 0),
      'used_trips', coalesce(u.used_trips, 0),
      'remaining_kg', case when z.max_catch_kg_per_period is not null
        then greatest(z.max_catch_kg_per_period - coalesce(u.used_kg, 0), 0) end,
      'remaining_trips', case when z.max_trips_per_period is not null
        then greatest(z.max_trips_per_period - coalesce(u.used_trips, 0), 0) end,
      'exhausted', coalesce(u.used_kg, 0) >= coalesce(z.max_catch_kg_per_period, 'Infinity'::numeric)
                or coalesce(u.used_trips, 0) >= coalesce(z.max_trips_per_period, 2147483647)
    )
    from (select private.period_start(z.period, at) as ps) p
    left join zone_quota_usage u on u.zone_id = z.id and u.period_start = p.ps
  ) end;
$$;

create function private.zone_in_force(z public.zones, at timestamptz)
returns boolean
language sql
immutable
as $$
  select z.is_active and z.effective_from <= at and (z.effective_until is null or at < z.effective_until);
$$;

-- Server-side "closed" (12.A.2 enforcement without the client-side open_schedule check)
create function private.zone_closed(z public.zones, at timestamptz)
returns boolean
language sql
stable
as $$
  select coalesce(private.zone_in_force(z, at)
    and (z.status = 'rehab' or coalesce((private.zone_quota(z, at) ->> 'exhausted')::boolean, false)), false);
$$;

-- ZoneEntry (12.A.2): the one shape for zone constraints in every endpoint
create function private.zone_entry(z public.zones, p_outline boolean default false)
returns jsonb
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  select jsonb_build_object(
    'id', z.id, 'name', z.name, 'status', z.status,
    'rules', case when z.status = 'restricted' then private.zone_rules(z) end,
    'effective_from', z.effective_from, 'effective_until', z.effective_until,
    'quota', private.zone_quota(z) - 'used_kg' - 'used_trips',
    'grid_ids', coalesce((select jsonb_agg(zg.grid_id order by zg.grid_id) from zone_grids zg where zg.zone_id = z.id), '[]'),
    'bbox', to_jsonb(z.bbox),
    'zone_version', z.version,
    'changed_in_heatmap_version', z.changed_in_heatmap_version,
    'updated_at', z.updated_at
  ) || case when p_outline then jsonb_build_object('outline', st_asgeojson(z.outline, 7)::jsonb) else '{}' end;
$$;

create function private.zone_snapshot(p_zone uuid)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'name', z.name, 'status', z.status, 'rules', private.zone_rules(z),
    'effective_from', z.effective_from, 'effective_until', z.effective_until, 'note', z.note,
    'grid_ids', coalesce((select jsonb_agg(zg.grid_id order by zg.grid_id) from zone_grids zg where zg.zone_id = z.id), '[]')
  )
  from zones z where z.id = p_zone;
$$;

create function private.add_history(p_zone uuid, p_action text, p_before jsonb, p_after jsonb, p_reason text, p_uid uuid)
returns void
language sql
set search_path = public, pg_temp
as $$
  insert into zone_history (zone_id, action, before, after, reason, changed_by)
  values (p_zone, p_action, p_before, p_after, p_reason, p_uid);
$$;

create function private.history_json(h public.zone_history)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id', h.id, 'action', h.action, 'before', h.before, 'after', h.after, 'reason', h.reason,
    'changed_by', (select jsonb_build_object('id', p.id, 'name', p.full_name) from profiles p where p.id = h.changed_by),
    'changed_at', h.changed_at
  );
$$;

create function private.zone_refresh_geometry(p_zone uuid)
returns void
language plpgsql
set search_path = public, extensions, pg_temp
as $$
declare
  v_outline geometry;
begin
  select st_multi(st_union(g.cell)) into v_outline
  from zone_grids zg join grid_cells g on g.grid_id = zg.grid_id
  where zg.zone_id = p_zone;
  update zones set
    outline = v_outline,
    bbox = case when v_outline is not null then array[
      round(st_xmin(v_outline)::numeric, 6), round(st_ymin(v_outline)::numeric, 6),
      round(st_xmax(v_outline)::numeric, 6), round(st_ymax(v_outline)::numeric, 6)] end
  where id = p_zone;
end;
$$;

-- ZoneAggregate (12.A.2) from the published snapshot; p_zone adds the quota
create function private.zone_aggregate(p_grids text[], p_zone uuid)
returns jsonb
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  select jsonb_build_object(
    'grid_count', count(*),
    'area_km2', count(*) * 0.25,
    'coral_grid_count', count(*) filter (where g.has_coral),
    'coral_pct', round(100.0 * count(*) filter (where g.has_coral) / nullif(count(*), 0), 1),
    'fatigue_avg', round(avg(h.fatigue), 3),
    'fatigue_max', round(max(h.fatigue), 3),
    'fatigue_distribution', jsonb_build_object(
      'healthy', count(*) filter (where h.fatigue_level = 'healthy'),
      'tired', count(*) filter (where h.fatigue_level = 'tired'),
      'critical', count(*) filter (where h.fatigue_level = 'critical')),
    'flagged_grid_count', count(*) filter (where h.auto_flag is not null),
    'trip_count_30d', (
      select count(distinct f.trip_id) from fishing_points f join trips t on t.id = f.trip_id
      where f.grid_id = any(p_grids) and t.departed_at >= now() - interval '30 days'),
    'catch_kg_30d', coalesce(sum(h.catch_kg_30d), 0),
    'fishing_hours_30d', coalesce(sum(h.fishing_hours_30d), 0),
    'cpue_30d', round(sum(h.catch_kg_30d) / nullif(sum(h.fishing_hours_30d), 0), 2),
    'violation_count_30d', (
      select count(distinct f.trip_id) from fishing_points f join trips t on t.id = f.trip_id
      where f.grid_id = any(p_grids) and f.zone_status_at_time = 'rehab' and t.departed_at >= now() - interval '30 days'),
    'quota', (select private.zone_quota(z) from zones z where z.id = p_zone)
  )
  from unnest(p_grids) x (grid_id)
  join grid_cells g on g.grid_id = x.grid_id
  left join heatmap_cells h on h.grid_id = x.grid_id;
$$;

-- How many active fishers already hold data at least as new as this zone's last change (12.B.10)
create function private.zone_sync(z public.zones)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'active_fishers_7d', count(*),
    'known_by', count(*) filter (where p.last_heatmap_version >= coalesce(z.changed_in_heatmap_version, 0)),
    'known_by_pct', round(100.0 * count(*) filter (where p.last_heatmap_version >= coalesce(z.changed_in_heatmap_version, 0))
                          / nullif(count(*), 0), 1)
  )
  from profiles p
  where p.role = 'nelayan'
    and p.last_seen_at >= now() - make_interval(days => (private.config('sync') ->> 'active_days')::int);
$$;

create function private.zone_detail(p_zone uuid)
returns jsonb
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  select jsonb_build_object(
    'id', z.id, 'name', z.name, 'status', z.status, 'rules', private.zone_rules(z),
    'reason', z.reason, 'note', z.note, 'effective_from', z.effective_from, 'effective_until', z.effective_until,
    'grid_ids', to_jsonb(gl.ids),
    'outline', st_asgeojson(z.outline, 7)::jsonb,
    'bbox', to_jsonb(z.bbox),
    'aggregate', private.zone_aggregate(gl.ids, z.id),
    'grids', coalesce((
      select jsonb_agg(jsonb_build_object(
        'grid_id', g.grid_id, 'has_coral', g.has_coral, 'fatigue_index', h.fatigue, 'fatigue_level', h.fatigue_level,
        'catch_kg_30d', h.catch_kg_30d, 'trip_count_30d', h.trip_count_30d
      ) order by h.fatigue desc nulls last, g.grid_id)
      from unnest(gl.ids) x (grid_id) join grid_cells g on g.grid_id = x.grid_id
      left join heatmap_cells h on h.grid_id = x.grid_id
    ), '[]'),
    'recent_history', coalesce((
      select jsonb_agg(private.history_json(hh) order by hh.changed_at desc, hh.id desc)
      from (select * from zone_history where zone_id = z.id order by changed_at desc, id desc limit 5) hh
    ), '[]'),
    'entry', private.zone_entry(z, false),
    'sync', private.zone_sync(z),
    'is_active', z.is_active, 'archived_at', z.archived_at, 'version', z.version,
    'heatmap_version', private.current_version(),
    'created_by', (select jsonb_build_object('id', p.id, 'name', p.full_name) from profiles p where p.id = z.created_by),
    'created_at', z.created_at, 'updated_at', z.updated_at
  )
  from zones z
  cross join lateral (
    select coalesce(array_agg(zg.grid_id order by zg.grid_id), '{}') as ids from zone_grids zg where zg.zone_id = z.id
  ) gl
  where z.id = p_zone;
$$;

create function private.zone_summary(z public.zones)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id', z.id, 'name', z.name, 'status', z.status,
    'grid_count', a.n, 'area_km2', a.n * 0.25, 'fatigue_avg', a.favg, 'fatigue_max', a.fmax,
    'quota_remaining_kg', q.q -> 'remaining_kg',
    'quota_exhausted', coalesce((q.q ->> 'exhausted')::boolean, false),
    'effective_until', z.effective_until, 'bbox', to_jsonb(z.bbox), 'is_active', z.is_active, 'updated_at', z.updated_at
  )
  from (
    select count(*) as n, round(avg(h.fatigue), 3) as favg, round(max(h.fatigue), 3) as fmax
    from zone_grids zg left join heatmap_cells h on h.grid_id = zg.grid_id
    where zg.zone_id = z.id
  ) a
  cross join (select private.zone_quota(z) as q) q;
$$;

-- ---------------------------------------------------------------------------------------------
-- Metrics, flags, publish
-- ---------------------------------------------------------------------------------------------

-- Recomputes grid_stats for p_grids (null = all) from trips and daily loads (AGENTS.md 5.3, 5.4).
-- shortcut: fatigue is the closed form sum(alpha * load_d * exp(-lambda * age)) clamped once at the end,
-- not clamped per day as in the spec's recurrence; upgrade to an iterative daily table if it matters.
create function private.recompute_stats(p_grids text[])
returns void
language plpgsql
set search_path = public, extensions, pg_temp
as $$
declare
  v_c jsonb := private.config('fatigue');
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_h numeric;
  v_kg numeric;
  v_visits numeric;
  v_p30 numeric;
  v_p7 numeric;
begin
  -- norm(): divide by the 95th percentile of non-empty daily loads over 90 days
  select percentile_cont(0.95) within group (order by fishing_hours) filter (where fishing_hours > 0),
         percentile_cont(0.95) within group (order by catch_kg) filter (where catch_kg > 0),
         percentile_cont(0.95) within group (order by visits) filter (where visits > 0)
    into v_h, v_kg, v_visits
  from grid_daily_load
  where day > v_today - 90;

  insert into grid_stats as s (
    grid_id, trip_count_7d, trip_count_30d, fishing_hours_7d, fishing_hours_30d, catch_kg_7d, catch_kg_30d,
    cpue_7d, cpue_30d, fatigue_index, fatigue_level, fatigue_updated_at, last_visited_at, has_data, updated_at
  )
  select g.grid_id,
    coalesce(w.t7, 0), coalesce(w.t30, 0), coalesce(w.h7, 0), coalesce(w.h30, 0), coalesce(w.c7, 0), coalesce(w.c30, 0),
    round(w.c7 / nullif(w.h7, 0), 3), round(w.c30 / nullif(w.h30, 0), 3),
    round(least(1, coalesce(f.fat, 0)), 4), private.fatigue_level(least(1, coalesce(f.fat, 0))), now(),
    lv.last_at, lv.last_at is not null, now()
  from grid_cells g
  left join lateral (
    select count(distinct x.trip_id) filter (where x.departed_at >= now() - interval '7 days') as t7,
           count(distinct x.trip_id) as t30,
           sum(x.fishing_hours) filter (where x.departed_at >= now() - interval '7 days') as h7,
           sum(x.fishing_hours) as h30,
           sum(x.allocated_catch_kg) filter (where x.departed_at >= now() - interval '7 days') as c7,
           sum(x.allocated_catch_kg) as c30
    from (
      select fp.trip_id, fp.fishing_hours, fp.allocated_catch_kg, tr.departed_at
      from fishing_points fp join trips tr on tr.id = fp.trip_id
      where fp.grid_id = g.grid_id and tr.departed_at >= now() - interval '30 days'
    ) x
  ) w on true
  left join lateral (
    select max(tr.departed_at) as last_at
    from fishing_points fp join trips tr on tr.id = fp.trip_id
    where fp.grid_id = g.grid_id
  ) lv on true
  left join lateral (
    select sum(
      (v_c ->> 'alpha_base')::numeric * (0.5 + g.coral_sensitivity)
      * ((v_c ->> 'w_hours')::numeric * least(1, coalesce(l.fishing_hours / nullif(v_h, 0), 0))
       + (v_c ->> 'w_catch')::numeric * least(1, coalesce(l.catch_kg / nullif(v_kg, 0), 0))
       + (v_c ->> 'w_visits')::numeric * least(1, coalesce(l.visits / nullif(v_visits, 0), 0)))
      * exp(-ln(2::numeric) / (case when g.has_coral then (v_c ->> 'half_life_coral_days')::numeric
                           else (v_c ->> 'half_life_other_days')::numeric end) * (v_today - l.day))
    ) as fat
    from grid_daily_load l
    where l.grid_id = g.grid_id and l.day > v_today - (v_c ->> 'window_days')::int and l.day <= v_today
  ) f on true
  where p_grids is null or g.grid_id = any(p_grids)
  on conflict (grid_id) do update set
    trip_count_7d = excluded.trip_count_7d, trip_count_30d = excluded.trip_count_30d,
    fishing_hours_7d = excluded.fishing_hours_7d, fishing_hours_30d = excluded.fishing_hours_30d,
    catch_kg_7d = excluded.catch_kg_7d, catch_kg_30d = excluded.catch_kg_30d,
    cpue_7d = excluded.cpue_7d, cpue_30d = excluded.cpue_30d,
    fatigue_index = excluded.fatigue_index, fatigue_level = excluded.fatigue_level,
    fatigue_updated_at = excluded.fatigue_updated_at, last_visited_at = excluded.last_visited_at,
    has_data = excluded.has_data, updated_at = excluded.updated_at;

  -- pressure: fishing hours relative to the 95th percentile across grids
  select percentile_cont(0.95) within group (order by fishing_hours_30d) filter (where fishing_hours_30d > 0),
         percentile_cont(0.95) within group (order by fishing_hours_7d) filter (where fishing_hours_7d > 0)
    into v_p30, v_p7
  from grid_stats;
  update grid_stats set
    pressure_30d = round(least(1, coalesce(fishing_hours_30d / nullif(v_p30, 0), 0)), 4),
    pressure_7d = round(least(1, coalesce(fishing_hours_7d / nullif(v_p7, 0), 0)), 4)
  where p_grids is null or grid_id = any(p_grids);

  -- AGENTS.md 5.4: mean over the cell and its 8 neighbours
  update grid_stats s set
    fatigue_smooth = n.f, pressure_30d_smooth = n.p, cpue_30d_smooth = n.c
  from (
    select g.grid_id, round(avg(s2.fatigue_index), 4) as f, round(avg(s2.pressure_30d), 4) as p,
           round(avg(s2.cpue_30d), 3) as c
    from grid_cells g
    join grid_cells nb on nb.grid_x between g.grid_x - 1 and g.grid_x + 1 and nb.grid_y between g.grid_y - 1 and g.grid_y + 1
    join grid_stats s2 on s2.grid_id = nb.grid_id
    where p_grids is null or g.grid_id = any(p_grids)
    group by g.grid_id
  ) n
  where s.grid_id = n.grid_id;
end;
$$;

-- Auto-flag rules (12.A.8). Returns the grids whose flag would change; writes only when not a dry run.
create function private.auto_flag(p_grids text[], p_dry_run boolean, out added text[], out removed text[], out evaluated int)
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_c jsonb := private.config('flag');
begin
  select count(*) into evaluated from grid_stats where p_grids is null or grid_id = any(p_grids);
  select coalesce(array_agg(s.grid_id order by s.grid_id), '{}') into added
  from grid_stats s
  where (p_grids is null or s.grid_id = any(p_grids))
    and s.auto_flag is null
    and s.fatigue_index >= (v_c ->> 'threshold_on')::numeric
    and not exists (select 1 from zone_grids zg where zg.grid_id = s.grid_id)
    and (s.flag_dismissed_until is null or s.flag_dismissed_until <= now());
  select coalesce(array_agg(s.grid_id order by s.grid_id), '{}') into removed
  from grid_stats s
  where (p_grids is null or s.grid_id = any(p_grids))
    and s.auto_flag is not null
    and (s.fatigue_index < (v_c ->> 'threshold_off')::numeric
         or exists (select 1 from zone_grids zg where zg.grid_id = s.grid_id));
  if not p_dry_run then
    update grid_stats set auto_flag = 'restricted', auto_flagged_at = now() where grid_id = any(added);
    update grid_stats set auto_flag = null, auto_flagged_at = null where grid_id = any(removed);
  end if;
end;
$$;

-- Publishes p_grids (null = all) to heatmap_cells under a new heatmap_version in the caller's transaction.
-- Only cells whose values changed get the new updated_version.
create function private.publish(
  p_grids text[], p_trigger text, p_reason text default null,
  p_changed_zones uuid[] default '{}', p_removed_zones uuid[] default '{}'
)
returns bigint
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_version bigint := nextval('heatmap_version_seq');
  v_changed int;
begin
  with src as (
    select g.grid_id, s.fatigue_index as fatigue, s.fatigue_level, s.pressure_7d, s.pressure_30d, s.cpue_7d, s.cpue_30d,
      s.fatigue_smooth, s.pressure_30d_smooth, s.cpue_30d_smooth, g.has_coral, zg.zone_id,
      s.auto_flag, s.auto_flagged_at, s.flag_dismissed_until, s.pressure_30d as pressure_index,
      s.trip_count_7d, s.trip_count_30d, s.fishing_hours_30d, s.catch_kg_30d, s.last_visited_at,
      coalesce(s.has_data, false) as has_data
    from grid_cells g
    left join grid_stats s on s.grid_id = g.grid_id
    left join zone_grids zg on zg.grid_id = g.grid_id
    where p_grids is null or g.grid_id = any(p_grids)
  ), up as (
    insert into heatmap_cells as h (
      grid_id, fatigue, fatigue_level, pressure_7d, pressure_30d, cpue_7d, cpue_30d, fatigue_smooth,
      pressure_30d_smooth, cpue_30d_smooth, has_coral, zone_id, auto_flag, auto_flagged_at, flag_dismissed_until,
      pressure_index, trip_count_7d, trip_count_30d, fishing_hours_30d, catch_kg_30d, last_visited_at, has_data,
      was_relevant, updated_version
    )
    select src.*, false, v_version from src
    on conflict (grid_id) do update set
      fatigue = excluded.fatigue, fatigue_level = excluded.fatigue_level,
      pressure_7d = excluded.pressure_7d, pressure_30d = excluded.pressure_30d,
      cpue_7d = excluded.cpue_7d, cpue_30d = excluded.cpue_30d,
      fatigue_smooth = excluded.fatigue_smooth, pressure_30d_smooth = excluded.pressure_30d_smooth,
      cpue_30d_smooth = excluded.cpue_30d_smooth, has_coral = excluded.has_coral, zone_id = excluded.zone_id,
      auto_flag = excluded.auto_flag, auto_flagged_at = excluded.auto_flagged_at,
      flag_dismissed_until = excluded.flag_dismissed_until, pressure_index = excluded.pressure_index,
      trip_count_7d = excluded.trip_count_7d, trip_count_30d = excluded.trip_count_30d,
      fishing_hours_30d = excluded.fishing_hours_30d, catch_kg_30d = excluded.catch_kg_30d,
      last_visited_at = excluded.last_visited_at, has_data = excluded.has_data,
      was_relevant = h.is_relevant, updated_version = excluded.updated_version
    where (h.fatigue, h.fatigue_level, h.pressure_7d, h.pressure_30d, h.cpue_7d, h.cpue_30d, h.fatigue_smooth,
           h.pressure_30d_smooth, h.cpue_30d_smooth, h.has_coral, h.zone_id, h.auto_flag, h.flag_dismissed_until,
           h.trip_count_7d, h.trip_count_30d, h.fishing_hours_30d, h.catch_kg_30d, h.last_visited_at, h.has_data)
      is distinct from
          (excluded.fatigue, excluded.fatigue_level, excluded.pressure_7d, excluded.pressure_30d, excluded.cpue_7d,
           excluded.cpue_30d, excluded.fatigue_smooth, excluded.pressure_30d_smooth, excluded.cpue_30d_smooth,
           excluded.has_coral, excluded.zone_id, excluded.auto_flag, excluded.flag_dismissed_until,
           excluded.trip_count_7d, excluded.trip_count_30d, excluded.fishing_hours_30d, excluded.catch_kg_30d,
           excluded.last_visited_at, excluded.has_data)
    returning 1
  )
  select count(*) into v_changed from up;

  insert into heatmap_versions (version, trigger, changed_cells, changed_zone_ids, removed_zone_ids, created_by, reason)
  values (v_version, p_trigger, v_changed, coalesce(p_changed_zones, '{}'), coalesce(p_removed_zones, '{}'), auth.uid(), p_reason);
  update zones set changed_in_heatmap_version = v_version
  where id = any(coalesce(p_changed_zones, '{}') || coalesce(p_removed_zones, '{}'));
  return v_version;
end;
$$;

-- Queues a zone_changed push (12.B.10), merging with a queued push for the same zone within the
-- coalesce window. Returns the number of fishers with a registered device that would receive it.
create function private.queue_push(p_zone uuid, p_change text, p_version bigint)
returns int
language plpgsql
set search_path = public, extensions, pg_temp
as $$
declare
  v_c jsonb := private.config('push');
  v_outline geometry := (select outline from zones where id = p_zone);
  v_count int;
begin
  if v_outline is null then
    return 0;
  end if;
  select count(distinct d.user_id) into v_count
  from user_devices d
  where d.user_id in (
    select b.user_id from boats b
    where b.is_default and b.deleted_at is null
      and st_dwithin(b.home_port, v_outline::geography, (v_c ->> 'range_km')::float8 * 1000)
    union
    select t.user_id from fishing_points f join trips t on t.id = f.trip_id
    where t.departed_at >= now() - make_interval(days => (v_c ->> 'recent_fishing_days')::int)
      and st_intersects(f.location, v_outline::geography)
  );

  update push_outbox set change = p_change, heatmap_version = p_version, recipient_count = v_count
  where zone_id = p_zone and status = 'queued'
    and created_at > now() - make_interval(mins => (v_c ->> 'coalesce_minutes')::int);
  if not found then
    insert into push_outbox (zone_id, change, heatmap_version, recipient_count)
    values (p_zone, p_change, p_version, v_count);
  end if;
  return v_count;
end;
$$;

-- Resolves grids already in another active zone: reject -> GRID_CONFLICT, skip -> drop them, move -> take them.
create function private.take_grids(p_zone uuid, p_grids text[], p_on_conflict text,
  out kept text[], out skipped text[], out moved text[])
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_conflicts jsonb;
  v_ids text[];
begin
  select jsonb_agg(jsonb_build_object('grid_id', zg.grid_id, 'zone_id', z.id, 'zone_name', z.name) order by zg.grid_id),
         array_agg(zg.grid_id)
    into v_conflicts, v_ids
  from zone_grids zg join zones z on z.id = zg.zone_id
  where zg.grid_id = any(p_grids) and zg.zone_id is distinct from p_zone;

  kept := p_grids;
  skipped := '{}';
  moved := '{}';
  if v_ids is null then
    return;
  end if;
  if p_on_conflict = 'skip' then
    kept := array(select unnest(p_grids) except select unnest(v_ids));
    skipped := v_ids;
  elsif p_on_conflict = 'move' then
    moved := v_ids;
  else
    perform private.fail('GRID_CONFLICT', 'Ada grid yang sudah masuk zona aktif lain',
      jsonb_build_object('conflicts', v_conflicts));
  end if;
end;
$$;

-- Archives a zone (status -> normal, or it lost every grid to another zone)
create function private.archive_zone(p_zone uuid, p_reason text, p_uid uuid)
returns text[]
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_released text[];
begin
  select coalesce(array_agg(grid_id order by grid_id), '{}') into v_released from zone_grids where zone_id = p_zone;
  perform private.add_history(p_zone, 'archive', private.zone_snapshot(p_zone),
    jsonb_build_object('status', 'normal', 'is_active', false), p_reason, p_uid);
  delete from zone_grids where zone_id = p_zone;
  update zones set is_active = false, archived_at = now(), version = version + 1, updated_at = now() where id = p_zone;
  return v_released;
end;
$$;

-- Removes p_grids from whatever zones hold them (used by on_conflict = move)
create function private.release_grids(p_grids text[], p_reason text, p_uid uuid, out changed uuid[], out archived uuid[])
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_zone uuid;
  v_ids text[];
begin
  changed := '{}';
  archived := '{}';
  for v_zone in select distinct zone_id from zone_grids where grid_id = any(p_grids) loop
    select array_agg(grid_id order by grid_id) into v_ids from zone_grids where zone_id = v_zone and grid_id = any(p_grids);
    if exists (select 1 from zone_grids where zone_id = v_zone and not (grid_id = any(p_grids))) then
      delete from zone_grids where zone_id = v_zone and grid_id = any(v_ids);
      update zones set version = version + 1, updated_at = now() where id = v_zone;
      perform private.zone_refresh_geometry(v_zone);
      perform private.add_history(v_zone, 'remove_grids', jsonb_build_object('grid_ids', v_ids), null, p_reason, p_uid);
      changed := changed || v_zone;
    else
      perform private.archive_zone(v_zone, p_reason, p_uid);
      archived := archived || v_zone;
    end if;
  end loop;
end;
$$;

-- Locks a zone for an edit and checks existence, archive state and optimistic version
create function private.lock_zone(p_zone uuid, p_version jsonb)
returns public.zones
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_zone zones;
begin
  if coalesce(jsonb_typeof(p_version), '') <> 'number' then
    perform private.fail('VALIDATION_ERROR', 'version wajib diisi',
      jsonb_build_object('fields', jsonb_build_object('version', 'wajib angka')));
  end if;
  select * into v_zone from zones where id = p_zone for update;
  if v_zone.id is null then
    perform private.fail('ZONE_NOT_FOUND', 'Zona tidak ditemukan');
  end if;
  if not v_zone.is_active then
    perform private.fail('ZONE_ARCHIVED', 'Zona sudah dibubarkan');
  end if;
  if v_zone.version <> (p_version #>> '{}')::numeric then
    perform private.fail('VERSION_CONFLICT', 'Zona sudah diubah orang lain, muat ulang',
      jsonb_build_object('current_version', v_zone.version));
  end if;
  return v_zone;
end;
$$;

-- After a trip: daily loads, zone quota, then recompute and publish the touched cells and their neighbours
create function private.after_trip(p_trip uuid)
returns bigint
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_trip trips;
  v_zone zones;
  v_targets text[];
  v_changed uuid[] := '{}';
  v_exhausted uuid[] := '{}';
  v_was boolean;
  v_version bigint;
  r record;
begin
  select * into v_trip from trips where id = p_trip;

  insert into grid_daily_load as l (grid_id, day, visits, fishing_hours, catch_kg)
  select f.grid_id, (coalesce(f.started_at, v_trip.departed_at) at time zone 'Asia/Jakarta')::date,
    count(*), coalesce(sum(f.fishing_hours), 0), coalesce(sum(f.allocated_catch_kg), 0)
  from fishing_points f
  where f.trip_id = p_trip and f.grid_id is not null
  group by 1, 2
  on conflict (grid_id, day) do update set
    visits = l.visits + excluded.visits,
    fishing_hours = l.fishing_hours + excluded.fishing_hours,
    catch_kg = l.catch_kg + excluded.catch_kg;

  for r in
    select f.zone_id_at_time as zone_id, coalesce(sum(f.allocated_catch_kg), 0) as kg
    from fishing_points f
    where f.trip_id = p_trip and f.zone_status_at_time = 'restricted' and f.zone_id_at_time is not null
    group by 1
  loop
    select * into v_zone from zones where id = r.zone_id;
    continue when v_zone.id is null or v_zone.period is null;
    v_was := private.zone_closed(v_zone, now());
    insert into zone_quota_usage as u (zone_id, period_start, used_kg, used_trips)
    values (r.zone_id, private.period_start(v_zone.period, v_trip.departed_at), r.kg, 1)
    on conflict (zone_id, period_start) do update set used_kg = u.used_kg + excluded.used_kg, used_trips = u.used_trips + 1;
    v_changed := v_changed || r.zone_id;
    if not v_was and private.zone_closed(v_zone, now()) then
      v_exhausted := v_exhausted || r.zone_id;
    end if;
  end loop;

  select array_agg(distinct nb.grid_id) into v_targets
  from fishing_points f
  join grid_cells g on g.grid_id = f.grid_id
  join grid_cells nb on nb.grid_x between g.grid_x - 1 and g.grid_x + 1 and nb.grid_y between g.grid_y - 1 and g.grid_y + 1
  where f.trip_id = p_trip;
  v_targets := coalesce(v_targets, '{}');
  if cardinality(v_targets) = 0 and cardinality(v_changed) = 0 then
    return null;
  end if;

  perform private.recompute_stats(v_targets);
  perform private.auto_flag(v_targets, false);
  v_version := private.publish(v_targets, 'trip', null, v_changed, '{}');
  perform private.queue_push(z, 'quota_exhausted', v_version) from unnest(v_exhausted) z;
  return v_version;
end;
$$;

-- Daily job (00:10 WIB): fatigue for every grid, flags, reopen suggestions, trend snapshot, quota rollover
create function private.daily_refresh()
returns bigint
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_c jsonb := private.config('flag');
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_rollover uuid[];
begin
  perform private.recompute_stats(null);
  perform private.auto_flag(null, false);

  update grid_stats s set
    days_low_fatigue = case when s.fatigue_index < (v_c ->> 'reopen_below')::numeric then s.days_low_fatigue + 1 else 0 end,
    suggestion = case when s.fatigue_index < (v_c ->> 'reopen_below')::numeric
                       and s.days_low_fatigue + 1 >= (v_c ->> 'reopen_days')::int then 'reopen' end
  where exists (
    select 1 from zone_grids zg join zones z on z.id = zg.zone_id where zg.grid_id = s.grid_id and z.status = 'rehab');
  update grid_stats s set days_low_fatigue = 0, suggestion = null
  where (s.days_low_fatigue > 0 or s.suggestion is not null)
    and not exists (
      select 1 from zone_grids zg join zones z on z.id = zg.zone_id where zg.grid_id = s.grid_id and z.status = 'rehab');

  insert into grid_daily_load as l (grid_id, day, fatigue)
  select grid_id, v_today, fatigue_index from grid_stats where fatigue_index > 0
  on conflict (grid_id, day) do update set fatigue = excluded.fatigue;

  -- a new quota period started today: clients need the fresh ZoneEntry.quota
  select coalesce(array_agg(id), '{}') into v_rollover
  from zones
  where is_active and status = 'restricted' and period is not null and private.period_start(period, now()) = v_today;

  return private.publish(null, 'daily', null, v_rollover, '{}');
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Existing consumers moved to the new zone model
-- ---------------------------------------------------------------------------------------------

-- Zone of the grid nearest to a point, if active at that moment (signature kept from the nelayan migration)
create or replace function private.zone_at(g extensions.geography, at timestamptz)
returns table (id uuid, name text, status text, max_catch_kg numeric)
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  select z.id, z.name, z.status, z.max_catch_kg_per_period
  from zone_grids zg join zones z on z.id = zg.zone_id
  where zg.grid_id = private.nearest_grid(g) and private.zone_in_force(z, at);
$$;

-- Zone summary for recommendations: status normal | restricted | rehab and whether it is closed then
create or replace function private.zone_json(g extensions.geography, at timestamptz)
returns jsonb
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  select coalesce(
    (select jsonb_build_object(
       'id', z.id, 'name', z.name, 'status', z.status, 'closed', private.zone_closed(z, at),
       'quota_remaining_kg', private.zone_quota(z, at) -> 'remaining_kg', 'open_schedule', z.open_schedule)
     from zone_grids zg join zones z on z.id = zg.zone_id
     where zg.grid_id = private.nearest_grid(g) and private.zone_in_force(z, at)),
    '{"id": null, "name": null, "status": "normal", "closed": false, "quota_remaining_kg": null, "open_schedule": null}'::jsonb
  );
$$;

create or replace function public.get_fishing_spots(p_period text, p_min_level int default 4)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select jsonb_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(jsonb_agg(jsonb_build_object(
      'type', 'Feature',
      'id', g.grid_id,
      'geometry', st_asgeojson(g.geom)::jsonb,
      'properties', jsonb_build_object(
        'grid_id', g.grid_id,
        'level', p.level,
        'potential_score', p.potential_score,
        'sst', p.sst,
        'chlor_a', p.chlor_a,
        'depth_m', p.depth_m,
        'zone_id', z.id,
        'zone_status', coalesce(z.status, 'normal'),
        'quota_remaining_kg', private.zone_quota(z) -> 'remaining_kg'
      )
    ) order by p.potential_score desc), '[]'::jsonb)
  )
  from cluster_predictions p
  join grid_cells g on g.grid_id = p.grid_id
  left join zone_grids zg on zg.grid_id = g.grid_id
  left join zones z on z.id = zg.zone_id and private.zone_in_force(z, now())
  where p.period = p_period
    and p.level >= p_min_level
    and auth.uid() is not null
    -- rehab zones and restricted zones with an exhausted quota are never offered
    and not private.zone_closed(z, now());
$$;

-- Closed areas for the Go route planner over a trip window, as GeoJSON MultiPolygons
create function public.closed_zone_outlines(p_from timestamptz, p_to timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select coalesce(jsonb_agg(st_asgeojson(z.outline, 7)::jsonb), '[]')
  from zones z
  where auth.uid() is not null
    and z.is_active and z.outline is not null
    and z.effective_from <= p_to and (z.effective_until is null or z.effective_until > p_from)
    and (z.status = 'rehab' or coalesce((private.zone_quota(z) ->> 'exhausted')::boolean, false));
$$;

-- ---------------------------------------------------------------------------------------------
-- Map API (shared by nelayan and konservatif, 12.A.4)
-- ---------------------------------------------------------------------------------------------

create function public.api_grid_meta()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_member();
  return private.grid_meta() || jsonb_build_object('cell_count', (select count(*) from grid_cells));
end;
$$;

-- Bit (grid_y - 1) * cols + (grid_x - 1) is 1 for a sea cell with data; bytes are MSB first, base64.
create function public.api_sea_mask()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_cols int := (private.grid_meta() ->> 'cols')::int;
  v_len int := v_cols * (private.grid_meta() ->> 'rows')::int;
  v_hex text;
begin
  perform private.require_member();
  select string_agg(lpad(to_hex(b.v), 2, '0'), '' order by b.k) into v_hex
  from (
    select i / 8 as k, sum(case when s.grid_id is not null then 1 << (7 - i % 8) else 0 end)::int as v
    from generate_series(0, v_len - 1) i
    left join grid_cells s on s.is_sea and (s.grid_y - 1) * v_cols + (s.grid_x - 1) = i
    group by i / 8
  ) b;
  return jsonb_build_object(
    'encoding', 'bitset-base64', 'order', 'y_then_x', 'cols', v_cols, 'length', v_len,
    'bits', replace(encode(decode(v_hex, 'hex'), 'base64'), E'\n', ''),
    'version', private.grid_meta() -> 'version'
  );
end;
$$;

create function private.check_view(p_window text, p_bbox float8[])
returns void
language plpgsql
immutable
as $$
begin
  if coalesce(p_window, '30d') not in ('7d', '30d') then
    perform private.fail('VALIDATION_ERROR', 'window harus 7d atau 30d');
  end if;
  if p_bbox is not null and (cardinality(p_bbox) <> 4 or p_bbox[1] >= p_bbox[3] or p_bbox[2] >= p_bbox[4]) then
    perform private.fail('VALIDATION_ERROR', 'bbox harus [minLng, minLat, maxLng, maxLat]');
  end if;
end;
$$;

-- HeatmapCell tuple in the fixed column order of 12.A.2
create function private.cell_tuple(h public.heatmap_cells, p_window text, p_smooth boolean)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_array(
    h.grid_id,
    case when p_smooth then h.fatigue_smooth else h.fatigue end,
    h.fatigue_level,
    case when p_window = '7d' then h.pressure_7d when p_smooth then h.pressure_30d_smooth else h.pressure_30d end,
    case when p_window = '7d' then h.cpue_7d when p_smooth then h.cpue_30d_smooth else h.cpue_30d end,
    h.has_coral, h.zone_id, h.auto_flag
  );
$$;

create function private.in_view(g public.grid_cells, p_bbox float8[], p_x_min int, p_x_max int, p_y_min int, p_y_max int)
returns boolean
language sql
immutable
set search_path = extensions, pg_temp
as $$
  select (p_bbox is null or (st_x(g.geom::geometry) between p_bbox[1] and p_bbox[3]
                             and st_y(g.geom::geometry) between p_bbox[2] and p_bbox[4]))
     and (p_x_min is null or g.grid_x >= p_x_min) and (p_x_max is null or g.grid_x <= p_x_max)
     and (p_y_min is null or g.grid_y >= p_y_min) and (p_y_max is null or g.grid_y <= p_y_max);
$$;

create function private.heatmap_scale(p_window text, p_smooth boolean)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'fatigue', jsonb_build_object('min', 0, 'max', 1, 'thresholds', jsonb_build_object(
      'tired', (private.config('fatigue') -> 'tired'), 'critical', (private.config('fatigue') -> 'critical'))),
    'pressure', jsonb_build_object('min', 0, 'max', 1),
    'cpue', jsonb_build_object('min', 0, 'unit', 'kg/jam', 'max', (
      select round(percentile_cont(0.95) within group (order by
        case when p_window = '7d' then cpue_7d when p_smooth then cpue_30d_smooth else cpue_30d end)::numeric, 3)
      from heatmap_cells
      where (case when p_window = '7d' then cpue_7d when p_smooth then cpue_30d_smooth else cpue_30d end) is not null))
  );
$$;

create function public.api_zones(p_bbox float8[] default null, p_include_outline boolean default true)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  perform private.require_member();
  perform private.check_view('30d', p_bbox);
  return jsonb_build_object(
    'heatmap_version', private.current_version(),
    'zones', coalesce((
      select jsonb_agg(private.zone_entry(z, coalesce(p_include_outline, true)) order by z.name)
      from zones z
      where z.is_active
        and (p_bbox is null or (z.bbox[1] <= p_bbox[3] and z.bbox[3] >= p_bbox[1]
                                and z.bbox[2] <= p_bbox[4] and z.bbox[4] >= p_bbox[2]))
    ), '[]')
  );
end;
$$;

create function public.api_heatmap(
  p_window text default '30d',
  p_smooth boolean default false,
  p_bbox float8[] default null,
  p_x_min int default null,
  p_x_max int default null,
  p_y_min int default null,
  p_y_max int default null,
  p_include_empty boolean default false,
  p_include_zone_outline boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_window text := coalesce(p_window, '30d');
  v_smooth boolean := coalesce(p_smooth, false);
  v_cells jsonb;
  v_zone_ids uuid[];
begin
  perform private.require_member();
  perform private.check_view(v_window, p_bbox);
  select coalesce(jsonb_agg(private.cell_tuple(h, v_window, v_smooth) order by h.grid_id), '[]'),
         array_agg(distinct h.zone_id) filter (where h.zone_id is not null)
    into v_cells, v_zone_ids
  from heatmap_cells h join grid_cells g on g.grid_id = h.grid_id
  where (coalesce(p_include_empty, false) or h.is_relevant)
    and private.in_view(g, p_bbox, p_x_min, p_x_max, p_y_min, p_y_max);

  return jsonb_build_object(
    'heatmap_version', private.current_version(),
    'generated_at', (select max(created_at) from heatmap_versions),
    'window', v_window,
    'smooth', v_smooth,
    'scale', private.heatmap_scale(v_window, v_smooth),
    'columns', '["grid_id", "fatigue", "fatigue_level", "pressure", "cpue", "has_coral", "zone_id", "auto_flag"]'::jsonb,
    'cells', v_cells,
    'zones', coalesce((
      select jsonb_object_agg(z.id, private.zone_entry(z, coalesce(p_include_zone_outline, false)))
      from zones z where z.id = any(v_zone_ids) and z.is_active
    ), '{}')
  );
end;
$$;

create function public.api_heatmap_version()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_member();
  return coalesce(
    (select jsonb_build_object('heatmap_version', version, 'updated_at', created_at)
     from heatmap_versions order by version desc limit 1),
    jsonb_build_object('heatmap_version', 0, 'updated_at', null));
end;
$$;

create function public.api_heatmap_changes(
  p_since bigint,
  p_window text default '30d',
  p_smooth boolean default false,
  p_bbox float8[] default null,
  p_include_zone_outline boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_window text := coalesce(p_window, '30d');
  v_smooth boolean := coalesce(p_smooth, false);
  v_current bigint := private.current_version();
  v_cfg jsonb := private.config('heatmap');
  v_removed uuid[];
  v_changed uuid[];
begin
  perform private.require_member();
  perform private.check_view(v_window, p_bbox);
  if p_since is null or p_since < 0 or p_since > v_current then
    perform private.fail('VALIDATION_ERROR', 'since harus versi heatmap yang pernah diterima',
      jsonb_build_object('current_version', v_current));
  end if;
  if p_since < v_current - (v_cfg ->> 'changes_max_versions')::int
     or not exists (
       select 1 from heatmap_versions
       where version = p_since and created_at >= now() - make_interval(days => (v_cfg ->> 'changes_max_age_days')::int)) then
    if p_since < v_current then
      perform private.fail('FULL_RELOAD_REQUIRED', 'Data terlalu lama, muat ulang heatmap dan zona',
        jsonb_build_object('current_version', v_current));
    end if;
  end if;

  select coalesce(array_agg(distinct x), '{}') into v_removed
  from heatmap_versions v, unnest(v.removed_zone_ids) x where v.version > p_since;
  select coalesce(array_agg(distinct x), '{}') into v_changed
  from heatmap_versions v, unnest(v.changed_zone_ids) x where v.version > p_since;
  -- a changed zone that is no longer active is reported as removed
  v_removed := v_removed || array(select z.id from zones z where z.id = any(v_changed) and not z.is_active);
  v_changed := private.uuid_minus(v_changed, v_removed);

  return jsonb_build_object(
    'from_version', p_since,
    'to_version', v_current,
    'columns', '["grid_id", "fatigue", "fatigue_level", "pressure", "cpue", "has_coral", "zone_id", "auto_flag"]'::jsonb,
    'upserts', coalesce((
      select jsonb_agg(private.cell_tuple(h, v_window, v_smooth) order by h.grid_id)
      from heatmap_cells h join grid_cells g on g.grid_id = h.grid_id
      where h.updated_version > p_since and (h.is_relevant or h.was_relevant)
        and private.in_view(g, p_bbox, null, null, null, null)
    ), '[]'),
    'zones_upserted', coalesce((
      select jsonb_object_agg(z.id, private.zone_entry(z, coalesce(p_include_zone_outline, false)))
      from zones z where z.id = any(v_changed)
    ), '{}'),
    'zones_removed', to_jsonb(array(select distinct unnest(v_removed))),
    'scale', private.heatmap_scale(v_window, v_smooth)
  );
end;
$$;

-- Replaces the X-Heatmap-Version header (12.B.10): the app reports the version it holds after a sync
create function public.api_sync_seen(p_heatmap_version bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := private.require_member();
begin
  update profiles set
    last_heatmap_version = greatest(coalesce(last_heatmap_version, 0), coalesce(p_heatmap_version, 0)),
    last_seen_at = now()
  where id = v_uid
    -- at most one write per user per minute unless the version moved forward
    and (last_seen_at is null or last_seen_at < now() - interval '1 minute'
         or coalesce(last_heatmap_version, 0) < coalesce(p_heatmap_version, 0));
  return jsonb_build_object('heatmap_version', private.current_version());
end;
$$;

create function public.api_register_device(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := private.require_nelayan();
  v_errors jsonb;
  v_id uuid;
begin
  v_errors := jsonb_strip_nulls(jsonb_build_object(
    'fcm_token', private.bad_text(p -> 'fcm_token', 10, 4096, true),
    'platform', case when coalesce(p ->> 'platform', 'android') not in ('android', 'ios', 'web') then 'android, ios, atau web' end,
    'app_version', private.bad_text(p -> 'app_version', 1, 50, false)
  ));
  if v_errors <> '{}' then
    perform private.fail('VALIDATION_ERROR', 'Data perangkat tidak valid', jsonb_build_object('fields', v_errors));
  end if;
  -- the token moves to this user when another account used the same phone before
  insert into user_devices as d (user_id, fcm_token, platform, app_version, last_used_at)
  values (v_uid, p ->> 'fcm_token', coalesce(p ->> 'platform', 'android'), p ->> 'app_version', now())
  on conflict (fcm_token) do update set
    user_id = excluded.user_id, platform = excluded.platform, app_version = excluded.app_version, last_used_at = now()
  returning d.id into v_id;
  return jsonb_build_object('device_id', v_id, 'push_enabled', true);
end;
$$;

create function public.api_unregister_device(p_device_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := private.require_member();
begin
  delete from user_devices where id = p_device_id and user_id = v_uid;
  if not found then
    perform private.fail('DEVICE_NOT_FOUND', 'Perangkat tidak ditemukan');
  end if;
  return jsonb_build_object('device_id', p_device_id, 'deleted', true);
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Admin (konservatif) API, 12.A.5-12.A.9
-- ---------------------------------------------------------------------------------------------

create function public.api_admin_grid_detail(p_grid_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_grid grid_cells;
  v_cell heatmap_cells;
  v_zone zones;
begin
  perform private.require_konservatif();
  if coalesce(p_grid_id, '') !~ '^X\d{3}_Y\d{3}$' then
    perform private.fail('GRID_INVALID', 'Format grid_id harus X149_Y001');
  end if;
  select * into v_grid from grid_cells where grid_id = p_grid_id;
  if v_grid.grid_id is null then
    perform private.fail('GRID_NOT_FOUND', 'Grid tidak ditemukan');
  end if;
  select * into v_cell from heatmap_cells where grid_id = p_grid_id;
  select * into v_zone from zones where id = v_cell.zone_id and is_active;

  return jsonb_build_object(
    'grid_id', v_grid.grid_id, 'cell_id', v_grid.cell_id, 'grid_x', v_grid.grid_x, 'grid_y', v_grid.grid_y,
    'centroid', private.latlng(v_grid.geom),
    'is_sea', v_grid.is_sea, 'has_coral', v_grid.has_coral, 'coral_cover_pct', v_grid.coral_cover_pct,
    'heatmap_version', private.current_version(),
    'zone', case when v_zone.id is not null then private.zone_entry(v_zone, false) end,
    'auto_flag', v_cell.auto_flag, 'auto_flagged_at', v_cell.auto_flagged_at,
    'flag_dismissed_until', v_cell.flag_dismissed_until,
    'stats', jsonb_build_object(
      'fatigue_index', v_cell.fatigue, 'fatigue_level', v_cell.fatigue_level, 'pressure_index', v_cell.pressure_index,
      'trip_count_7d', v_cell.trip_count_7d, 'trip_count_30d', v_cell.trip_count_30d,
      'fishing_hours_30d', v_cell.fishing_hours_30d, 'catch_kg_30d', v_cell.catch_kg_30d,
      'cpue_30d', v_cell.cpue_30d, 'last_visited_at', v_cell.last_visited_at),
    'fatigue_trend_30d', coalesce((
      select jsonb_agg(jsonb_build_array(l.day, l.fatigue) order by l.day)
      from grid_daily_load l
      where l.grid_id = p_grid_id and l.fatigue is not null
        and l.day > (now() at time zone 'Asia/Jakarta')::date - 30
    ), '[]')
  );
end;
$$;

create function public.api_admin_preview_zone(p jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_ids text[];
  v_valid text[];
  v_invalid text[];
  v_union geometry;
begin
  perform private.require_konservatif();
  if private.bad_uuid(p -> 'exclude_zone_id', false) is not null then
    perform private.fail('VALIDATION_ERROR', 'exclude_zone_id harus UUID');
  end if;
  if coalesce(jsonb_typeof(p -> 'polygon'), 'null') <> 'null' then
    v_ids := private.zone_grid_input(p);
  else
    -- unknown ids are reported in invalid_grid_ids instead of failing, so the UI can mark them
    if coalesce(jsonb_typeof(p -> 'grid_ids'), '') <> 'array' then
      perform private.fail('VALIDATION_ERROR', 'Isi grid_ids (1 sampai 5000) atau polygon');
    end if;
    if jsonb_array_length(p -> 'grid_ids') not between 1 and 5000
       or exists (select 1 from jsonb_array_elements(p -> 'grid_ids') e where jsonb_typeof(e) <> 'string') then
      perform private.fail('VALIDATION_ERROR', 'grid_ids harus array 1 sampai 5000 grid_id');
    end if;
    select array_agg(distinct x) into v_ids from jsonb_array_elements_text(p -> 'grid_ids') x;
  end if;
  select coalesce(array_agg(x order by x) filter (where g.grid_id is not null), '{}'),
         coalesce(array_agg(x order by x) filter (where g.grid_id is null), '{}')
    into v_valid, v_invalid
  from unnest(v_ids) x left join grid_cells g on g.grid_id = x and g.is_sea;
  select st_multi(st_union(g.cell)) into v_union from grid_cells g where g.grid_id = any(v_valid);

  return jsonb_build_object(
    'valid_grid_ids', to_jsonb(v_valid),
    'invalid_grid_ids', to_jsonb(v_invalid),
    'conflicts', coalesce((
      select jsonb_agg(jsonb_build_object('grid_id', zg.grid_id, 'zone_id', z.id, 'zone_name', z.name) order by zg.grid_id)
      from zone_grids zg join zones z on z.id = zg.zone_id
      where zg.grid_id = any(v_valid) and zg.zone_id is distinct from (p ->> 'exclude_zone_id')::uuid
    ), '[]'),
    'aggregate', private.zone_aggregate(v_valid, null),
    'outline', st_asgeojson(v_union, 7)::jsonb,
    'is_contiguous', coalesce(st_numgeometries(v_union) = 1, false),
    'heatmap_version', private.current_version()
  );
end;
$$;

create function public.api_admin_create_zone(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := private.require_konservatif();
  v_errors jsonb;
  v_grids text[];
  v_take record;
  v_release record;
  v_zone zones;
  v_from timestamptz;
  v_until timestamptz;
  v_version bigint;
  v_queued int;
  v_on text := coalesce(p ->> 'on_conflict', 'reject');
begin
  if jsonb_typeof(p) is distinct from 'object' then
    perform private.fail('VALIDATION_ERROR', 'Body harus objek JSON');
  end if;
  v_errors := jsonb_strip_nulls(jsonb_build_object(
    'name', private.bad_text(p -> 'name', 3, 100, true),
    'status', case when coalesce(p ->> 'status', '') not in ('restricted', 'rehab') then 'restricted atau rehab' end,
    'rules', private.bad_rules(p -> 'rules'),
    'effective_from', private.bad_time(p -> 'effective_from', false),
    'effective_until', private.bad_time(p -> 'effective_until', false),
    'reason', private.bad_text(p -> 'reason', 3, 500, true),
    'note', private.bad_text(p -> 'note', 0, 2000, false),
    'on_conflict', case when v_on not in ('reject', 'move', 'skip') then 'reject, move, atau skip' end
  ));
  if v_errors <> '{}' then
    perform private.fail('VALIDATION_ERROR', 'Data zona tidak valid', jsonb_build_object('fields', v_errors));
  end if;
  if p ->> 'status' = 'restricted' and coalesce(jsonb_typeof(p -> 'rules'), 'null') = 'null' then
    perform private.fail('RULES_REQUIRED', 'Zona terbatas wajib punya aturan kuota');
  end if;
  v_from := coalesce((p ->> 'effective_from')::timestamptz, now());
  v_until := (p ->> 'effective_until')::timestamptz;
  if v_until is not null and v_until <= v_from then
    perform private.fail('VALIDATION_ERROR', 'Masa berlaku tidak valid',
      jsonb_build_object('fields', jsonb_build_object('effective_until', 'harus setelah effective_from')));
  end if;
  v_grids := private.zone_grid_input(p);
  if exists (select 1 from zones where is_active and lower(name) = lower(trim(p ->> 'name'))) then
    perform private.fail('ZONE_NAME_TAKEN', 'Nama zona sudah dipakai zona aktif lain');
  end if;

  select * into v_take from private.take_grids(null, v_grids, v_on);
  if cardinality(v_take.kept) = 0 then
    perform private.fail('ZONE_EMPTY', 'Semua grid dilewati karena konflik');
  end if;
  select * into v_release from private.release_grids(v_take.moved, p ->> 'reason', v_uid);

  insert into zones (name, status, max_catch_kg_per_period, max_trips_per_period, period, open_schedule,
                     effective_from, effective_until, reason, note, created_by)
  values (trim(p ->> 'name'), p ->> 'status', (p -> 'rules' ->> 'max_catch_kg_per_period')::numeric,
          (p -> 'rules' ->> 'max_trips_per_period')::numeric::int, p -> 'rules' ->> 'period',
          case when jsonb_typeof(p -> 'rules' -> 'open_schedule') = 'object' then p -> 'rules' -> 'open_schedule' end,
          v_from, v_until, trim(p ->> 'reason'), nullif(trim(p ->> 'note'), ''), v_uid)
  returning * into v_zone;
  insert into zone_grids (grid_id, zone_id) select unnest(v_take.kept), v_zone.id;
  perform private.zone_refresh_geometry(v_zone.id);
  perform private.add_history(v_zone.id, 'create', null, private.zone_snapshot(v_zone.id), trim(p ->> 'reason'), v_uid);
  update grid_stats set auto_flag = null, auto_flagged_at = null where grid_id = any(v_take.kept) and auto_flag is not null;

  v_version := private.publish(v_take.kept || v_take.moved, 'create_zone', trim(p ->> 'reason'),
    v_zone.id || v_release.changed, v_release.archived);
  v_queued := private.queue_push(v_zone.id, 'created', v_version);
  return private.zone_detail(v_zone.id) || jsonb_build_object(
    'skipped_grid_ids', to_jsonb(v_take.skipped), 'moved_grid_ids', to_jsonb(v_take.moved),
    'notification', jsonb_build_object('change', 'created', 'queued_fishers', v_queued));
exception when unique_violation then
  perform private.fail('ZONE_NAME_TAKEN', 'Nama zona sudah dipakai zona aktif lain');
end;
$$;

create function public.api_admin_list_zones(
  p_status text default null,
  p_q text default null,
  p_sort text default '-updated_at',
  p_page int default 1,
  p_limit int default 20,
  p_include_archived boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_page int := greatest(coalesce(p_page, 1), 1);
  v_limit int := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_sort text := coalesce(p_sort, '-updated_at');
begin
  perform private.require_konservatif();
  if p_status is not null and p_status not in ('restricted', 'rehab') then
    perform private.fail('VALIDATION_ERROR', 'status harus restricted atau rehab');
  end if;
  if v_sort not in ('name', '-fatigue_max', '-fatigue_avg', '-grid_count', '-updated_at', '-created_at') then
    perform private.fail('VALIDATION_ERROR', 'sort tidak dikenal');
  end if;
  return (
    with f as (
      select z.id, z.name, z.updated_at, z.created_at, a.n, a.favg, a.fmax
      from zones z
      cross join lateral (
        select count(*) as n, avg(h.fatigue) as favg, max(h.fatigue) as fmax
        from zone_grids zg left join heatmap_cells h on h.grid_id = zg.grid_id where zg.zone_id = z.id
      ) a
      where (coalesce(p_include_archived, false) or z.is_active)
        and (p_status is null or z.status = p_status)
        and (p_q is null or z.name ilike '%' || replace(replace(replace(p_q, '\', '\\'), '%', '\%'), '_', '\_') || '%')
    ), r as (
      select f.id, row_number() over (order by
        case when v_sort = 'name' then lower(f.name) end asc,
        case when v_sort = '-fatigue_max' then f.fmax end desc nulls last,
        case when v_sort = '-fatigue_avg' then f.favg end desc nulls last,
        case when v_sort = '-grid_count' then f.n end desc,
        case when v_sort = '-created_at' then f.created_at end desc,
        f.updated_at desc, f.id
      ) as rn
      from f
    )
    select jsonb_build_object(
      'data', coalesce((
        select jsonb_agg(private.zone_summary(z) order by r.rn)
        from r join zones z on z.id = r.id
        where r.rn > (v_page - 1) * v_limit and r.rn <= v_page * v_limit
      ), '[]'),
      'meta', jsonb_build_object('page', v_page, 'limit', v_limit, 'total', (select count(*) from f),
                                 'heatmap_version', private.current_version())
    )
  );
end;
$$;

create function public.api_admin_zone_detail(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_konservatif();
  if not exists (select 1 from zones where id = p_id) then
    perform private.fail('ZONE_NOT_FOUND', 'Zona tidak ditemukan');
  end if;
  return private.zone_detail(p_id);
end;
$$;

create function public.api_admin_edit_zone(p_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := private.require_konservatif();
  v_zone zones;
  v_errors jsonb;
  v_before jsonb;
  v_rules_changed boolean;
  v_window_changed boolean;
  v_from timestamptz;
  v_until timestamptz;
  v_version bigint;
  v_queued int := 0;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    perform private.fail('VALIDATION_ERROR', 'Body harus objek JSON');
  end if;
  if p ? 'status' or p ? 'grid_ids' then
    perform private.fail('VALIDATION_ERROR', 'Gunakan endpoint status atau grid untuk mengubah status dan anggota zona');
  end if;
  v_errors := jsonb_strip_nulls(jsonb_build_object(
    'name', private.bad_text(p -> 'name', 3, 100, false),
    'rules', private.bad_rules(p -> 'rules'),
    'effective_from', private.bad_time(p -> 'effective_from', false),
    'effective_until', private.bad_time(p -> 'effective_until', false),
    'note', private.bad_text(p -> 'note', 0, 2000, false),
    'reason', private.bad_text(p -> 'reason', 3, 500, true)
  ));
  if v_errors <> '{}' then
    perform private.fail('VALIDATION_ERROR', 'Data zona tidak valid', jsonb_build_object('fields', v_errors));
  end if;
  v_zone := private.lock_zone(p_id, p -> 'version');
  v_before := private.zone_snapshot(p_id);

  if v_zone.status = 'restricted' and p ? 'rules' and coalesce(jsonb_typeof(p -> 'rules'), 'null') = 'null' then
    perform private.fail('RULES_REQUIRED', 'Zona terbatas wajib punya aturan kuota');
  end if;
  if p ->> 'name' is not null and exists (
    select 1 from zones where is_active and id <> p_id and lower(name) = lower(trim(p ->> 'name'))) then
    perform private.fail('ZONE_NAME_TAKEN', 'Nama zona sudah dipakai zona aktif lain');
  end if;
  -- effective_from null keeps the current start; effective_until null clears the end
  v_from := coalesce((p ->> 'effective_from')::timestamptz, v_zone.effective_from);
  v_until := case when p ? 'effective_until' then (p ->> 'effective_until')::timestamptz else v_zone.effective_until end;
  if v_until is not null and v_until <= v_from then
    perform private.fail('VALIDATION_ERROR', 'Masa berlaku tidak valid',
      jsonb_build_object('fields', jsonb_build_object('effective_until', 'harus setelah effective_from')));
  end if;
  v_rules_changed := jsonb_typeof(p -> 'rules') = 'object';
  v_window_changed := v_from is distinct from v_zone.effective_from or v_until is distinct from v_zone.effective_until;

  if v_rules_changed and v_zone.period is distinct from p -> 'rules' ->> 'period' then
    -- AGENTS.md 12.A.7: changing the period resets the running quota
    delete from zone_quota_usage
    where zone_id = p_id
      and period_start in (private.period_start(v_zone.period, now()), private.period_start(p -> 'rules' ->> 'period', now()));
  end if;
  update zones set
    name = coalesce(trim(p ->> 'name'), name),
    note = case when p ? 'note' then nullif(trim(p ->> 'note'), '') else note end,
    effective_from = v_from,
    effective_until = v_until,
    max_catch_kg_per_period = case when v_rules_changed then (p -> 'rules' ->> 'max_catch_kg_per_period')::numeric else max_catch_kg_per_period end,
    max_trips_per_period = case when v_rules_changed then (p -> 'rules' ->> 'max_trips_per_period')::numeric::int else max_trips_per_period end,
    period = case when v_rules_changed then p -> 'rules' ->> 'period' else period end,
    open_schedule = case when v_rules_changed then
      case when jsonb_typeof(p -> 'rules' -> 'open_schedule') = 'object' then p -> 'rules' -> 'open_schedule' end
      else open_schedule end,
    version = version + 1,
    updated_at = now()
  where id = p_id;

  perform private.add_history(p_id, case when v_rules_changed then 'update_rules' else 'update_meta' end,
    v_before, private.zone_snapshot(p_id), trim(p ->> 'reason'), v_uid);
  v_version := private.publish('{}', 'edit_zone', trim(p ->> 'reason'), array[p_id], '{}');
  if v_rules_changed or v_window_changed then
    v_queued := private.queue_push(p_id, 'rules_changed', v_version);
  end if;
  return private.zone_detail(p_id) || case when v_rules_changed or v_window_changed
    then jsonb_build_object('notification', jsonb_build_object('change', 'rules_changed', 'queued_fishers', v_queued))
    else '{}' end;
exception when unique_violation then
  perform private.fail('ZONE_NAME_TAKEN', 'Nama zona sudah dipakai zona aktif lain');
end;
$$;

create function public.api_admin_edit_zone_grids(p_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := private.require_konservatif();
  v_add text[];
  v_remove text[];
  v_take record;
  v_release record;
  v_on text := coalesce(p ->> 'on_conflict', 'reject');
  v_version bigint;
  v_queued int := 0;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    perform private.fail('VALIDATION_ERROR', 'Body harus objek JSON');
  end if;
  if v_on not in ('reject', 'move', 'skip') or private.bad_text(p -> 'reason', 3, 500, true) is not null then
    perform private.fail('VALIDATION_ERROR', 'Data tidak valid', jsonb_build_object('fields', jsonb_strip_nulls(jsonb_build_object(
      'on_conflict', case when v_on not in ('reject', 'move', 'skip') then 'reject, move, atau skip' end,
      'reason', private.bad_text(p -> 'reason', 3, 500, true)))));
  end if;
  v_add := private.grid_ids(p -> 'add', 'add', 0, 5000);
  v_remove := private.grid_ids(p -> 'remove', 'remove', 0, 5000);
  -- polygons are merged with the explicit lists
  if coalesce(jsonb_typeof(p -> 'add_polygon'), 'null') <> 'null' then
    v_add := array(select distinct unnest(v_add || private.polygon_grids(p -> 'add_polygon', 'add_polygon')));
  end if;
  if coalesce(jsonb_typeof(p -> 'remove_polygon'), 'null') <> 'null' then
    v_remove := array(select distinct unnest(v_remove || private.polygon_grids(p -> 'remove_polygon', 'remove_polygon')));
  end if;
  if cardinality(v_add) + cardinality(v_remove) = 0 or v_add && v_remove then
    perform private.fail('VALIDATION_ERROR', 'Isi add atau remove, dan keduanya tidak boleh beririsan');
  end if;
  perform private.lock_zone(p_id, p -> 'version');

  v_add := array(select unnest(v_add) except select grid_id from zone_grids where zone_id = p_id);
  v_remove := array(select grid_id from zone_grids where zone_id = p_id and grid_id = any(v_remove));
  select * into v_take from private.take_grids(p_id, v_add, v_on);
  if not exists (
    select 1 from zone_grids where zone_id = p_id and not (grid_id = any(v_remove))
    union all select 1 from unnest(v_take.kept)
  ) then
    perform private.fail('ZONE_EMPTY', 'Zona tidak boleh kosong; ubah status ke normal untuk membubarkan');
  end if;

  select * into v_release from private.release_grids(v_take.moved, trim(p ->> 'reason'), v_uid);
  delete from zone_grids where zone_id = p_id and grid_id = any(v_remove);
  insert into zone_grids (grid_id, zone_id) select unnest(v_take.kept), p_id;
  update zones set version = version + 1, updated_at = now() where id = p_id;
  perform private.zone_refresh_geometry(p_id);
  if cardinality(v_take.kept) > 0 then
    perform private.add_history(p_id, 'add_grids', null, jsonb_build_object('grid_ids', v_take.kept), trim(p ->> 'reason'), v_uid);
  end if;
  if cardinality(v_remove) > 0 then
    perform private.add_history(p_id, 'remove_grids', jsonb_build_object('grid_ids', v_remove), null, trim(p ->> 'reason'), v_uid);
  end if;
  update grid_stats set auto_flag = null, auto_flagged_at = null where grid_id = any(v_take.kept) and auto_flag is not null;
  perform private.auto_flag(v_remove, false);  -- released grids are evaluated again

  v_version := private.publish(v_take.kept || v_take.moved || v_remove, 'edit_grids', trim(p ->> 'reason'),
    p_id || v_release.changed, v_release.archived);
  if cardinality(v_take.kept) > 0 then
    v_queued := private.queue_push(p_id, 'grids_added', v_version);
  end if;
  return private.zone_detail(p_id) || jsonb_build_object(
    'skipped_grid_ids', to_jsonb(v_take.skipped), 'moved_grid_ids', to_jsonb(v_take.moved))
    || case when cardinality(v_take.kept) > 0
       then jsonb_build_object('notification', jsonb_build_object('change', 'grids_added', 'queued_fishers', v_queued))
       else '{}' end;
end;
$$;

create function public.api_admin_edit_zone_status(p_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := private.require_konservatif();
  v_zone zones;
  v_status text := p ->> 'status';
  v_reason text := trim(p ->> 'reason');
  v_errors jsonb;
  v_before jsonb;
  v_released text[];
  v_flags record;
  v_version bigint;
  v_queued int;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    perform private.fail('VALIDATION_ERROR', 'Body harus objek JSON');
  end if;
  v_errors := jsonb_strip_nulls(jsonb_build_object(
    'status', case when coalesce(v_status, '') not in ('normal', 'restricted', 'rehab') then 'normal, restricted, atau rehab' end,
    'reason', private.bad_text(p -> 'reason', 3, 500, true),
    'rules', private.bad_rules(p -> 'rules'),
    'effective_until', private.bad_time(p -> 'effective_until', false)
  ));
  if v_errors <> '{}' then
    perform private.fail('VALIDATION_ERROR', 'Data tidak valid', jsonb_build_object('fields', v_errors));
  end if;
  v_zone := private.lock_zone(p_id, p -> 'version');
  if v_status = v_zone.status then
    perform private.fail('SAME_STATUS', 'Status baru sama dengan status sekarang');
  end if;

  if v_status = 'normal' then
    v_released := private.archive_zone(p_id, v_reason, v_uid);
    select * into v_flags from private.auto_flag(v_released, false);
    v_version := private.publish(v_released, 'edit_status', v_reason, '{}', array[p_id]);
    perform private.queue_push(p_id, 'dissolved', v_version);
    return jsonb_build_object(
      'id', p_id, 'status', 'normal', 'is_active', false,
      'archived_at', (select archived_at from zones where id = p_id),
      'released_grid_ids', to_jsonb(v_released), 'reflagged_grid_ids', to_jsonb(v_flags.added),
      'heatmap_version', v_version, 'version', v_zone.version + 1);
  end if;

  if v_status = 'restricted' and jsonb_typeof(p -> 'rules') is distinct from 'object'
     and v_zone.max_catch_kg_per_period is null and v_zone.max_trips_per_period is null then
    perform private.fail('RULES_REQUIRED', 'Zona terbatas wajib punya aturan kuota');
  end if;
  if p ? 'effective_until' and (p ->> 'effective_until')::timestamptz <= v_zone.effective_from then
    perform private.fail('VALIDATION_ERROR', 'effective_until harus setelah effective_from');
  end if;
  v_before := private.zone_snapshot(p_id);
  if v_status = 'restricted' then
    -- rehab -> restricted: the running quota starts from zero (12.A.7)
    delete from zone_quota_usage where zone_id = p_id;
  end if;
  update zones set
    status = v_status,
    max_catch_kg_per_period = case when jsonb_typeof(p -> 'rules') = 'object' then (p -> 'rules' ->> 'max_catch_kg_per_period')::numeric else max_catch_kg_per_period end,
    max_trips_per_period = case when jsonb_typeof(p -> 'rules') = 'object' then (p -> 'rules' ->> 'max_trips_per_period')::numeric::int else max_trips_per_period end,
    period = case when jsonb_typeof(p -> 'rules') = 'object' then p -> 'rules' ->> 'period' else period end,
    open_schedule = case when jsonb_typeof(p -> 'rules') = 'object' then
      case when jsonb_typeof(p -> 'rules' -> 'open_schedule') = 'object' then p -> 'rules' -> 'open_schedule' end
      else open_schedule end,
    effective_until = case when p ? 'effective_until' then (p ->> 'effective_until')::timestamptz else effective_until end,
    version = version + 1,
    updated_at = now()
  where id = p_id;
  perform private.add_history(p_id, 'update_status', v_before, private.zone_snapshot(p_id), v_reason, v_uid);
  v_version := private.publish(array(select grid_id from zone_grids where zone_id = p_id), 'edit_status', v_reason, array[p_id], '{}');
  v_queued := private.queue_push(p_id, 'status_changed', v_version);
  return private.zone_detail(p_id)
    || jsonb_build_object('notification', jsonb_build_object('change', 'status_changed', 'queued_fishers', v_queued));
end;
$$;

create function public.api_admin_zone_history(p_id uuid, p_action text default null, p_page int default 1, p_limit int default 20)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_page int := greatest(coalesce(p_page, 1), 1);
  v_limit int := least(greatest(coalesce(p_limit, 20), 1), 100);
begin
  perform private.require_konservatif();
  if not exists (select 1 from zones where id = p_id) then
    perform private.fail('ZONE_NOT_FOUND', 'Zona tidak ditemukan');
  end if;
  return jsonb_build_object(
    'data', coalesce((
      select jsonb_agg(private.history_json(h) order by h.changed_at desc, h.id desc)
      from (
        select * from zone_history
        where zone_id = p_id and (p_action is null or action = p_action)
        order by changed_at desc, id desc
        offset (v_page - 1) * v_limit limit v_limit
      ) h
    ), '[]'),
    'meta', jsonb_build_object('page', v_page, 'limit', v_limit, 'total', (
      select count(*) from zone_history where zone_id = p_id and (p_action is null or action = p_action)))
  );
end;
$$;

create function public.api_admin_list_flags(
  p_state text default 'active',
  p_has_coral boolean default null,
  p_bbox float8[] default null,
  p_sort text default '-fatigue',
  p_page int default 1,
  p_limit int default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_state text := coalesce(p_state, 'active');
  v_sort text := coalesce(p_sort, '-fatigue');
  v_page int := greatest(coalesce(p_page, 1), 1);
  v_limit int := least(greatest(coalesce(p_limit, 20), 1), 100);
begin
  perform private.require_konservatif();
  perform private.check_view('30d', p_bbox);
  if v_state not in ('active', 'dismissed') or v_sort not in ('-fatigue', '-flagged_at', 'flagged_at') then
    perform private.fail('VALIDATION_ERROR', 'state atau sort tidak dikenal');
  end if;
  return (
    with f as (
      select h.*, g.grid_x, g.grid_y, g.geom
      from heatmap_cells h join grid_cells g on g.grid_id = h.grid_id
      where case when v_state = 'active' then h.auto_flag is not null else h.flag_dismissed_until > now() end
        and (p_has_coral is null or h.has_coral = p_has_coral)
        and private.in_view(g, p_bbox, null, null, null, null)
    ), r as (
      select f.*, row_number() over (order by
        case when v_sort = '-fatigue' then f.fatigue end desc nulls last,
        case when v_sort = '-flagged_at' then f.auto_flagged_at end desc nulls last,
        case when v_sort = 'flagged_at' then f.auto_flagged_at end asc nulls last,
        f.grid_id) as rn
      from f
    )
    select jsonb_build_object(
      'data', coalesce((
        select jsonb_agg(jsonb_build_object(
          'grid_id', r.grid_id, 'grid_x', r.grid_x, 'grid_y', r.grid_y, 'centroid', private.latlng(r.geom),
          'has_coral', r.has_coral, 'fatigue_index', r.fatigue, 'fatigue_level', r.fatigue_level,
          'flagged_at', r.auto_flagged_at,
          'days_flagged', case when r.auto_flagged_at is not null then extract(day from now() - r.auto_flagged_at)::int end,
          'flagged_neighbor_ids', coalesce((
            select jsonb_agg(nb.grid_id order by nb.grid_id)
            from grid_cells nb join heatmap_cells nh on nh.grid_id = nb.grid_id
            where nb.grid_x between r.grid_x - 1 and r.grid_x + 1 and nb.grid_y between r.grid_y - 1 and r.grid_y + 1
              and nb.grid_id <> r.grid_id and nh.auto_flag is not null), '[]'),
          'dismissed_until', r.flag_dismissed_until,
          'dismiss_reason', (select d.reason from flag_dismissals d where d.grid_id = r.grid_id order by d.created_at desc limit 1)
        ) order by r.rn)
        from r where r.rn > (v_page - 1) * v_limit and r.rn <= v_page * v_limit
      ), '[]'),
      'meta', jsonb_build_object('page', v_page, 'limit', v_limit, 'total', (select count(*) from f))
    )
  );
end;
$$;

create function public.api_admin_dismiss_flags(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := private.require_konservatif();
  v_c jsonb := private.config('flag');
  v_grids text[];
  v_flagged text[];
  v_until timestamptz;
  v_version bigint;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    perform private.fail('VALIDATION_ERROR', 'Body harus objek JSON');
  end if;
  if private.bad_text(p -> 'reason', 3, 500, true) is not null or private.bad_time(p -> 'until', false) is not null then
    perform private.fail('VALIDATION_ERROR', 'Data tidak valid', jsonb_build_object('fields', jsonb_strip_nulls(jsonb_build_object(
      'reason', private.bad_text(p -> 'reason', 3, 500, true), 'until', private.bad_time(p -> 'until', false)))));
  end if;
  v_grids := private.grid_ids(p -> 'grid_ids', 'grid_ids', 1, 5000);
  v_until := coalesce((p ->> 'until')::timestamptz, now() + make_interval(days => (v_c ->> 'dismiss_default_days')::int));
  if v_until <= now() or v_until > now() + make_interval(days => (v_c ->> 'dismiss_max_days')::int) then
    perform private.fail('VALIDATION_ERROR', 'until harus di masa depan, maksimal 180 hari',
      jsonb_build_object('fields', jsonb_build_object('until', 'maksimal 180 hari dari sekarang')));
  end if;

  select coalesce(array_agg(grid_id order by grid_id), '{}') into v_flagged
  from grid_stats where grid_id = any(v_grids) and auto_flag is not null;
  insert into flag_dismissals (grid_id, dismissed_until, reason, dismissed_by)
  select x, v_until, trim(p ->> 'reason'), v_uid from unnest(v_flagged) x;
  update grid_stats set auto_flag = null, auto_flagged_at = null, flag_dismissed_until = v_until
  where grid_id = any(v_flagged);
  v_version := private.publish(v_flagged, 'dismiss_flag', trim(p ->> 'reason'));
  return jsonb_build_object(
    'dismissed_grid_ids', to_jsonb(v_flagged),
    'skipped_grid_ids', to_jsonb(array(select unnest(v_grids) except select unnest(v_flagged) order by 1)),
    'until', v_until,
    'heatmap_version', v_version);
end;
$$;

create function public.api_admin_refresh_heatmap(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := private.require_konservatif();
  v_scope text := p ->> 'scope';
  v_targets text[];
  v_job uuid;
  v_version bigint;
  v_changed int;
begin
  if jsonb_typeof(p) is distinct from 'object' or coalesce(v_scope, '') not in ('all', 'grids', 'zone')
     or private.bad_text(p -> 'reason', 3, 500, true) is not null then
    perform private.fail('VALIDATION_ERROR', 'scope (all, grids, zone) dan reason (3 sampai 500 karakter) wajib diisi');
  end if;
  if v_scope = 'grids' then
    v_targets := private.grid_ids(p -> 'grid_ids', 'grid_ids', 1, 5000);
  elsif v_scope = 'zone' then
    if private.bad_uuid(p -> 'zone_id', true) is not null
       or not exists (select 1 from zones where id = (p ->> 'zone_id')::uuid and is_active) then
      perform private.fail('ZONE_NOT_FOUND', 'Zona aktif tidak ditemukan');
    end if;
    v_targets := array(select grid_id from zone_grids where zone_id = (p ->> 'zone_id')::uuid);
  end if;

  begin
    insert into heatmap_refresh_jobs (scope, params, status, requested_by, started_at)
    values (v_scope, p, 'running', v_uid, now())
    returning id into v_job;
  exception when unique_violation then
    perform private.fail('REFRESH_IN_PROGRESS', 'Refresh penuh masih berjalan');
  end;

  -- shortcut: runs synchronously (31k cells take seconds); the job row keeps getRefreshStatus working
  perform private.recompute_stats(v_targets);
  perform private.auto_flag(v_targets, false);
  v_version := private.publish(v_targets, 'manual', trim(p ->> 'reason'));
  select changed_cells into v_changed from heatmap_versions where version = v_version;
  update heatmap_refresh_jobs set
    status = 'done', progress_pct = 100, result_version = v_version, changed_cells = v_changed, finished_at = now()
  where id = v_job;
  return jsonb_build_object('status', 'done', 'job_id', v_job, 'heatmap_version', v_version,
                            'changed_cells', v_changed, 'finished_at', now());
end;
$$;

create function public.api_admin_refresh_status(p_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_job heatmap_refresh_jobs;
begin
  perform private.require_konservatif();
  select * into v_job from heatmap_refresh_jobs where id = p_job_id;
  if v_job.id is null then
    perform private.fail('JOB_NOT_FOUND', 'Job tidak ditemukan');
  end if;
  return jsonb_build_object(
    'job_id', v_job.id, 'status', v_job.status, 'progress_pct', v_job.progress_pct,
    'heatmap_version', v_job.result_version, 'changed_cells', v_job.changed_cells, 'error', v_job.error,
    'started_at', v_job.started_at, 'finished_at', v_job.finished_at);
end;
$$;

create function public.api_admin_stats_summary(p_window text default '30d')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_window text := coalesce(p_window, '30d');
  v_since timestamptz;
  v_current bigint := private.current_version();
  v_active_days int := (private.config('sync') ->> 'active_days')::int;
begin
  perform private.require_konservatif();
  perform private.check_view(v_window, null);
  v_since := now() - case when v_window = '7d' then interval '7 days' else interval '30 days' end;
  return jsonb_build_object(
    'window', v_window,
    'zones', (
      select jsonb_build_object(
        'restricted', count(distinct z.id) filter (where z.status = 'restricted'),
        'rehab', count(distinct z.id) filter (where z.status = 'rehab'),
        'protected_area_km2', count(zg.grid_id) * 0.25)
      from zones z left join zone_grids zg on zg.zone_id = z.id where z.is_active),
    'flags', jsonb_build_object(
      'active', (select count(*) from heatmap_cells where auto_flag is not null),
      'dismissed', (select count(*) from heatmap_cells where flag_dismissed_until > now())),
    'trips', (
      select jsonb_build_object('count', count(*), 'catch_kg', coalesce(sum(catch_kg), 0),
                                'active_fishers', count(distinct user_id))
      from trips where departed_at >= v_since),
    'coral_fatigue_distribution', (
      select jsonb_build_object(
        'healthy', count(*) filter (where fatigue_level = 'healthy'),
        'tired', count(*) filter (where fatigue_level = 'tired'),
        'critical', count(*) filter (where fatigue_level = 'critical'))
      from heatmap_cells where has_coral),
    'top_fatigued_zones', coalesce((
      select jsonb_agg(x order by (x ->> 'fatigue_avg')::numeric desc nulls last)
      from (
        select jsonb_build_object('id', z.id, 'name', z.name, 'status', z.status, 'fatigue_avg', round(avg(h.fatigue), 3)) as x
        from zones z join zone_grids zg on zg.zone_id = z.id left join heatmap_cells h on h.grid_id = zg.grid_id
        where z.is_active group by z.id, z.name, z.status
        order by avg(h.fatigue) desc nulls last limit 5
      ) t), '[]'),
    'top_flagged_grids', coalesce((
      select jsonb_agg(jsonb_build_object('grid_id', grid_id, 'fatigue_index', fatigue) order by fatigue desc)
      from (select grid_id, fatigue from heatmap_cells where auto_flag is not null order by fatigue desc limit 5) t), '[]'),
    'violations', jsonb_build_object(
      'count', (select count(*) from trips where zone_violation and departed_at >= v_since),
      'by_zone', coalesce((
        select jsonb_agg(jsonb_build_object('zone_id', zone_id, 'name', name, 'count', n) order by n desc)
        from (
          select f.zone_id_at_time as zone_id, max(f.zone_name_at_time) as name, count(distinct f.trip_id) as n
          from fishing_points f join trips t on t.id = f.trip_id
          where f.zone_status_at_time = 'rehab' and t.departed_at >= v_since
          group by f.zone_id_at_time
        ) v), '[]')),
    'sync_coverage', (
      select jsonb_build_object(
        'active_fishers_7d', count(*),
        'on_latest_version', count(*) filter (where p.last_heatmap_version >= v_current),
        'on_latest_pct', round(100.0 * count(*) filter (where p.last_heatmap_version >= v_current) / nullif(count(*), 0), 1),
        'behind', jsonb_build_array(
          jsonb_build_object('bucket', '1-5 versi', 'count', count(*) filter (
            where v_current - coalesce(p.last_heatmap_version, 0) between 1 and 5)),
          jsonb_build_object('bucket', '> 5 versi', 'count', count(*) filter (
            where v_current - coalesce(p.last_heatmap_version, 0) > 5))),
        'push_enabled_fishers', count(*) filter (where exists (select 1 from user_devices d where d.user_id = p.id)))
      from profiles p
      where p.role = 'nelayan' and p.last_seen_at >= now() - make_interval(days => v_active_days)),
    'heatmap_version', v_current,
    'generated_at', now()
  );
end;
$$;

-- System job (12.A.8): service_role only (and pg_cron, which runs as postgres)
create function public.api_internal_auto_flag(p_grid_ids text[] default null, p_dry_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_flags record;
  v_version bigint := private.current_version();
begin
  select * into v_flags from private.auto_flag(p_grid_ids, coalesce(p_dry_run, false));
  if not coalesce(p_dry_run, false) and cardinality(v_flags.added) + cardinality(v_flags.removed) > 0 then
    v_version := private.publish(v_flags.added || v_flags.removed, 'auto_flag');
  end if;
  return jsonb_build_object(
    'run_id', gen_random_uuid(), 'evaluated', v_flags.evaluated,
    'flag_added', to_jsonb(v_flags.added), 'flag_removed', to_jsonb(v_flags.removed),
    'heatmap_version', v_version, 'finished_at', now());
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Nelayan RPCs moved to the zone model (bodies copied from 20261016100500_nelayan; changes: rehab instead of closed,
-- zone_rules from the quota, after_trip publishes the heatmap)
-- ---------------------------------------------------------------------------------------------

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
      select 1 from fishing_points where trip_id = v_trip.id and zone_status_at_time = 'rehab'
    )
  where id = v_trip.id;

  if p ->> 'source' = 'onboarding' then
    update profiles set onboarded = true where id = v_uid;
  end if;
  perform private.after_trip(v_trip.id);
  return private.post_trip_result(v_trip.id, false);
end;
$$;

create or replace function public.api_rec_context(p_for_date date default null, p_refresh boolean default false)
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
    -- predicted cells in range of the home port, outside rehab zones and exhausted quotas at departure
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
        and not (zz.z ->> 'closed')::boolean
        and not exists (select 1 from heatmap_cells hc where hc.grid_id = g.grid_id and hc.fatigue_level = 'critical')
    ), '[]'),
    'habitual', (
      select jsonb_build_object(
        'grid_id', g.grid_id,
        'lat', round(st_y(g.geom::geometry)::numeric, 6), 'lng', round(st_x(g.geom::geometry)::numeric, 6),
        'dist_m', round(st_distance(g.geom, v_boat.home_port)::numeric),
        'visits', h.visits, 'zone', private.zone_json(g.geom, v_window),
        'critical', exists (select 1 from heatmap_cells hc where hc.grid_id = g.grid_id and hc.fatigue_level = 'critical')
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

create or replace function public.api_save_recommendations(p jsonb)
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
    if exists (select 1 from heatmap_cells hc where hc.grid_id = v_item ->> 'grid_id' and hc.fatigue_level = 'critical') then
      perform private.fail('VALIDATION_ERROR', 'Rekomendasi tidak boleh di grid dengan kelelahan kritis');
    end if;
    if (v_zone ->> 'closed')::boolean then
      perform private.fail('VALIDATION_ERROR', 'Rekomendasi tidak boleh di zona tertutup');
    end if;

    insert into recommendations (
      set_id, user_id, type, grid_id, point, zone, zone_rules, distance_from_port_km,
      predicted_fuel_liters, fuel_efficiency_pct, predicted_catch_kg, predicted_catch_min, predicted_catch_max,
      confidence, reason, weather_summary, area_condition
    ) values (
      v_set, v_uid, v_item ->> 'type', v_item ->> 'grid_id', v_geom,
      jsonb_build_object('id', v_zone -> 'id', 'name', v_zone -> 'name', 'status', v_zone -> 'status'),
      case when v_zone ->> 'status' = 'restricted' then jsonb_build_object(
        'quota_remaining_kg', v_zone -> 'quota_remaining_kg', 'open_schedule', v_zone -> 'open_schedule') end,
      round((st_distance(v_geom, v_boat.home_port) / 1000)::numeric, 2),
      (v_item ->> 'predicted_fuel_liters')::numeric, (v_item ->> 'fuel_efficiency_pct')::numeric,
      (v_item ->> 'predicted_catch_kg')::numeric, (v_item ->> 'predicted_catch_min')::numeric,
      (v_item ->> 'predicted_catch_max')::numeric,
      coalesce((v_item ->> 'confidence')::numeric, 0.3), coalesce(v_item ->> 'reason', ''),
      v_item -> 'weather_summary',
      coalesce((select case when hc.fatigue_level = 'tired' then 'tired' end
                from heatmap_cells hc where hc.grid_id = v_item ->> 'grid_id'), 'healthy')
    );
  end loop;
  return private.set_json(v_set);
exception when unique_violation then
  perform private.fail('VALIDATION_ERROR', 'Satu tipe rekomendasi hanya boleh sekali');
end;
$$;

alter table public.recommendations
  add column area_condition text not null default 'healthy' check (area_condition in ('healthy', 'tired'));

create or replace function private.rec_json(r public.recommendations, s public.recommendation_sets)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id, 'type', r.type, 'grid_id', r.grid_id, 'point', private.latlng(r.point),
    'zone', r.zone, 'zone_rules', r.zone_rules,
    'area_condition', r.area_condition,
    'predicted_fuel_liters', r.predicted_fuel_liters, 'fuel_efficiency_pct', r.fuel_efficiency_pct,
    'predicted_catch_kg', r.predicted_catch_kg,
    'predicted_catch_range_kg', case when r.predicted_catch_kg is not null
      then jsonb_build_array(r.predicted_catch_min, r.predicted_catch_max) end,
    'departure_time', to_char(s.departure_time, 'HH24:MI'), 'return_time', to_char(s.return_time, 'HH24:MI'),
    'for_date', s.for_date, 'distance_from_port_km', r.distance_from_port_km,
    'weather_summary', r.weather_summary, 'confidence', r.confidence, 'reason', r.reason
  );
$$;

-- ---------------------------------------------------------------------------------------------
-- Grants, first snapshot, schedule
-- ---------------------------------------------------------------------------------------------

revoke execute on all functions in schema private from public;
revoke execute on function
  public.api_grid_meta(), public.api_sea_mask(), public.api_zones(float8[], boolean),
  public.api_heatmap(text, boolean, float8[], int, int, int, int, boolean, boolean),
  public.api_heatmap_version(), public.api_heatmap_changes(bigint, text, boolean, float8[], boolean),
  public.api_sync_seen(bigint), public.api_register_device(jsonb), public.api_unregister_device(uuid),
  public.api_admin_grid_detail(text), public.api_admin_preview_zone(jsonb), public.api_admin_create_zone(jsonb),
  public.api_admin_list_zones(text, text, text, int, int, boolean), public.api_admin_zone_detail(uuid),
  public.api_admin_edit_zone(uuid, jsonb), public.api_admin_edit_zone_grids(uuid, jsonb),
  public.api_admin_edit_zone_status(uuid, jsonb), public.api_admin_zone_history(uuid, text, int, int),
  public.api_admin_list_flags(text, boolean, float8[], text, int, int), public.api_admin_dismiss_flags(jsonb),
  public.api_admin_refresh_heatmap(jsonb), public.api_admin_refresh_status(uuid),
  public.api_admin_stats_summary(text), public.api_internal_auto_flag(text[], boolean),
  public.closed_zone_outlines(timestamptz, timestamptz)
from public, anon, authenticated;
grant execute on function
  public.api_grid_meta(), public.api_sea_mask(), public.api_zones(float8[], boolean),
  public.api_heatmap(text, boolean, float8[], int, int, int, int, boolean, boolean),
  public.api_heatmap_version(), public.api_heatmap_changes(bigint, text, boolean, float8[], boolean),
  public.api_sync_seen(bigint), public.api_register_device(jsonb), public.api_unregister_device(uuid),
  public.api_admin_grid_detail(text), public.api_admin_preview_zone(jsonb), public.api_admin_create_zone(jsonb),
  public.api_admin_list_zones(text, text, text, int, int, boolean), public.api_admin_zone_detail(uuid),
  public.api_admin_edit_zone(uuid, jsonb), public.api_admin_edit_zone_grids(uuid, jsonb),
  public.api_admin_edit_zone_status(uuid, jsonb), public.api_admin_zone_history(uuid, text, int, int),
  public.api_admin_list_flags(text, boolean, float8[], text, int, int), public.api_admin_dismiss_flags(jsonb),
  public.api_admin_refresh_heatmap(jsonb), public.api_admin_refresh_status(uuid),
  public.api_admin_stats_summary(text), public.closed_zone_outlines(timestamptz, timestamptz)
to authenticated;
grant execute on function public.api_internal_auto_flag(text[], boolean) to service_role;

select private.publish(null, 'init', 'migration 20261016100600_zones_heatmap');

select cron.schedule('heatmap-daily', '10 17 * * *', 'select private.daily_refresh()');  -- 00:10 WIB
