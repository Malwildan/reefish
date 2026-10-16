-- Team decision 2026-10-16: a grid has 3 states, managed only through zones (docs/AGENTS.md 6):
--   normal (no zone) | restricted (catch capacity / quota per zone) | rehab (zero tolerance, cell disabled).
-- The system flags grids up to restricted (auto-flag); the konservatif aggregates them into zones and decides.
-- main's grid lock (contracts/grid-locks.md) now only mirrors rehab: the snapshot lists the cells of rehab zones
-- in force, validation rejects them, and set_grid_lock is retired. Public signatures are unchanged, so the
-- mobile client keeps working; legacy lock rows (none in practice) still count.

-- Snapshot: same five fields; version follows heatmap_version so it moves whenever a zone changes.
create or replace function public.get_grid_lock_snapshot(p_area_id text default 'east-java-pilot')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  -- validates the caller and the area exactly like main's implementation
  v_snapshot jsonb := reefish_private.impl_get_grid_lock_snapshot(p_area_id, null) - 'grid';
begin
  return v_snapshot || jsonb_build_object(
    'version', private.current_version()::text,
    'locks', coalesce((
      select jsonb_agg(l order by l ->> 'cell_id')
      from (
        select x as l from jsonb_array_elements(v_snapshot -> 'locks') x
        union all
        select jsonb_build_object('cell_id', g.cell_id, 'reason', 'Rehab: ' || z.name)
        from zones z
        join zone_grids zg on zg.zone_id = z.id
        join grid_cells g on g.grid_id = zg.grid_id
        where z.status = 'rehab' and private.zone_in_force(z, now())
      ) t
    ), '[]')
  );
end;
$$;

create or replace function public.validate_fishing_grid_selection(p_area_id text, p_cell_id text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- main's checks first: caller, area, canonical in-area cell, legacy locks
  perform reefish_private.impl_validate_fishing_grid_selection(p_area_id, p_cell_id, null);
  if exists (
    select 1 from grid_cells g
    join zone_grids zg on zg.grid_id = g.grid_id
    join zones z on z.id = zg.zone_id
    where g.cell_id = p_cell_id and z.status = 'rehab' and private.zone_in_force(z, now())
  ) then
    raise exception using errcode = '23514', message = 'Fishing location is in a rehab zone';
  end if;
  return true;
end;
$$;

-- Retired: cells are disabled by putting them in a rehab zone (api_admin_create_zone / api_admin_edit_zone_*).
create or replace function public.set_grid_lock(
  p_area_id text, p_cell_id text, p_locked boolean, p_reason text, p_expected_version text
) returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.fail('DEPRECATED_USE_ZONES',
    'Kunci grid sekarang lewat zona berstatus rehab (api_admin_create_zone / api_admin_edit_zone_status)');
  return null;
end;
$$;

revoke all on function public.get_grid_lock_snapshot(text) from public, anon, authenticated;
revoke all on function public.set_grid_lock(text, text, boolean, text, text) from public, anon, authenticated;
revoke all on function public.validate_fishing_grid_selection(text, text) from public, anon, authenticated;
grant execute on function public.get_grid_lock_snapshot(text) to authenticated;
grant execute on function public.set_grid_lock(text, text, boolean, text, text) to authenticated;
grant execute on function public.validate_fishing_grid_selection(text, text) to authenticated;
