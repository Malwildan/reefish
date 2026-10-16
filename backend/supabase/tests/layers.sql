-- Smoke test for migration 0008 (api_layers, api_habitat). Run after importing grid, clusters, coral,
-- mangrove and potensi_ikan (setup/README.md). Everything is rolled back.
begin;

insert into auth.users (id, email, aud, role)
values ('00000000-0000-4000-8000-00000000d001', 'smoke-layers@phone.reefish.app', 'authenticated', 'authenticated');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-00000000d001", "role": "authenticated"}', true);

do $$
declare
  v jsonb;
  c jsonb;
begin
  v := public.api_layers();
  if jsonb_array_length(v -> 'periods') <> 24 or v ->> 'period' <> '2025-12' or jsonb_array_length(v -> 'cells') <> 31354 then
    raise exception 'layers default %', v - 'cells';
  end if;
  -- cell (149,1): suhu_laut.csv = sst of 2025-12, potensi_ikan.csv 16.35 (guide section 3)
  select x into c from jsonb_array_elements(v -> 'cells') x where x ->> 0 = 'X149_Y001';
  if (c ->> 3)::numeric <> 29.136 or (c ->> 5)::numeric <> 5000 or (c ->> 6)::numeric <> 16.35 then
    raise exception 'cell X149_Y001 %', c;
  end if;

  v := public.api_layers('2024-01', array[112.9, -9.16, 113.0, -9.10]);
  select x into c from jsonb_array_elements(v -> 'cells') x where x ->> 0 = 'X149_Y001';
  -- chlorophyll entry 1 of the export = period 2024-01
  if (c ->> 4)::numeric <> 0.2612 or jsonb_array_length(v -> 'cells') >= 31354 then
    raise exception 'layers 2024-01 bbox %', c;
  end if;

  begin
    perform public.api_layers('1999-01');
    raise exception 'expected VALIDATION_ERROR';
  exception when raise_exception then
    if sqlerrm <> 'VALIDATION_ERROR' then raise; end if;
  end;

  v := public.api_habitat();
  if jsonb_array_length(v -> 'coral' -> 'features') <> 140 or jsonb_array_length(v -> 'mangrove' -> 'features') <> 3
     or (select count(*) from jsonb_array_elements(v -> 'coral' -> 'features') f where (f -> 'properties' ->> 'value')::numeric = 1) <> 116 then
    raise exception 'habitat counts';
  end if;

  raise notice 'layers smoke test passed';
end;
$$;

rollback;
