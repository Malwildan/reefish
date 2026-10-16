-- Demo data for app/dashboard demos (docs/AGENTS.md scenarios). NOT a migration, NOT a test: rows persist.
-- Every demo account uses *@demo.reefish.app / phone 62899000…; remove everything with demo_reset.sql.
-- Requires the grid/ML import (setup/README.md section 3). Re-running replaces the previous demo data.
--
-- Run as postgres (psql or SQL Editor), opting in explicitly so it never runs by accident:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -c "set reefish.allow_demo = 'on'" -f supabase/seed/demo.sql
--   (SQL Editor: run `set reefish.allow_demo = 'on';` in the same query, above the file contents)
--
-- Scenarios (port Sendang Biru, lat -8.43 lng 112.68; all dates relative to today, WIB):
--   1. Nelayan baru    demo-baru     boat filled, onboarding trip not sent yet -> onboarding -> recommendations
--   2. Nelayan aktif   demo-aktif    30 days of trips around X102_Y156 -> baseline fuel, habitual cell
--   3. Grid ramai      demo-n01..20  ~3 weeks of trips on coral cells X100..X102_Y152 -> fatigue critical,
--                                    auto-flag restricted, excluded from recommendations, in admin suggestions
--   4. Zona restricted "Demo Karang Kuota" (X102..X103_Y154..Y155) monthly quota 600 kg, ~85 % used this month
--   5. Zona rehab      "Demo Rehab Pulih" (X098_Y153, X099_Y153, X099_Y154) recovered -> reopen suggestion;
--                                    one violating trip on X099_Y154
--   6. Konservatif     demo-admin    owns the zones, decides on the flags and suggestions
-- Password for every demo account: Demo#2026

begin;

do $$
begin
  if current_setting('reefish.allow_demo', true) is distinct from 'on' then
    raise exception 'Demo seed refused: run "set reefish.allow_demo = ''on''" in this session first';
  end if;
end;
$$;

-- Removes every demo row and its heatmap contribution; also called by demo_reset.sql.
create or replace function private.demo_reset()
returns void
language plpgsql
set search_path = public, extensions, pg_temp
as $$
begin
  -- take the demo trips' load back out of the daily totals before the trips disappear
  with demo_load as (
    select f.grid_id, (coalesce(f.started_at, t.departed_at) at time zone 'Asia/Jakarta')::date as day,
      count(*) as visits, coalesce(sum(f.fishing_hours), 0) as hours, coalesce(sum(f.allocated_catch_kg), 0) as kg
    from fishing_points f
    join trips t on t.id = f.trip_id
    join auth.users u on u.id = t.user_id
    where u.email like '%@demo.reefish.app' and f.grid_id is not null
    group by 1, 2
  )
  update grid_daily_load l set
    visits = greatest(l.visits - d.visits, 0),
    fishing_hours = greatest(l.fishing_hours - d.hours, 0),
    catch_kg = greatest(l.catch_kg - d.kg, 0)
  from demo_load d
  where l.grid_id = d.grid_id and l.day = d.day;
  delete from grid_daily_load where visits = 0 and fishing_hours = 0 and catch_kg = 0 and fatigue is null;

  delete from flag_dismissals where dismissed_by in (select id from auth.users where email like '%@demo.reefish.app');
  delete from zones where name like 'Demo %';
  delete from auth.users where email like '%@demo.reefish.app';  -- cascades to profiles, boats, trips, recommendations
  update grid_stats set days_low_fatigue = 0, suggestion = null where suggestion is not null or days_low_fatigue > 0;
  perform private.daily_refresh();
end;
$$;
revoke execute on function private.demo_reset() from public;

select private.demo_reset();

-- ------------------------------------------------------------------------------------------------
-- Helpers for this session only
-- ------------------------------------------------------------------------------------------------

