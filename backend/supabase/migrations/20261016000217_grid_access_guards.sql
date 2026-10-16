-- RPC-only access is deliberate. Explicit deny policies also protect against
-- accidental table grants; trusted implementations perform their own auth checks.
create policy map_areas_rpc_only on public.map_areas
  as restrictive for all to anon, authenticated using (false) with check (false);
create policy map_area_admins_rpc_only on public.map_area_admins
  as restrictive for all to anon, authenticated using (false) with check (false);
create policy grid_definitions_rpc_only on public.grid_definitions
  as restrictive for all to anon, authenticated using (false) with check (false);
create policy grid_restrictions_rpc_only on public.grid_restrictions
  as restrictive for all to anon, authenticated using (false) with check (false);
create policy grid_admin_audit_rpc_only on public.grid_admin_audit
  as restrictive for all to anon, authenticated using (false) with check (false);

-- Cover FK lookups for retained history, membership, and immutable definitions.
create index map_area_admins_user_idx on public.map_area_admins (user_id);
create index map_areas_active_grid_idx on public.map_areas (id, active_grid_id);
create index grid_definitions_creator_idx on public.grid_definitions (created_by);
create index grid_restrictions_creator_idx on public.grid_restrictions (created_by);
create index grid_restrictions_remover_idx on public.grid_restrictions (removed_by);
create index grid_restrictions_source_grid_idx
  on public.grid_restrictions (area_id, source_grid_id);
create index grid_admin_audit_actor_idx on public.grid_admin_audit (actor_user_id);
create index grid_admin_audit_restriction_idx on public.grid_admin_audit (restriction_id);
