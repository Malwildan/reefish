create function public.is_konservatif()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'konservatif'
  );
$$;

alter table public.profiles enable row level security;
alter table public.cluster_levels enable row level security;
alter table public.grid_cells enable row level security;
alter table public.cluster_predictions enable row level security;
alter table public.zones enable row level security;

-- No update policy: role and profile changes go through the SQL editor
create policy "read own profile" on public.profiles
  for select to authenticated using (id = (select auth.uid()));

-- Model output is read-only; only the service-role import writes it
create policy "read levels" on public.cluster_levels
  for select to authenticated using (true);
create policy "read grid" on public.grid_cells
  for select to authenticated using (true);
create policy "read predictions" on public.cluster_predictions
  for select to authenticated using (true);

create policy "read zones" on public.zones
  for select to authenticated using (true);
create policy "konservatif insert zones" on public.zones
  for insert to authenticated with check ((select public.is_konservatif()));
create policy "konservatif update zones" on public.zones
  for update to authenticated
  using ((select public.is_konservatif()))
  with check ((select public.is_konservatif()));
create policy "konservatif delete zones" on public.zones
  for delete to authenticated using ((select public.is_konservatif()));