create function pg_temp.demo_user(p_handle text, p_phone text, p_name text, p_role text default 'nelayan')
returns uuid
language plpgsql
as $$
declare
  v_id uuid := gen_random_uuid();
  v_email text := p_handle || '@demo.reefish.app';
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, phone, phone_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    phone_change, phone_change_token, email_change_token_current, reauthentication_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
    extensions.crypt('Demo#2026', extensions.gen_salt('bf')), now(), p_phone, now(),
    '{"provider": "email", "providers": ["email", "phone"]}', jsonb_build_object('full_name', p_name), now(), now(),
    '', '', '', '', '', '', '', ''
  );
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (v_id::text, v_id, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
          'email', now(), now(), now());
  if p_role = 'konservatif' then
    update public.profiles set role = 'konservatif' where id = v_id;
  end if;
  return v_id;
end;
$$;

-- Calls the API as that user (the RPCs read auth.uid() from the JWT claims).
create function pg_temp.act_as(p_user uuid)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.cell(p_grid text)
returns jsonb
language sql
as $$
  select jsonb_build_object('lat', round(st_y(geom::geometry)::numeric, 6), 'lng', round(st_x(geom::geometry)::numeric, 6))
  from public.grid_cells where grid_id = p_grid;
$$;

-- One trip: departs at 04:00 WIB p_days_ago, back 8 h later, fishing at the given cells (catch split evenly).
create function pg_temp.trip(p_user uuid, p_seq int, p_source text, p_days_ago int, p_cells text[], p_fuel numeric, p_catch numeric)
returns jsonb
language plpgsql
as $$
declare
  v_dep timestamptz := ((now() at time zone 'Asia/Jakarta')::date - p_days_ago + time '04:00') at time zone 'Asia/Jakarta';
