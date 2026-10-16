-- FCM sender support (12.B.10): the Edge Function push-dispatch claims queued pushes, sends them,
-- and reports back. Recipient rule moves to private.push_recipients so the count at queue time and
-- the tokens at send time use the same rule.

alter table public.push_outbox drop constraint push_outbox_status_check;
alter table public.push_outbox add constraint push_outbox_status_check
  check (status in ('queued', 'sending', 'sent', 'failed'));
alter table public.push_outbox add column claimed_at timestamptz;

-- Fishers who should hear about a zone: default boat's home port within range_km of the outline,
-- or a fishing point inside the zone in the last recent_fishing_days.
create function private.push_recipients(p_zone uuid)
returns setof uuid
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  with c as (select private.config('push') as v),
       z as (select outline from zones where id = p_zone and outline is not null)
  select b.user_id from boats b, z, c
  where b.is_default and b.deleted_at is null
    and st_dwithin(b.home_port, z.outline::geography, (c.v ->> 'range_km')::float8 * 1000)
  union
  select t.user_id from fishing_points f join trips t on t.id = f.trip_id, z, c
  where t.departed_at >= now() - make_interval(days => (c.v ->> 'recent_fishing_days')::int)
    and st_intersects(f.location, z.outline::geography);
$$;

create or replace function private.queue_push(p_zone uuid, p_change text, p_version bigint)
returns int
language plpgsql
set search_path = public, extensions, pg_temp
as $$
declare
  v_c jsonb := private.config('push');
  v_count int;
begin
  if not exists (select 1 from zones where id = p_zone and outline is not null) then
    return 0;
  end if;
  select count(distinct d.user_id) into v_count
  from user_devices d
  where d.user_id in (select private.push_recipients(p_zone));

  update push_outbox set change = p_change, heatmap_version = p_version, recipient_count = v_count
  where zone_id = p_zone and status = 'queued'
    and created_at > now() - make_interval(mins => (v_c ->> 'coalesce_minutes')::int);
  if not found then
    insert into push_outbox (zone_id, change, heatmap_version, recipient_count)
    values (p_zone, p_change, p_version, v_count);
  end if;
  return v_count;
end;
$$;

-- Claims up to p_limit queued pushes for sending. Rows stuck in 'sending' (sender crashed) for
-- 10 minutes go back to the queue first. Concurrent senders never claim the same row.
create function public.api_internal_push_claim(p_limit int default 20)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_out jsonb;
begin
  update push_outbox set status = 'queued'
  where status = 'sending' and claimed_at < now() - interval '10 minutes';

  with picked as (
    select id from push_outbox
    where status = 'queued'
    order by created_at
    limit least(greatest(coalesce(p_limit, 20), 1), 100)
    for update skip locked
  ), claimed as (
    update push_outbox o set status = 'sending', attempts = attempts + 1, claimed_at = now()
    from picked where o.id = picked.id
    returning o.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'change', c.change, 'heatmap_version', c.heatmap_version,
      'zone', jsonb_build_object('id', z.id, 'name', z.name, 'status', z.status),
      'tokens', coalesce((select jsonb_agg(d.fcm_token) from user_devices d
                          where d.user_id in (select private.push_recipients(c.zone_id))), '[]'::jsonb))
    order by c.created_at), '[]'::jsonb)
  into v_out
  from claimed c left join zones z on z.id = c.zone_id;
  return v_out;
end;
$$;

-- Reports a claimed push. 'failed' goes back to the queue until 3 attempts. Tokens FCM rejected as
-- UNREGISTERED / INVALID_ARGUMENT are removed so they are not tried again.
create function public.api_internal_push_done(p_id bigint, p_status text, p_invalid_tokens text[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row push_outbox;
  v_removed int;
begin
  if p_status not in ('sent', 'failed') then
    perform private.fail('VALIDATION_ERROR', 'status harus sent atau failed');
  end if;
  delete from user_devices where fcm_token = any(coalesce(p_invalid_tokens, '{}'));
  get diagnostics v_removed = row_count;

  update push_outbox set
    status = case when p_status = 'sent' then 'sent' when attempts < 3 then 'queued' else 'failed' end,
    sent_at = case when p_status = 'sent' then now() end
  where id = p_id and status = 'sending'
  returning * into v_row;
  if v_row.id is null then
    perform private.fail('PUSH_NOT_SENDING', 'Push tidak sedang dikirim');
  end if;
  return jsonb_build_object('id', v_row.id, 'status', v_row.status, 'attempts', v_row.attempts,
    'tokens_removed', v_removed);
end;
$$;

revoke execute on function public.api_internal_push_claim(int), public.api_internal_push_done(bigint, text, text[])
from public, anon, authenticated;
grant execute on function public.api_internal_push_claim(int), public.api_internal_push_done(bigint, text, text[])
to service_role;
