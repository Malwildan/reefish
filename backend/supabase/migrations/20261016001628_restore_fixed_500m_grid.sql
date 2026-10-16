-- Forward-only rollback of dynamic grid administration. Preserve the area,
-- legacy 500 m definition, restrictions, audit, membership, and auth state.

-- A dynamic draft may be deleted only when it is the known unused 1000 m seed.
-- Fail closed if a live restriction, audit record, active pointer, or unexpected
-- definition appeared after the preflight review.
do $rollback_guard$
begin
  if exists (
    select 1 from public.grid_definitions g
    where not (
      g.area_id = 'east-java-pilot'
      and g.id = 'tp-id-utm49s-1000m:v1'
      and g.cell_size_m = 1000
      and g.srid = 32749
      and g.origin_x_m = 0 and g.origin_y_m = 0
      and g.state = 'draft'
    )
    and not (
      g.cell_size_m = 500 and g.srid = 32749
      and g.origin_x_m = 0 and g.origin_y_m = 0
      and g.state in ('published','archived')
    )
  ) then
    raise exception 'Grid rollback blocked: a non-static definition exists';
  end if;

  if exists (select 1 from public.map_areas a
      where a.id = 'east-java-pilot' and a.active_grid_id = 'tp-id-utm49s-1000m:v1') then
    raise exception 'Grid rollback blocked: 1000 m definition is active';
  end if;
  if exists (select 1 from public.grid_restrictions r
      where r.area_id = 'east-java-pilot' and r.source_grid_id = 'tp-id-utm49s-1000m:v1') then
    raise exception 'Grid rollback blocked: restrictions reference the 1000 m definition';
  end if;
  if exists (select 1 from public.grid_admin_audit a
      where a.area_id = 'east-java-pilot'
        and (a.grid_id = 'tp-id-utm49s-1000m:v1'
          or a.cell_id like 'tp-id-utm49s-1000m:v1:%')) then
    raise exception 'Grid rollback blocked: audit history references the 1000 m definition';
  end if;
  if exists (select 1 from public.grid_definitions g
      where g.area_id = 'east-java-pilot'
        and g.id = 'tp-id-utm49s-1000m:v1'
        and (g.cell_size_m <> 1000 or g.srid <> 32749
          or g.origin_x_m <> 0 or g.origin_y_m <> 0 or g.state <> 'draft')) then
    raise exception 'Grid rollback blocked: the known 1000 m seed is no longer an unused draft';
  end if;
end
$rollback_guard$;

-- Remove only the dynamic management entry points and implementations. RESTRICT
-- intentionally makes unexpected dependencies stop this migration for review.
drop function public.create_grid_definition(text,integer,text) restrict;
drop function public.preview_grid_definition(text,text) restrict;
drop function public.publish_grid_definition(text,text,text,boolean) restrict;
drop function reefish_private.impl_create_grid_definition(text,integer,text) restrict;
drop function reefish_private.impl_preview_grid_definition(text,text) restrict;
drop function reefish_private.impl_publish_grid_definition(text,text,text,boolean) restrict;

delete from public.grid_definitions
where area_id = 'east-java-pilot'
  and id = 'tp-id-utm49s-1000m:v1'
  and cell_size_m = 1000 and srid = 32749
  and origin_x_m = 0 and origin_y_m = 0 and state = 'draft';

-- Flush the deferred active-grid FK check before altering its referenced table.
set constraints map_areas_active_grid_fk immediate;

alter table public.grid_definitions
  add constraint grid_definitions_fixed_500m_check check (
    cell_size_m = 500 and srid = 32749
    and origin_x_m = 0 and origin_y_m = 0
    and state in ('published','archived')
  );

-- Restore the public RPC signatures used by the fixed 500 m mobile client.
drop function public.get_grid_lock_snapshot(text,text) restrict;
create function public.get_grid_lock_snapshot(p_area_id text default 'east-java-pilot')
returns jsonb
language sql stable security invoker set search_path = ''
as $function$
  select reefish_private.impl_get_grid_lock_snapshot(p_area_id,null) - 'grid'
$function$;

drop function public.set_grid_lock(text,text,boolean,text,text,text) restrict;
create function public.set_grid_lock(
  p_area_id text, p_cell_id text, p_locked boolean, p_reason text, p_expected_version text
) returns text
language sql security invoker set search_path = ''
as $function$
  select reefish_private.impl_set_grid_lock(
    p_area_id,p_cell_id,p_locked,p_reason,p_expected_version,null)
$function$;

drop function public.validate_fishing_grid_selection(text,text,text) restrict;
create function public.validate_fishing_grid_selection(p_area_id text,p_cell_id text)
returns boolean
language sql security invoker set search_path = ''
as $function$
  select reefish_private.impl_validate_fishing_grid_selection(p_area_id,p_cell_id,null)
$function$;

revoke all on function public.get_grid_lock_snapshot(text) from public,anon,authenticated;
revoke all on function public.set_grid_lock(text,text,boolean,text,text) from public,anon,authenticated;
revoke all on function public.validate_fishing_grid_selection(text,text) from public,anon,authenticated;
grant execute on function public.get_grid_lock_snapshot(text) to authenticated;
grant execute on function public.set_grid_lock(text,text,boolean,text,text) to authenticated;
grant execute on function public.validate_fishing_grid_selection(text,text) to authenticated;
