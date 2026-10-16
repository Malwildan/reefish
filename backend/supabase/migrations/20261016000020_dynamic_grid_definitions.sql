-- Install PostGIS into Supabase's dedicated extension schema when absent.
create schema if not exists extensions;
create schema if not exists reefish_private;
revoke all on schema reefish_private from public, anon, authenticated;
grant usage on schema reefish_private to authenticated;
create extension if not exists postgis with schema extensions;

do $migration$
declare
  v_postgis_schema text;
begin
  select n.nspname into v_postgis_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'postgis';
  if v_postgis_schema is null then
    raise exception 'PostGIS installation failed';
  end if;
  if v_postgis_schema <> 'extensions' then
    raise exception 'PostGIS is installed in schema %, but this migration requires schema extensions; relocate PostGIS before applying', v_postgis_schema;
  end if;
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
    and (bounds ->> 0)::numeric < (bounds ->> 2)::numeric
    and (bounds ->> 1)::numeric < (bounds ->> 3)::numeric
    and (bounds ->> 0)::numeric >= -180 and (bounds ->> 2)::numeric <= 180
    and (bounds ->> 1)::numeric >= -90 and (bounds ->> 3)::numeric <= 90
  ),
  version bigint not null default 1 check (version > 0),
  active_grid_id text,
  created_at timestamptz not null default pg_catalog.now()
);

