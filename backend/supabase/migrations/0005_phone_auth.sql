-- Phone + password auth: the phone (normalised 62…) lives in profiles; auth.users holds a synthetic email.
alter table public.profiles
  add column phone text unique check (phone ~ '^62[0-9]{8,13}$');

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- role is never taken from signup metadata, so users cannot self-promote
  insert into public.profiles (id, full_name, phone)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'phone');
  return new;
end;
$$;
