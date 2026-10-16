-- api_admin_refresh_heatmap becomes asynchronous. A full refresh takes about as long as the
-- authenticated role's statement_timeout (8 s on Supabase), so calling it from the admin web was
-- cancelled. The RPC now only queues a job; pg_cron (as postgres, no timeout) runs it within
-- ~10 seconds and the client polls api_admin_refresh_status.

-- Runs one queued job. A failure is recorded on the job; its partial work is rolled back.
create function private.run_refresh_job(p_job uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_job heatmap_refresh_jobs;
  v_targets text[];
  v_version bigint;
  v_changed int;
begin
  update heatmap_refresh_jobs set status = 'running', started_at = clock_timestamp(), progress_pct = 0
  where id = p_job and status = 'queued'
  returning * into v_job;
  if v_job.id is null then
    return;
  end if;
  if v_job.scope = 'grids' then
    v_targets := array(select jsonb_array_elements_text(v_job.params -> 'grid_ids'));
  elsif v_job.scope = 'zone' then
    v_targets := array(select grid_id from zone_grids where zone_id = (v_job.params ->> 'zone_id')::uuid);
  end if;

  begin
    perform private.recompute_stats(v_targets);
    perform private.auto_flag(v_targets, false);
    v_version := private.publish(v_targets, 'manual', trim(v_job.params ->> 'reason'));
    select changed_cells into v_changed from heatmap_versions where version = v_version;
    update heatmap_refresh_jobs set
      status = 'done', progress_pct = 100, result_version = v_version, changed_cells = v_changed, finished_at = clock_timestamp()
    where id = p_job;
  exception when others then
    update heatmap_refresh_jobs set status = 'failed', error = sqlerrm, finished_at = clock_timestamp() where id = p_job;
  end;
end;
$$;

-- Called by pg_cron. Jobs left 'running' for 15 minutes (worker died) are marked failed first.
create function private.process_refresh_jobs(p_max int default 5)
returns int
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_n int := 0;
begin
  update heatmap_refresh_jobs set status = 'failed', error = 'timeout: worker stopped', finished_at = now()
  where status = 'running' and started_at < now() - interval '15 minutes';
  for v_id in
    select id from heatmap_refresh_jobs where status = 'queued' order by created_at limit p_max
  loop
    perform private.run_refresh_job(v_id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

create or replace function public.api_admin_refresh_heatmap(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := private.require_konservatif();
  v_scope text := p ->> 'scope';
  v_params jsonb := p;
  v_job uuid;
begin
  if jsonb_typeof(p) is distinct from 'object' or coalesce(v_scope, '') not in ('all', 'grids', 'zone')
     or private.bad_text(p -> 'reason', 3, 500, true) is not null then
    perform private.fail('VALIDATION_ERROR', 'scope (all, grids, zone) dan reason (3 sampai 500 karakter) wajib diisi');
  end if;
  if v_scope = 'grids' then
    v_params := jsonb_set(p, '{grid_ids}', to_jsonb(private.grid_ids(p -> 'grid_ids', 'grid_ids', 1, 5000)));
  elsif v_scope = 'zone' then
    if private.bad_uuid(p -> 'zone_id', true) is not null
       or not exists (select 1 from zones where id = (p ->> 'zone_id')::uuid and is_active) then
      perform private.fail('ZONE_NOT_FOUND', 'Zona aktif tidak ditemukan');
    end if;
  end if;

  begin
    insert into heatmap_refresh_jobs (scope, params, status, requested_by)
    values (v_scope, v_params, 'queued', v_uid)
    returning id into v_job;
  exception when unique_violation then
    perform private.fail('REFRESH_IN_PROGRESS', 'Refresh penuh masih berjalan');
  end;
  return jsonb_build_object('status', 'queued', 'job_id', v_job, 'heatmap_version', private.current_version(),
                            'changed_cells', null, 'finished_at', null);
end;
$$;

select cron.schedule('heatmap-refresh-jobs', '10 seconds', 'select private.process_refresh_jobs()');
