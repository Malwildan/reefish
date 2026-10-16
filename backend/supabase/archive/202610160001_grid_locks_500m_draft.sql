begin;

do $migration$
declare
  v_postgis_schema text;
begin
  select n.nspname
    into v_postgis_schema
    from pg_catalog.pg_extension e
    join pg_catalog.pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'postgis';

  if v_postgis_schema is null then
    raise exception 'PostGIS must be installed before applying the grid-lock migration';
  end if;

  execute pg_catalog.format(
    'create function public.grid_lock_parse_axis(p_axis text) returns bigint
     language plpgsql immutable strict
     set search_path = pg_catalog
     as $fn$
     declare v_digits text;
     begin
       if p_axis !~ ''^[rc](p(0|[1-9][0-9]*)|n([1-9][0-9]*))$'' then
         return null;
       end if;
       v_digits := pg_catalog.substr(p_axis, 3);
       if pg_catalog.substr(p_axis, 2, 1) = ''n'' then
         return -v_digits::bigint;
       end if;
       return v_digits::bigint;
     exception when numeric_value_out_of_range then
       return null;
     end
     $fn$'
  );

  -- Discover and qualify PostGIS so installation outside public is supported.
  execute pg_catalog.format(
    'create or replace function public.grid_lock_cell_intersects_area(p_area_id text, p_cell_id text)
     returns boolean language plpgsql stable security definer
     set search_path = pg_catalog, auth, %I
     as $fn$
     declare
       v_bounds jsonb;
       v_row bigint;
       v_col bigint;
       v_west double precision;
       v_south double precision;
       v_east double precision;
       v_north double precision;
       v_intersects boolean;
     begin
       if p_cell_id !~ ''^tp-id-utm49s-500m:v2:r(p(0|[1-9][0-9]*)|n([1-9][0-9]*)):c(p(0|[1-9][0-9]*)|n([1-9][0-9]*))$'' then
         return false;
       end if;
       v_row := public.grid_lock_parse_axis(pg_catalog.split_part(p_cell_id, '':'', 3));
       v_col := public.grid_lock_parse_axis(pg_catalog.split_part(p_cell_id, '':'', 4));
       if v_row is null or v_col is null then return false; end if;
       v_west := (v_col::numeric * 500)::double precision;
       v_south := (v_row::numeric * 500)::double precision;
       v_east := v_west + 500;
       v_north := v_south + 500;
       if v_west < 0 or v_east > 1000000 or v_south < 0 or v_north > 10000000 then
         return false;
       end if;
       select a.bounds into v_bounds from public.map_areas a where a.id = p_area_id;
       if not found then return false; end if;
       execute pg_catalog.format(
         ''select %%I.ST_Intersects(
             %%I.ST_Transform(%%I.ST_MakeEnvelope($1, $2, $3, $4, 32749), 4326),
             %%I.ST_MakeEnvelope(($5 ->> 0)::double precision, ($5 ->> 1)::double precision,
                                ($5 ->> 2)::double precision, ($5 ->> 3)::double precision, 4326))'',
         %L, %L, %L, %L
       ) into v_intersects using v_west, v_south, v_east, v_north, v_bounds;
       return coalesce(v_intersects, false);
     end
     $fn$',
    v_postgis_schema,
    v_postgis_schema, v_postgis_schema, v_postgis_schema, v_postgis_schema
  );
end
$migration$;

create table public.map_areas (
  id text primary key,
  bounds jsonb not null check (
    pg_catalog.jsonb_typeof(bounds) = 'array'
    and pg_catalog.jsonb_array_length(bounds) = 4
    and pg_catalog.jsonb_typeof(bounds -> 0) = 'number'
    and pg_catalog.jsonb_typeof(bounds -> 1) = 'number'
    and pg_catalog.jsonb_typeof(bounds -> 2) = 'number'
    and pg_catalog.jsonb_typeof(bounds -> 3) = 'number'
  ),
  version bigint not null default 1 check (version > 0)
);

