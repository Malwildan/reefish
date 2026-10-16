-- Profile phone from Supabase native phone auth (frontend/mobile: signUp/signInWithPassword with phone + SMS OTP).
-- Supabase stores auth.users.phone in E.164 without the leading "+", any country (the mobile app has a country picker).
alter table public.profiles
  add column phone text unique check (phone ~ '^[1-9][0-9]{7,14}$');

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- role is never taken from signup metadata, so users cannot self-promote
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    nullif(ltrim(coalesce(new.phone, new.raw_user_meta_data ->> 'phone'), '+'), '')
  );
  return new;
end;
$$;

-- Keep the profile phone in sync when the user changes or confirms a number later
create function public.handle_user_phone_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set phone = nullif(ltrim(new.phone, '+'), '') where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_phone_changed
  after update of phone on auth.users
  for each row when (old.phone is distinct from new.phone)
  execute function public.handle_user_phone_change();

revoke execute on function public.handle_user_phone_change() from public, anon, authenticated;