create table public.map_area_admins (
  area_id text not null references public.map_areas(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (area_id, user_id)
);

create table public.grid_definitions (
  area_id text not null references public.map_areas(id) on delete restrict,
  id text not null,
  cell_size_m integer not null check (
    cell_size_m between 100 and 5000 and cell_size_m % 50 = 0
  ),
  srid integer not null check (srid = 32749),
  origin_x_m double precision not null,
  origin_y_m double precision not null,
  bounds jsonb not null,
  state text not null default 'draft' check (state in ('draft', 'published', 'archived')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  published_at timestamptz,
  archived_at timestamptz,
  primary key (area_id, id),
  check (pg_catalog.jsonb_typeof(bounds) = 'array' and pg_catalog.jsonb_array_length(bounds) = 4)
);

alter table public.map_areas add constraint map_areas_active_grid_fk
  foreign key (id, active_grid_id) references public.grid_definitions(area_id, id)
  deferrable initially deferred;

create index grid_definitions_area_state_idx
  on public.grid_definitions (area_id, state, cell_size_m);

-- Restrictions retain their original square and source identity. Publishing a
-- different grid derives visible cell locks from these polygons, never from IDs.
create table public.grid_restrictions (
  id bigint generated always as identity primary key,
  area_id text not null references public.map_areas(id) on delete restrict,
  source_grid_id text not null,
  source_cell_id text not null,
  reason text not null check (pg_catalog.length(pg_catalog.btrim(reason)) between 1 and 500),
  geom extensions.geometry(Polygon, 32749) not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default pg_catalog.now(),
  removed_by uuid references auth.users(id),
  removed_at timestamptz,
  removal_note text,
  foreign key (area_id, source_grid_id)
    references public.grid_definitions(area_id, id) on delete restrict,
  check ((removed_at is null) = (removed_by is null))
);

create unique index grid_restrictions_active_source_uq
  on public.grid_restrictions (area_id, source_grid_id, source_cell_id)
  where removed_at is null;
create index grid_restrictions_active_area_idx
  on public.grid_restrictions (area_id, id) where removed_at is null;
create index grid_restrictions_geom_gist
  on public.grid_restrictions using gist (geom) where removed_at is null;

create table public.grid_admin_audit (
  id bigint generated always as identity primary key,
  area_id text not null references public.map_areas(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id),
  action text not null check (action in (
    'grid_created', 'grid_published', 'grid_archived', 'restriction_added',
    'restriction_reason_changed', 'restriction_removed'
  )),
  grid_id text,
  cell_id text,
  restriction_id bigint references public.grid_restrictions(id) on delete restrict,
  detail jsonb not null default '{}'::jsonb,
  changed_at timestamptz not null default pg_catalog.now()
);
create index grid_admin_audit_area_changed_idx
  on public.grid_admin_audit (area_id, changed_at desc);

create function reefish_private.grid_definitions_immutable()
returns trigger language plpgsql set search_path = '' as $function$
begin
  if new.area_id is distinct from old.area_id
     or new.id is distinct from old.id
     or new.cell_size_m is distinct from old.cell_size_m
     or new.srid is distinct from old.srid
     or new.origin_x_m is distinct from old.origin_x_m
     or new.origin_y_m is distinct from old.origin_y_m
     or new.bounds is distinct from old.bounds
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception using errcode = '55000', message = 'Grid definition geometry and identity are immutable';
  end if;
  if not ((old.state = 'draft' and new.state = 'published')
       or (old.state = 'published' and new.state = 'archived')) then
    raise exception using errcode = '55000', message = 'Grid state may only move draft to published or published to archived';
  end if;
  if old.state = 'draft' and (new.published_at is null or new.archived_at is not null) then
    raise exception using errcode = '55000', message = 'Publishing must set published_at only';
  end if;
  if old.state = 'published' and (new.published_at is distinct from old.published_at or new.archived_at is null) then
    raise exception using errcode = '55000', message = 'Archiving must preserve published_at and set archived_at';
  end if;
  return new;
end
$function$;
create trigger grid_definitions_immutable_trg
before update on public.grid_definitions
for each row execute function reefish_private.grid_definitions_immutable();

create function reefish_private.grid_parse_axis(p_axis text)
returns bigint language plpgsql immutable strict set search_path = '' as $function$
declare v_digits text;
begin
  if p_axis !~ '^(p(0|[1-9][0-9]*)|n([1-9][0-9]*))$' then return null; end if;
  v_digits := pg_catalog.substr(p_axis, 2);
  if pg_catalog.substr(p_axis, 1, 1) = 'n' then return -v_digits::bigint; end if;
  return v_digits::bigint;
exception when numeric_value_out_of_range then return null;
end
$function$;

create function reefish_private.grid_axis_id(p_axis bigint)
returns text language sql immutable strict set search_path = '' as $function$
  select case when p_axis < 0 then 'n' || pg_catalog.abs(p_axis)::text else 'p' || p_axis::text end
$function$;

create function reefish_private.grid_cell_indices(p_grid_id text, p_cell_id text)
returns table (row_index bigint, col_index bigint)
language plpgsql immutable strict set search_path = '' as $function$
declare v_match text[];
begin
  v_match := pg_catalog.regexp_match(p_cell_id, '^(.*):r(p(0|[1-9][0-9]*)|n([1-9][0-9]*)):c(p(0|[1-9][0-9]*)|n([1-9][0-9]*))$');
  if v_match is null or v_match[1] <> p_grid_id then return; end if;
  row_index := reefish_private.grid_parse_axis(v_match[2]);
  col_index := reefish_private.grid_parse_axis(v_match[5]);
  if row_index is null or col_index is null then return; end if;
  return next;
end
$function$;

create function reefish_private.area_geom(p_area_id text)
returns extensions.geometry
language plpgsql stable security definer set search_path = '' as $function$
declare v_bounds jsonb;
begin
  select a.bounds into v_bounds from public.map_areas a where a.id = p_area_id;
  if not found then raise exception using errcode = 'P0002', message = 'Unknown map area'; end if;
  return extensions.ST_Transform(
    extensions.ST_MakeEnvelope((v_bounds ->> 0)::float8, (v_bounds ->> 1)::float8,
      (v_bounds ->> 2)::float8, (v_bounds ->> 3)::float8, 4326), 32749);
end
$function$;

create function reefish_private.grid_cell_geom(p_area_id text, p_grid_id text, p_cell_id text)
returns extensions.geometry
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_grid public.grid_definitions%rowtype;
  v_row bigint;
  v_col bigint;
  v_x double precision;
  v_y double precision;
  v_size double precision;
begin
  select g.* into v_grid from public.grid_definitions g where g.area_id = p_area_id and g.id = p_grid_id;
  if not found then raise exception using errcode = 'P0002', message = 'Unknown grid definition'; end if;
  select i.row_index, i.col_index into v_row, v_col
    from reefish_private.grid_cell_indices(p_grid_id, p_cell_id) i;
  if v_row is null or v_col is null then
    raise exception using errcode = '22023', message = 'Malformed or non-canonical cell identifier for this grid';
  end if;
  v_size := v_grid.cell_size_m::double precision;
  v_x := v_grid.origin_x_m + v_col::numeric * v_size;
  v_y := v_grid.origin_y_m + v_row::numeric * v_size;
  if abs(v_x) > 10000000 or abs(v_y) > 10000000
     or v_x + v_size < -10000000 or v_y + v_size < -10000000 then
    raise exception using errcode = '22023', message = 'Cell coordinate is outside supported bounds';
  end if;
  return extensions.ST_MakeEnvelope(v_x, v_y, v_x + v_size, v_y + v_size, v_grid.srid);
end
$function$;

create function reefish_private.cell_intersects_area(p_area_id text, p_grid_id text, p_cell_id text)
returns boolean language plpgsql stable security definer set search_path = '' as $function$
declare v_cell extensions.geometry; v_area extensions.geometry;
begin
  v_cell := reefish_private.grid_cell_geom(p_area_id, p_grid_id, p_cell_id);
  v_area := reefish_private.area_geom(p_area_id);
  return extensions.ST_Area(extensions.ST_Intersection(v_cell, v_area)) > 0;
end
$function$;

create function reefish_private.grid_json(
  p_id text, p_area_id text, p_cell_size_m integer, p_srid integer,
  p_origin_x_m double precision, p_origin_y_m double precision, p_bounds jsonb
) returns jsonb language sql immutable set search_path = '' as $function$
  select pg_catalog.jsonb_build_object(
    'id', p_id, 'area_id', p_area_id, 'cell_size_m', p_cell_size_m,
    'srid', p_srid, 'origin_x_m', p_origin_x_m, 'origin_y_m', p_origin_y_m,
    'bounds', p_bounds)
$function$;

-- Candidate generation is bounded before rasterizing any restriction geometry.
create function reefish_private.visible_lock_rows(p_area_id text, p_grid_id text, p_allow_draft boolean default false)
returns table (cell_id text, reason text)
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_grid public.grid_definitions%rowtype;
  v_candidates numeric;
begin
  select g.* into v_grid from public.grid_definitions g
  where g.area_id = p_area_id and g.id = p_grid_id
    and (g.state in ('published', 'archived') or (p_allow_draft and g.state = 'draft'));
  if not found then raise exception using errcode = '22023', message = 'Grid must be a published definition'; end if;
  select coalesce(sum(
    (pg_catalog.floor((extensions.ST_XMax(r.geom) - v_grid.origin_x_m) / v_grid.cell_size_m)
      - pg_catalog.floor((extensions.ST_XMin(r.geom) - v_grid.origin_x_m) / v_grid.cell_size_m) + 1)
    * (pg_catalog.floor((extensions.ST_YMax(r.geom) - v_grid.origin_y_m) / v_grid.cell_size_m)
      - pg_catalog.floor((extensions.ST_YMin(r.geom) - v_grid.origin_y_m) / v_grid.cell_size_m) + 1)
  ), 0) into v_candidates
  from public.grid_restrictions r where r.area_id = p_area_id and r.removed_at is null;
  if v_candidates > 50000 then
    raise exception using errcode = '54000', message = 'Lock snapshot candidate limit exceeded; use a coarser grid or reduce active restrictions';
  end if;

  return query
  with source as (
    select r.geom, r.reason,
      pg_catalog.floor((extensions.ST_XMin(r.geom) - v_grid.origin_x_m) / v_grid.cell_size_m)::bigint as col_min,
      pg_catalog.floor((extensions.ST_XMax(r.geom) - v_grid.origin_x_m) / v_grid.cell_size_m)::bigint as col_max,
      pg_catalog.floor((extensions.ST_YMin(r.geom) - v_grid.origin_y_m) / v_grid.cell_size_m)::bigint as row_min,
      pg_catalog.floor((extensions.ST_YMax(r.geom) - v_grid.origin_y_m) / v_grid.cell_size_m)::bigint as row_max
    from public.grid_restrictions r where r.area_id = p_area_id and r.removed_at is null
  ), candidates as (
    select s.geom, s.reason, x.col_index, y.row_index
    from source s
    cross join lateral pg_catalog.generate_series(s.col_min, s.col_max) x(col_index)
    cross join lateral pg_catalog.generate_series(s.row_min, s.row_max) y(row_index)
  ), matched as (
    select c.reason, c.row_index, c.col_index,
      extensions.ST_MakeEnvelope(
        v_grid.origin_x_m + c.col_index::numeric * v_grid.cell_size_m,
        v_grid.origin_y_m + c.row_index::numeric * v_grid.cell_size_m,
        v_grid.origin_x_m + (c.col_index + 1)::numeric * v_grid.cell_size_m,
        v_grid.origin_y_m + (c.row_index + 1)::numeric * v_grid.cell_size_m,
        v_grid.srid) as cell_geom,
      c.geom as restriction_geom
    from candidates c
  ), visible as (
    select m.reason, m.row_index, m.col_index
    from matched m
    where extensions.ST_Area(extensions.ST_Intersection(m.cell_geom, m.restriction_geom)) > 0
      and extensions.ST_Area(extensions.ST_Intersection(m.cell_geom, reefish_private.area_geom(p_area_id))) > 0
  )
  select v_grid.id || ':r' || reefish_private.grid_axis_id(v.row_index)
       || ':c' || reefish_private.grid_axis_id(v.col_index),
       pg_catalog.string_agg(distinct v.reason, '; ' order by v.reason)
  from visible v group by v.row_index, v.col_index;
end
$function$;

-- Membership is trusted database state only. No caller metadata is consulted.
create function reefish_private.require_area_admin(p_area_id text)
returns uuid language plpgsql stable security definer set search_path = '' as $function$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null then raise exception using errcode = '42501', message = 'Authentication required'; end if;
  if not exists (select 1 from public.map_area_admins m where m.area_id = p_area_id and m.user_id = v_actor) then
    raise exception using errcode = '42501', message = 'Area admin membership required';
  end if;
  return v_actor;
end
$function$;

create function reefish_private.check_expected_version(p_expected_version text, p_actual bigint)
returns void language plpgsql immutable set search_path = '' as $function$
begin
  if p_expected_version is null or p_expected_version !~ '^[1-9][0-9]*$'
     or p_expected_version::numeric <> p_actual then
    raise exception using errcode = '40001', message = 'Stale map area version; refresh the grid snapshot';
  end if;
end
$function$;

-- Admin RPC implementations.
create function reefish_private.impl_get_grid_lock_snapshot(p_area_id text, p_grid_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_area public.map_areas%rowtype;
  v_grid public.grid_definitions%rowtype;
  v_grid_id text;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_locks jsonb;
begin
  if auth.uid() is null then raise exception using errcode = '42501', message = 'Authentication required'; end if;
  select a.* into v_area from public.map_areas a where a.id = p_area_id;
  if not found then raise exception using errcode = 'P0002', message = 'Unknown map area'; end if;
  v_grid_id := coalesce(p_grid_id, v_area.active_grid_id);
  select g.* into v_grid from public.grid_definitions g
   where g.area_id = p_area_id and g.id = v_grid_id
     and g.state in ('published', 'archived');
  if not found then raise exception using errcode = '22023', message = 'Grid snapshot requires the active or another published/archived grid'; end if;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('cell_id', l.cell_id, 'reason', l.reason) order by l.cell_id), '[]'::jsonb)
    into v_locks from reefish_private.visible_lock_rows(p_area_id, v_grid_id, false) l;
  return pg_catalog.jsonb_build_object(
    'grid', reefish_private.grid_json(v_grid.id, v_grid.area_id, v_grid.cell_size_m,
      v_grid.srid, v_grid.origin_x_m, v_grid.origin_y_m, v_grid.bounds),
    'version', v_area.version::text,
    'fetched_at', pg_catalog.to_char(pg_catalog.timezone('UTC', v_now), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'expires_at', pg_catalog.to_char(pg_catalog.timezone('UTC', v_now + interval '5 minutes'), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'is_demo', false, 'locks', v_locks);
end
$function$;

create function reefish_private.impl_set_grid_lock(
  p_area_id text, p_cell_id text, p_locked boolean, p_reason text,
  p_expected_version text, p_grid_id text
) returns text language plpgsql security definer set search_path = '' as $function$
declare
  v_actor uuid;
  v_area public.map_areas%rowtype;
  v_grid public.grid_definitions%rowtype;
  v_target_grid_id text;
  v_geom extensions.geometry;
  v_existing public.grid_restrictions%rowtype;
  v_candidate_count integer;
  v_restriction_id bigint;
  v_version bigint;
begin
  if p_area_id is null or p_cell_id is null or p_locked is null then
    raise exception using errcode = '22023', message = 'Area, cell, and lock state are required';
  end if;
  if p_locked and (p_reason is null or pg_catalog.length(pg_catalog.btrim(p_reason)) not between 1 and 500) then
    raise exception using errcode = '22023', message = 'A non-empty reason of at most 500 characters is required when restricting a cell';
  end if;
  select a.* into v_area from public.map_areas a where a.id = p_area_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Unknown map area'; end if;
  v_actor := reefish_private.require_area_admin(p_area_id);
  perform reefish_private.check_expected_version(p_expected_version, v_area.version);
  v_target_grid_id := coalesce(p_grid_id, v_area.active_grid_id);
  select g.* into v_grid from public.grid_definitions g
  where g.area_id = p_area_id and g.id = v_target_grid_id and g.state in ('published', 'archived');
  if not found then raise exception using errcode = '22023', message = 'Restrictions may be placed only on published or archived grids'; end if;
  v_geom := reefish_private.grid_cell_geom(p_area_id, v_grid.id, p_cell_id);
  if not reefish_private.cell_intersects_area(p_area_id, v_grid.id, p_cell_id) then
    raise exception using errcode = '22023', message = 'Cell does not overlap the map area';
  end if;

  if p_locked then
    select r.* into v_existing from public.grid_restrictions r
    where r.area_id = p_area_id and r.source_grid_id = v_grid.id
      and r.source_cell_id = p_cell_id and r.removed_at is null for update;
    if found then
      if v_existing.reason = pg_catalog.btrim(p_reason) then return v_area.version::text; end if;
      update public.grid_restrictions set reason = pg_catalog.btrim(p_reason) where id = v_existing.id;
      v_restriction_id := v_existing.id;
      insert into public.grid_admin_audit(area_id, actor_user_id, action, grid_id, cell_id, restriction_id, detail)
      values (p_area_id, v_actor, 'restriction_reason_changed', v_grid.id, p_cell_id, v_restriction_id,
        pg_catalog.jsonb_build_object('old_reason',v_existing.reason,'new_reason',pg_catalog.btrim(p_reason)));
    else
      insert into public.grid_restrictions(area_id, source_grid_id, source_cell_id, reason, geom, created_by)
      values (p_area_id, v_grid.id, p_cell_id, pg_catalog.btrim(p_reason), v_geom, v_actor)
      returning id into v_restriction_id;
      insert into public.grid_admin_audit(area_id, actor_user_id, action, grid_id, cell_id, restriction_id, detail)
      values (p_area_id, v_actor, 'restriction_added', v_grid.id, p_cell_id, v_restriction_id,
        pg_catalog.jsonb_build_object('reason',pg_catalog.btrim(p_reason)));
    end if;
  else
    select r.* into v_existing from public.grid_restrictions r
    where r.area_id = p_area_id and r.source_grid_id = v_grid.id
      and r.source_cell_id = p_cell_id and r.removed_at is null for update;
    if not found then
      select pg_catalog.count(*) into v_candidate_count from public.grid_restrictions r
      where r.area_id = p_area_id and r.removed_at is null and r.geom OPERATOR(extensions.&&) v_geom
        and extensions.ST_Area(extensions.ST_Intersection(r.geom, v_geom)) > 0;
      if v_candidate_count > 0 then
        raise exception using errcode = '22023', message = pg_catalog.format(
          'Unlock requires the exact source grid and source cell: this selected cell only overlaps %s active restriction(s).', v_candidate_count);
      end if;
      return v_area.version::text;
    end if;
    update public.grid_restrictions set removed_by = v_actor, removed_at = pg_catalog.clock_timestamp(),
      removal_note = nullif(pg_catalog.btrim(p_reason), '') where id = v_existing.id;
    v_restriction_id := v_existing.id;
    insert into public.grid_admin_audit(area_id, actor_user_id, action, grid_id, cell_id, restriction_id, detail)
    values (p_area_id, v_actor, 'restriction_removed', v_existing.source_grid_id, v_existing.source_cell_id, v_restriction_id,
      pg_catalog.jsonb_build_object('reason',v_existing.reason,'removal_note',nullif(pg_catalog.btrim(p_reason),'')));
  end if;

  update public.map_areas set version = version + 1 where id = p_area_id returning version into v_version;
  return v_version::text;
end
$function$;

create function reefish_private.impl_create_grid_definition(
  p_area_id text, p_cell_size_m integer, p_expected_version text
) returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_actor uuid;
  v_area public.map_areas%rowtype;
  v_base public.grid_definitions%rowtype;
  v_id text;
  v_new_version bigint;
  v_grid public.grid_definitions%rowtype;
begin
  select a.* into v_area from public.map_areas a where a.id = p_area_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Unknown map area'; end if;
  v_actor := reefish_private.require_area_admin(p_area_id);
  perform reefish_private.check_expected_version(p_expected_version, v_area.version);
  if p_cell_size_m is null or p_cell_size_m not between 100 and 5000 or p_cell_size_m % 50 <> 0 then
    raise exception using errcode = '22023', message = 'Cell size must be a 50 m multiple from 100 m through 5000 m';
  end if;
  select g.* into v_base from public.grid_definitions g
    where g.area_id = p_area_id and g.id = v_area.active_grid_id;
  if not found then raise exception using errcode = '55000', message = 'Area has no active grid definition'; end if;
  v_id := 'grid-' || pg_catalog.gen_random_uuid()::text;
  insert into public.grid_definitions(area_id,id,cell_size_m,srid,origin_x_m,origin_y_m,bounds,state,created_by)
  values(p_area_id,v_id,p_cell_size_m,v_base.srid,v_base.origin_x_m,v_base.origin_y_m,v_area.bounds,'draft',v_actor)
  returning * into v_grid;
  update public.map_areas set version = version + 1 where id = p_area_id returning version into v_new_version;
  insert into public.grid_admin_audit(area_id,actor_user_id,action,grid_id,detail)
  values(p_area_id,v_actor,'grid_created',v_id,pg_catalog.jsonb_build_object('version',v_new_version::text));
  return pg_catalog.jsonb_build_object(
    'grid',reefish_private.grid_json(v_grid.id,v_grid.area_id,v_grid.cell_size_m,v_grid.srid,
      v_grid.origin_x_m,v_grid.origin_y_m,v_grid.bounds),
    'version',v_new_version::text);
end
$function$;

create function reefish_private.impl_preview_grid_definition(p_area_id text,p_grid_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_actor uuid;
  v_area public.map_areas%rowtype;
  v_grid public.grid_definitions%rowtype;
  v_area_geom extensions.geometry;
  v_col_min bigint; v_col_max bigint; v_row_min bigint; v_row_max bigint;
  v_candidates numeric; v_inside bigint; v_affected bigint;
begin
  v_actor := reefish_private.require_area_admin(p_area_id);
  select a.* into v_area from public.map_areas a where a.id = p_area_id;
  if not found then raise exception using errcode = 'P0002', message = 'Unknown map area'; end if;
  select g.* into v_grid from public.grid_definitions g where g.area_id=p_area_id and g.id=p_grid_id and g.state='draft';
  if not found then raise exception using errcode = '22023', message = 'Preview requires a draft grid definition'; end if;
  v_area_geom := reefish_private.area_geom(p_area_id);
  v_col_min := pg_catalog.floor((extensions.ST_XMin(v_area_geom)-v_grid.origin_x_m)/v_grid.cell_size_m)::bigint;
  v_col_max := pg_catalog.floor((extensions.ST_XMax(v_area_geom)-v_grid.origin_x_m)/v_grid.cell_size_m)::bigint;
  v_row_min := pg_catalog.floor((extensions.ST_YMin(v_area_geom)-v_grid.origin_y_m)/v_grid.cell_size_m)::bigint;
  v_row_max := pg_catalog.floor((extensions.ST_YMax(v_area_geom)-v_grid.origin_y_m)/v_grid.cell_size_m)::bigint;
  v_candidates := (v_col_max-v_col_min+1)::numeric * (v_row_max-v_row_min+1)::numeric;
  if v_candidates > 50000 then raise exception using errcode='54000', message='Grid preview candidate limit exceeded'; end if;
  select count(*) into v_inside from pg_catalog.generate_series(v_col_min,v_col_max) c
  cross join pg_catalog.generate_series(v_row_min,v_row_max) r
  where extensions.ST_Area(extensions.ST_Intersection(
    extensions.ST_MakeEnvelope(v_grid.origin_x_m+c::numeric*v_grid.cell_size_m,
      v_grid.origin_y_m+r::numeric*v_grid.cell_size_m,
      v_grid.origin_x_m+(c+1)::numeric*v_grid.cell_size_m,
      v_grid.origin_y_m+(r+1)::numeric*v_grid.cell_size_m,v_grid.srid),v_area_geom)) > 0;
  select pg_catalog.count(*) into v_affected
    from reefish_private.visible_lock_rows(p_area_id, p_grid_id, true);
  return pg_catalog.jsonb_build_object(
    'grid',reefish_private.grid_json(v_grid.id,v_grid.area_id,v_grid.cell_size_m,v_grid.srid,
      v_grid.origin_x_m,v_grid.origin_y_m,v_grid.bounds),
    'version',v_area.version::text,'candidate_cell_count',v_candidates::bigint,
    'in_area_cell_count',v_inside,'affected_lock_count',v_affected);
end
$function$;

create function reefish_private.impl_publish_grid_definition(
  p_area_id text,p_grid_id text,p_expected_version text,p_confirm_restrictions boolean
) returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_actor uuid;
  v_area public.map_areas%rowtype;
  v_grid public.grid_definitions%rowtype;
  v_old_grid_id text;
  v_active_restrictions bigint;
  v_version bigint;
begin
  select a.* into v_area from public.map_areas a where a.id=p_area_id for update;
  if not found then raise exception using errcode='P0002',message='Unknown map area'; end if;
  v_actor := reefish_private.require_area_admin(p_area_id);
  perform reefish_private.check_expected_version(p_expected_version,v_area.version);
  select g.* into v_grid from public.grid_definitions g
   where g.area_id=p_area_id and g.id=p_grid_id and g.state='draft' for update;
  if not found then raise exception using errcode='22023',message='Only a draft grid definition can be published'; end if;
  select count(*) into v_active_restrictions from public.grid_restrictions r
   where r.area_id=p_area_id and r.removed_at is null;
  if v_active_restrictions>0 and not coalesce(p_confirm_restrictions,false) then
    raise exception using errcode='22023',message=pg_catalog.format(
      'Publishing will remap %s active restrictions; review preview and set p_confirm_restrictions=true',v_active_restrictions);
  end if;
  v_old_grid_id := v_area.active_grid_id;
  update public.grid_definitions set state='published',published_at=pg_catalog.clock_timestamp()
   where area_id=p_area_id and id=p_grid_id;
  if v_old_grid_id is not null then
    update public.grid_definitions set state='archived',archived_at=pg_catalog.clock_timestamp()
     where area_id=p_area_id and id=v_old_grid_id and state='published';
    insert into public.grid_admin_audit(area_id,actor_user_id,action,grid_id,detail)
    values(p_area_id,v_actor,'grid_archived',v_old_grid_id,
      pg_catalog.jsonb_build_object('replaced_by',p_grid_id));
  end if;
  update public.map_areas set active_grid_id=p_grid_id,version=version+1
   where id=p_area_id returning version into v_version;
  insert into public.grid_admin_audit(area_id,actor_user_id,action,grid_id,detail)
  values(p_area_id,v_actor,'grid_published',p_grid_id,pg_catalog.jsonb_build_object(
    'previous_grid_id',v_old_grid_id,'active_restriction_count',v_active_restrictions,
    'version',v_version::text));
  return pg_catalog.jsonb_build_object(
    'grid',reefish_private.grid_json(v_grid.id,v_grid.area_id,v_grid.cell_size_m,v_grid.srid,
      v_grid.origin_x_m,v_grid.origin_y_m,v_grid.bounds),
    'version',v_version::text,'previous_grid_id',v_old_grid_id,
    'active_restriction_count',v_active_restrictions);
end
$function$;

create function reefish_private.impl_validate_fishing_grid_selection(
  p_area_id text,p_cell_id text,p_grid_id text
) returns boolean language plpgsql security definer set search_path = '' as $function$
declare
  v_area public.map_areas%rowtype;
  v_grid public.grid_definitions%rowtype;
  v_cell extensions.geometry;
begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required'; end if;
  select a.* into v_area from public.map_areas a where a.id=p_area_id for share;
  if not found then raise exception using errcode='P0002',message='Unknown map area'; end if;
  select g.* into v_grid from public.grid_definitions g where g.area_id=p_area_id
    and g.id=coalesce(p_grid_id,v_area.active_grid_id) and g.state in ('published','archived');
  if not found then raise exception using errcode='22023',message='Fishing selection requires a published or archived grid'; end if;
  v_cell := reefish_private.grid_cell_geom(p_area_id,v_grid.id,p_cell_id);
  if not reefish_private.cell_intersects_area(p_area_id,v_grid.id,p_cell_id) then
    raise exception using errcode='22023',message='Cell does not overlap the map area';
  end if;
  if exists(select 1 from public.grid_restrictions r where r.area_id=p_area_id
    and r.removed_at is null and r.geom OPERATOR(extensions.&&) v_cell
    and extensions.ST_Area(extensions.ST_Intersection(r.geom,v_cell))>0) then
    raise exception using errcode='23514',message='Fishing location overlaps an active administrative restriction';
  end if;
  return true;
end
$function$;

-- Public API functions are SECURITY INVOKER shims. Their implementations are
-- private, fixed-search-path SECURITY DEFINER functions with explicit auth checks.
create function public.get_grid_lock_snapshot(p_area_id text default 'east-java-pilot',p_grid_id text default null)
returns jsonb language sql stable security invoker set search_path = '' as $function$
  select reefish_private.impl_get_grid_lock_snapshot(p_area_id,p_grid_id)
$function$;
create function public.set_grid_lock(
  p_area_id text,p_cell_id text,p_locked boolean,p_reason text,p_expected_version text,p_grid_id text default null
) returns text language sql security invoker set search_path = '' as $function$
  select reefish_private.impl_set_grid_lock(p_area_id,p_cell_id,p_locked,p_reason,p_expected_version,p_grid_id)
$function$;
create function public.create_grid_definition(p_area_id text,p_cell_size_m integer,p_expected_version text)
returns jsonb language sql security invoker set search_path = '' as $function$
  select reefish_private.impl_create_grid_definition(p_area_id,p_cell_size_m,p_expected_version)
$function$;
create function public.preview_grid_definition(p_area_id text,p_grid_id text)
returns jsonb language sql stable security invoker set search_path = '' as $function$
  select reefish_private.impl_preview_grid_definition(p_area_id,p_grid_id)
$function$;
create function public.publish_grid_definition(
  p_area_id text,p_grid_id text,p_expected_version text,p_confirm_restrictions boolean default false
) returns jsonb language sql security invoker set search_path = '' as $function$
  select reefish_private.impl_publish_grid_definition(p_area_id,p_grid_id,p_expected_version,p_confirm_restrictions)
$function$;
create function public.validate_fishing_grid_selection(p_area_id text,p_cell_id text,p_grid_id text default null)
returns boolean language sql security invoker set search_path = '' as $function$
  select reefish_private.impl_validate_fishing_grid_selection(p_area_id,p_cell_id,p_grid_id)
$function$;

-- Seed only configuration. No human admin or fictional restrictions are seeded.
insert into public.map_areas(id,bounds,version,active_grid_id)
values('east-java-pilot','[112.25,-9.15,113.10,-8.35]'::jsonb,1,null);
insert into public.grid_definitions(area_id,id,cell_size_m,srid,origin_x_m,origin_y_m,bounds,state,published_at)
values('east-java-pilot','tp-id-utm49s-500m:v2',500,32749,0,0,
  '[112.25,-9.15,113.10,-8.35]'::jsonb,'published',pg_catalog.now()),
      ('east-java-pilot','tp-id-utm49s-1000m:v1',1000,32749,0,0,
  '[112.25,-9.15,113.10,-8.35]'::jsonb,'draft',null);
update public.map_areas set active_grid_id='tp-id-utm49s-500m:v2'
where id='east-java-pilot';

-- Flush the deferred active-grid FK now that both definitions exist. PostgreSQL
-- rejects ALTER TABLE while a deferred FK check on that table is still queued.
set constraints map_areas_active_grid_fk immediate;

alter table public.map_areas enable row level security;
alter table public.map_area_admins enable row level security;
alter table public.grid_definitions enable row level security;
alter table public.grid_restrictions enable row level security;
alter table public.grid_admin_audit enable row level security;

revoke all on table public.map_areas,public.map_area_admins,public.grid_definitions,
  public.grid_restrictions,public.grid_admin_audit from public,anon,authenticated;
revoke all on sequence public.grid_restrictions_id_seq, public.grid_admin_audit_id_seq from public,anon,authenticated;
revoke all on all functions in schema reefish_private from public,anon,authenticated;
revoke all on function public.get_grid_lock_snapshot(text,text) from public,anon,authenticated;
revoke all on function public.set_grid_lock(text,text,boolean,text,text,text) from public,anon,authenticated;
revoke all on function public.create_grid_definition(text,integer,text) from public,anon,authenticated;
revoke all on function public.preview_grid_definition(text,text) from public,anon,authenticated;
revoke all on function public.publish_grid_definition(text,text,text,boolean) from public,anon,authenticated;
revoke all on function public.validate_fishing_grid_selection(text,text,text) from public,anon,authenticated;
grant execute on function reefish_private.impl_get_grid_lock_snapshot(text,text) to authenticated;
grant execute on function reefish_private.impl_set_grid_lock(text,text,boolean,text,text,text) to authenticated;
grant execute on function reefish_private.impl_create_grid_definition(text,integer,text) to authenticated;
grant execute on function reefish_private.impl_preview_grid_definition(text,text) to authenticated;
grant execute on function reefish_private.impl_publish_grid_definition(text,text,text,boolean) to authenticated;
grant execute on function reefish_private.impl_validate_fishing_grid_selection(text,text,text) to authenticated;
grant execute on function public.get_grid_lock_snapshot(text,text) to authenticated;
grant execute on function public.set_grid_lock(text,text,boolean,text,text,text) to authenticated;
grant execute on function public.create_grid_definition(text,integer,text) to authenticated;
grant execute on function public.preview_grid_definition(text,text) to authenticated;
grant execute on function public.publish_grid_definition(text,text,text,boolean) to authenticated;
grant execute on function public.validate_fishing_grid_selection(text,text,text) to authenticated;
