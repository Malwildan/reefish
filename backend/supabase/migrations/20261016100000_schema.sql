create extension if not exists postgis with schema extensions;

-- Roles: nelayan (default) and konservatif (set manually via SQL editor)
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null default 'nelayan' check (role in ('nelayan', 'konservatif')),
  full_name text
);

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- role is never taken from signup metadata, so users cannot self-promote
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Legend from data/geojson/metadata.json
create table public.cluster_levels (
  level smallint primary key,
  label text not null,
  color text not null
);

insert into public.cluster_levels (level, label, color) values
  (1, 'Sangat Rendah', '#440154'),
  (2, 'Rendah', '#3b528b'),
  (3, 'Sedang', '#21918c'),
  (4, 'Tinggi', '#5ec962'),
  (5, 'Sangat Tinggi', '#fde725');

-- Grid is identical every period, so geometry is stored once
create table public.grid_cells (
  grid_id text primary key,
  geom extensions.geography(Point, 4326) not null
);

create index grid_cells_geom_idx on public.grid_cells using gist (geom);

create table public.cluster_predictions (
  grid_id text not null references public.grid_cells (grid_id),
  period text not null,
  cluster_id int not null,
  level smallint not null references public.cluster_levels (level),
  potential_score real not null,
  sst real,
  chlor_a real,
  depth_m real,
  imputed boolean not null default false,
  primary key (grid_id, period)
);

create index cluster_predictions_period_level_idx on public.cluster_predictions (period, level);

create table public.zones (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  status text not null check (status in ('open', 'limited', 'closed')),
  max_catch_kg numeric check (max_catch_kg >= 0),
  notes text,
  valid_from date not null default current_date,
  valid_to date,
  geom extensions.geography(Polygon, 4326) not null,
  -- REST returns geography as hex WKB; this gives the frontend GeoJSON directly
  geojson jsonb generated always as (extensions.st_asgeojson(geom)::jsonb) stored,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from)
);

create index zones_geom_idx on public.zones using gist (geom);
