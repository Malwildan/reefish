-- Rollback-only smoke test for a project with only the current cluster period imported.
-- Run after the latest prediction batch, grid_layers, and habitat batches are loaded.
begin;

insert into auth.users (id, email, aud, role)
values ('00000000-0000-4000-8000-00000000d101', 'smoke-layers-latest@phone.reefish.app', 'authenticated', 'authenticated');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-00000000d101", "role": "authenticated"}', true);

do $$
declare
  v jsonb;
  c jsonb;
begin
  v := public.api_layers();
  if jsonb_array_length(v -> 'periods') <> 1 or v ->> 'period' <> '2025-12'
     or v -> 'periods' ->> 0 <> '2025-12' or jsonb_array_length(v -> 'cells') <> 31354 then
    raise exception 'latest layers default %', v - 'cells';
  end if;

  select x into c from jsonb_array_elements(v -> 'cells') x where x ->> 0 = 'X149_Y001';
  if c is null or (c ->> 3)::numeric <> 29.136 or (c ->> 5)::numeric <> 5000 or (c ->> 6)::numeric <> 16.35 then
    raise exception 'latest fixture cell X149_Y001 %', c;
  end if;

  begin
    perform public.api_layers('1999-01');
    raise exception 'expected VALIDATION_ERROR';
  exception when raise_exception then
    if sqlerrm <> 'VALIDATION_ERROR' then raise; end if;
  end;

  v := public.api_habitat();
  if jsonb_array_length(v -> 'coral' -> 'features') <> 140
     or jsonb_array_length(v -> 'mangrove' -> 'features') <> 3
     or (select count(*) from jsonb_array_elements(v -> 'coral' -> 'features') f
         where (f -> 'properties' ->> 'value')::numeric = 1) <> 116 then
    raise exception 'habitat counts';
  end if;

  raise notice 'latest layers smoke test passed';
end;
$$;

-- Return a compact result row for remote SQL clients that do not surface NOTICE messages.
select jsonb_build_object(
  'result', 'layers_latest_passed',
  'period', public.api_layers() ->> 'period',
  'periods', public.api_layers() -> 'periods',
  'cells', jsonb_array_length(public.api_layers() -> 'cells'),
  'fixture_grid_id', 'X149_Y001',
  'coral_features', jsonb_array_length(public.api_habitat() -> 'coral' -> 'features'),
  'mangrove_features', jsonb_array_length(public.api_habitat() -> 'mangrove' -> 'features'),
  'coral_value_one_features', (
    select count(*) from jsonb_array_elements(public.api_habitat() -> 'coral' -> 'features') f
    where (f -> 'properties' ->> 'value')::numeric = 1
  )
) as verification;

rollback;