insert into public.map_areas (id, bounds, version)
values ('east-java-pilot', '[112.25, -9.15, 113.10, -8.35]'::jsonb, 1);

create table public.map_area_admins (
  area_id text not null references public.map_areas(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (area_id, user_id)
);

create table public.grid_locks (
  area_id text not null references public.map_areas(id) on delete cascade,
  cell_id text not null check (
    cell_id ~ '^tp-id-utm49s-500m:v2:r(p(0|[1-9][0-9]*)|n([1-9][0-9]*)):c(p(0|[1-9][0-9]*)|n([1-9][0-9]*))$'
  ),
  reason text not null check (pg_catalog.length(pg_catalog.btrim(reason)) > 0),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (area_id, cell_id)
);

create table public.grid_lock_audit (
  id bigint generated always as identity primary key,
  area_id text not null references public.map_areas(id),
  cell_id text not null,
  action text not null check (action in ('locked', 'reason_changed', 'unlocked')),
  reason text,
  actor_user_id uuid not null references auth.users(id),
  changed_at timestamptz not null default pg_catalog.now()
);

create index grid_lock_audit_area_changed_at_idx
  on public.grid_lock_audit (area_id, changed_at desc);

alter table public.map_areas enable row level security;
alter table public.map_area_admins enable row level security;
alter table public.grid_locks enable row level security;
alter table public.grid_lock_audit enable row level security;

create policy map_areas_read_authenticated on public.map_areas
  for select to authenticated using (true);

revoke all on table public.map_areas, public.map_area_admins,
  public.grid_locks, public.grid_lock_audit from public, anon, authenticated;
grant select on table public.map_areas to authenticated;
revoke all on sequence public.grid_lock_audit_id_seq from public, anon, authenticated;

create function public.get_grid_lock_snapshot(p_area_id text default 'east-java-pilot')
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, auth
as $function$
declare
  v_version bigint;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_locks jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  select a.version into v_version
    from public.map_areas a
   where a.id = p_area_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Unknown map area';
  end if;

  select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object('cell_id', l.cell_id, 'reason', l.reason)
        order by l.cell_id
      ), '[]'::jsonb
    )
    into v_locks
    from public.grid_locks l
   where l.area_id = p_area_id;

  return pg_catalog.jsonb_build_object(
    'version', v_version::text,
    'fetched_at', pg_catalog.to_char(pg_catalog.timezone('UTC', v_now), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'expires_at', pg_catalog.to_char(pg_catalog.timezone('UTC', v_now + interval '5 minutes'), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'is_demo', false,
    'locks', v_locks
  );
end
$function$;

create function public.set_grid_lock(
  p_area_id text,
  p_cell_id text,
  p_locked boolean,
  p_reason text,
  p_expected_version text
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_version bigint;
  v_previous_reason text;
  v_action text;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_area_id is null or p_cell_id is null or p_locked is null then
    raise exception using errcode = '22023', message = 'Area, cell, and lock state are required';
  end if;
  if p_cell_id !~ '^tp-id-utm49s-500m:v2:r(p(0|[1-9][0-9]*)|n([1-9][0-9]*)):c(p(0|[1-9][0-9]*)|n([1-9][0-9]*))$'
     or public.grid_lock_parse_axis(pg_catalog.split_part(p_cell_id, ':', 3)) is null
     or public.grid_lock_parse_axis(pg_catalog.split_part(p_cell_id, ':', 4)) is null then
    raise exception using errcode = '22023', message = 'Malformed or non-canonical cell identifier';
  end if;
  if p_locked and (p_reason is null or pg_catalog.length(pg_catalog.btrim(p_reason)) = 0) then
    raise exception using errcode = '22023', message = 'A reason is required when locking a cell';
  end if;

  select a.version into v_version
    from public.map_areas a
   where a.id = p_area_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Unknown map area';
  end if;

  if not exists (
    select 1 from public.map_area_admins m
     where m.area_id = p_area_id and m.user_id = v_actor
  ) then
    raise exception using errcode = '42501', message = 'Area admin membership required';
  end if;

  if p_expected_version is null or p_expected_version !~ '^[1-9][0-9]*$'
     or p_expected_version::numeric <> v_version then
    raise exception using errcode = '40001', message = 'Stale map area version; refresh the lock snapshot';
  end if;

  if not public.grid_lock_cell_intersects_area(p_area_id, p_cell_id) then
    raise exception using errcode = '22023', message = 'Cell is outside the map area';
  end if;

  select l.reason into v_previous_reason
    from public.grid_locks l
   where l.area_id = p_area_id and l.cell_id = p_cell_id;

  if p_locked then
    if v_previous_reason is not null and v_previous_reason = pg_catalog.btrim(p_reason) then
      return v_version::text;
    end if;
    v_action := case when v_previous_reason is null then 'locked' else 'reason_changed' end;
    insert into public.grid_locks (area_id, cell_id, reason, updated_by, updated_at)
    values (p_area_id, p_cell_id, pg_catalog.btrim(p_reason), v_actor, pg_catalog.clock_timestamp())
    on conflict (area_id, cell_id) do update
      set reason = excluded.reason, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  else
    if v_previous_reason is null then
      return v_version::text;
    end if;
    v_action := 'unlocked';
    delete from public.grid_locks where area_id = p_area_id and cell_id = p_cell_id;
  end if;

  update public.map_areas set version = version + 1 where id = p_area_id returning version into v_version;
  insert into public.grid_lock_audit (area_id, cell_id, action, reason, actor_user_id)
  values (p_area_id, p_cell_id, v_action, nullif(pg_catalog.btrim(p_reason), ''), v_actor);

  return v_version::text;
end
$function$;

create function public.validate_fishing_grid_selection(p_area_id text, p_cell_id text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, auth
as $function$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_area_id is null or p_cell_id is null
     or p_cell_id !~ '^tp-id-utm49s-500m:v2:r(p(0|[1-9][0-9]*)|n([1-9][0-9]*)):c(p(0|[1-9][0-9]*)|n([1-9][0-9]*))$'
     or public.grid_lock_parse_axis(pg_catalog.split_part(p_cell_id, ':', 3)) is null
     or public.grid_lock_parse_axis(pg_catalog.split_part(p_cell_id, ':', 4)) is null then
    raise exception using errcode = '22023', message = 'Malformed or non-canonical cell identifier';
  end if;

  perform 1
    from public.map_areas a
   where a.id = p_area_id
   for share;
  if not found then
    raise exception using errcode = 'P0002', message = 'Unknown map area';
  end if;
  if not public.grid_lock_cell_intersects_area(p_area_id, p_cell_id) then
    raise exception using errcode = '22023', message = 'Cell is outside the map area';
  end if;
  if exists (
    select 1 from public.grid_locks l
     where l.area_id = p_area_id and l.cell_id = p_cell_id
  ) then
    raise exception using errcode = '23514', message = 'Fishing location is administratively locked';
  end if;
  return true;
end
$function$;

revoke all on function public.grid_lock_parse_axis(text) from public, anon, authenticated;
revoke all on function public.grid_lock_cell_intersects_area(text, text) from public, anon, authenticated;
revoke all on function public.get_grid_lock_snapshot(text) from public, anon, authenticated;
revoke all on function public.set_grid_lock(text, text, boolean, text, text) from public, anon, authenticated;
revoke all on function public.validate_fishing_grid_selection(text, text) from public, anon, authenticated;
grant execute on function public.get_grid_lock_snapshot(text) to authenticated;
grant execute on function public.set_grid_lock(text, text, boolean, text, text) to authenticated;
grant execute on function public.validate_fishing_grid_selection(text, text) to authenticated;

commit;