begin
  perform pg_temp.act_as(p_user);
  return public.api_post_trip(jsonb_build_object(
    'client_trip_id', md5(p_user::text || ':' || p_seq)::uuid,
    'source', p_source,
    'departed_at', to_char(v_dep at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'returned_at', to_char((v_dep + interval '8 hours') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'fuel_liters', p_fuel,
    'catch_kg', p_catch,
    'fishing_points', (select jsonb_agg(pg_temp.cell(c)) from unnest(p_cells) c)
  ));
end;
$$;

-- ------------------------------------------------------------------------------------------------
-- Scenario
-- ------------------------------------------------------------------------------------------------

do $$
declare
  v_port jsonb := '{"lat": -8.43, "lng": 112.68}';
  v_hot text[] := array['X100_Y152', 'X101_Y152', 'X102_Y152'];
  v_quota text[] := array['X102_Y154', 'X103_Y154', 'X102_Y155', 'X103_Y155'];
  v_rehab text[] := array['X098_Y153', 'X099_Y153', 'X099_Y154'];
  v_habit text := 'X102_Y156';
  v_month_days int := extract(day from now() at time zone 'Asia/Jakarta')::int - 1;  -- past days in this month
  v_admin uuid;
  v_baru uuid;
  v_aktif uuid;
  v_n uuid;
  v_crowd uuid[] := '{}';
  v_missing text[];
  i int;
  d int;
begin
  select array_agg(x) into v_missing
  from unnest(v_hot || v_quota || v_rehab || v_habit) x
  where not exists (select 1 from public.grid_cells g where g.grid_id = x and g.is_sea);
  if v_missing is not null then
    raise exception 'Demo cells missing (import the grid first): %', v_missing;
  end if;

  -- accounts
  v_admin := pg_temp.demo_user('demo-admin', '6289900000001', 'Admin Konservasi Demo', 'konservatif');
  v_baru := pg_temp.demo_user('demo-baru', '6289900000002', 'Pak Baru');
  v_aktif := pg_temp.demo_user('demo-aktif', '6289900000003', 'Pak Aktif');
  for i in 1..20 loop
    v_crowd := v_crowd || pg_temp.demo_user(format('demo-n%s', lpad(i::text, 2, '0')), format('62899000001%s', lpad(i::text, 2, '0')),
                                            format('Nelayan Demo %s', i));
  end loop;

  -- 6. konservatif creates the two zones, in force since 25 days ago
  perform pg_temp.act_as(v_admin);
  perform public.api_admin_create_zone(jsonb_build_object(
    'name', 'Demo Karang Kuota', 'status', 'restricted', 'grid_ids', to_jsonb(v_quota),
    'rules', jsonb_build_object('max_catch_kg_per_period', 600, 'period', 'monthly'),
    'effective_from', to_char((now() - interval '25 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'reason', 'Demo: tekanan tinggi di karang dekat dermaga, dibatasi dengan kuota bulanan'));
  perform public.api_admin_create_zone(jsonb_build_object(
    'name', 'Demo Rehab Pulih', 'status', 'rehab', 'grid_ids', to_jsonb(v_rehab),
    'effective_from', to_char((now() - interval '25 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'reason', 'Demo: rehabilitasi karang, dilarang total'));

  -- 1. new fisher: boat only
  perform pg_temp.act_as(v_baru);
  perform public.api_create_boat(jsonb_build_object('name', 'KM Demo Baru', 'engine_hp', 15, 'boat_length_m', 7, 'home_port', v_port));

  -- 2. active fisher: onboarding 30 days ago + a trip every ~4 days at the habitual cell
  perform pg_temp.act_as(v_aktif);
  perform public.api_create_boat(jsonb_build_object('name', 'KM Demo Aktif', 'engine_hp', 20, 'boat_length_m', 8, 'home_port', v_port));
  perform pg_temp.trip(v_aktif, 0, 'onboarding', 30, array[v_habit], 26, 38);
  for d in 1..7 loop
    perform pg_temp.trip(v_aktif, d, 'manual', 30 - d * 4, array[v_habit], 22 + d % 3, 30 + d * 2);
  end loop;

  -- 3. crowd: 20 fishers on the same coral cells for three weeks
  for i in 1..20 loop
    v_n := v_crowd[i];
    perform pg_temp.act_as(v_n);
    perform public.api_create_boat(jsonb_build_object('engine_hp', 10 + i % 15, 'boat_length_m', 6 + i % 4, 'home_port', v_port));
    perform pg_temp.trip(v_n, 0, 'onboarding', 21, array[v_hot[1 + i % 3]], 18 + i % 5, 35 + i % 7);
    for d in 1..7 loop
      perform pg_temp.trip(v_n, d, 'manual', 21 - d * 3 + i % 2, array[v_hot[1 + (i + d) % 3]], 18 + (i + d) % 6, 30 + (i * d) % 15);
    end loop;
  end loop;

  -- 4. quota zone: 12 trips this month, 42.5 kg each -> 510 of 600 kg used
  if v_month_days >= 1 then
    for i in 1..12 loop
      perform pg_temp.trip(v_crowd[i], 100 + i, 'manual', 1 + (i - 1) % v_month_days, array[v_quota[1 + i % 4]], 20, 42.5);
    end loop;
  else
    raise notice 'First day of the month: the quota zone stays empty until tomorrow';
  end if;

  -- 5. one violating trip in the rehab zone (education stat, not a penalty)
  perform pg_temp.trip(v_crowd[20], 200, 'manual', 5, array[v_rehab[3]], 19, 25);

  -- rehab cells have been quiet for a month: the daily job turns that into a reopen suggestion
  update public.grid_stats set days_low_fatigue = 29 where grid_id = any(v_rehab);
  perform set_config('request.jwt.claims', '', true);
  perform private.daily_refresh();
end;
$$;

commit;

-- Summary for the demo operator
select u.email, u.phone, p.role, p.full_name,
       (select count(*) from public.trips t where t.user_id = u.id) as trips
from auth.users u join public.profiles p on p.id = u.id
where u.email like '%@demo.reefish.app' and (u.email not like 'demo-n%' or u.email like 'demo-n01%')
order by u.email;
