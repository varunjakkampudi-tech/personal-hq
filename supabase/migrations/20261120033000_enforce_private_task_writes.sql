-- Harden the initial schema: clients can read owner rows but cannot write
-- around the compare-and-swap task RPCs. SECURITY DEFINER code stays in the
-- non-exposed private schema; public functions are SECURITY INVOKER wrappers.

create schema if not exists personal_hq_internal;
revoke all on schema personal_hq_internal from public, anon, authenticated;
grant usage on schema personal_hq_internal to authenticated;

create or replace function personal_hq_internal.save_personal_hq_task(
  p_task_id text,
  p_expected_revision bigint,
  p_title text,
  p_area text,
  p_due date,
  p_status text,
  p_next_action text,
  p_notes text,
  p_owner_label text default '',
  p_source text default ''
)
returns table(task_id text, revision bigint, updated_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := (select auth.uid());
  v_row public.personal_hq_tasks%rowtype;
begin
  if v_owner_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'Expected revision must be zero or greater' using errcode = '22023';
  end if;
  if p_status not in ('Not started', 'In progress', 'Waiting', 'Done') then
    raise exception 'Unsupported task status' using errcode = '22023';
  end if;

  if p_expected_revision = 0 then
    insert into public.personal_hq_tasks as t (
      owner_id, task_id, title, area, due, status, next_action, notes,
      owner_label, source, revision
    ) values (
      v_owner_id, p_task_id, p_title, p_area, p_due, p_status, p_next_action,
      p_notes, coalesce(p_owner_label, ''), coalesce(p_source, ''), 1
    ) on conflict (owner_id, task_id) do nothing
    returning t.* into v_row;
  else
    update public.personal_hq_tasks as t
    set title = p_title,
        area = p_area,
        due = p_due,
        status = p_status,
        next_action = p_next_action,
        notes = p_notes,
        owner_label = coalesce(p_owner_label, ''),
        source = coalesce(p_source, ''),
        updated_at = now(),
        revision = t.revision + 1
    where t.owner_id = v_owner_id
      and t.task_id = p_task_id
      and t.revision = p_expected_revision
      and t.deleted_at is null
    returning t.* into v_row;
  end if;

  if v_row.task_id is null then
    return;
  end if;
  return query select v_row.task_id, v_row.revision, v_row.updated_at;
end;
$$;

create or replace function personal_hq_internal.delete_personal_hq_task(
  p_task_id text,
  p_expected_revision bigint
)
returns table(task_id text, revision bigint, updated_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := (select auth.uid());
  v_row public.personal_hq_tasks%rowtype;
begin
  if v_owner_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'Expected revision must be positive' using errcode = '22023';
  end if;

  update public.personal_hq_tasks as t
  set deleted_at = now(), updated_at = now(), revision = t.revision + 1
  where t.owner_id = v_owner_id
    and t.task_id = p_task_id
    and t.revision = p_expected_revision
    and t.deleted_at is null
  returning t.* into v_row;

  if v_row.task_id is null then
    return;
  end if;
  return query select v_row.task_id, v_row.revision, v_row.updated_at;
end;
$$;

create or replace function personal_hq_internal.restore_personal_hq_task(
  p_task_id text,
  p_expected_revision bigint
)
returns table(task_id text, revision bigint, updated_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := (select auth.uid());
  v_row public.personal_hq_tasks%rowtype;
begin
  if v_owner_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'Expected revision must be positive' using errcode = '22023';
  end if;

  update public.personal_hq_tasks as t
  set deleted_at = null, updated_at = now(), revision = t.revision + 1
  where t.owner_id = v_owner_id
    and t.task_id = p_task_id
    and t.revision = p_expected_revision
    and t.deleted_at is not null
  returning t.* into v_row;

  if v_row.task_id is null then
    return;
  end if;
  return query select v_row.task_id, v_row.revision, v_row.updated_at;
end;
$$;

revoke all on function personal_hq_internal.save_personal_hq_task(text, bigint, text, text, date, text, text, text, text, text) from public, anon, authenticated;
revoke all on function personal_hq_internal.delete_personal_hq_task(text, bigint) from public, anon, authenticated;
revoke all on function personal_hq_internal.restore_personal_hq_task(text, bigint) from public, anon, authenticated;
grant execute on function personal_hq_internal.save_personal_hq_task(text, bigint, text, text, date, text, text, text, text, text) to authenticated;
grant execute on function personal_hq_internal.delete_personal_hq_task(text, bigint) to authenticated;
grant execute on function personal_hq_internal.restore_personal_hq_task(text, bigint) to authenticated;

create or replace function public.save_personal_hq_task(
  p_task_id text,
  p_expected_revision bigint,
  p_title text,
  p_area text,
  p_due date,
  p_status text,
  p_next_action text,
  p_notes text,
  p_owner_label text default '',
  p_source text default ''
)
returns table(task_id text, revision bigint, updated_at timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select * from personal_hq_internal.save_personal_hq_task(
    p_task_id, p_expected_revision, p_title, p_area, p_due, p_status,
    p_next_action, p_notes, p_owner_label, p_source
  );
$$;

create or replace function public.delete_personal_hq_task(
  p_task_id text,
  p_expected_revision bigint
)
returns table(task_id text, revision bigint, updated_at timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select * from personal_hq_internal.delete_personal_hq_task(p_task_id, p_expected_revision);
$$;

create or replace function public.restore_personal_hq_task(
  p_task_id text,
  p_expected_revision bigint
)
returns table(task_id text, revision bigint, updated_at timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select * from personal_hq_internal.restore_personal_hq_task(p_task_id, p_expected_revision);
$$;

revoke all on function public.save_personal_hq_task(text, bigint, text, text, date, text, text, text, text, text) from public, anon;
revoke all on function public.delete_personal_hq_task(text, bigint) from public, anon;
revoke all on function public.restore_personal_hq_task(text, bigint) from public, anon;
grant execute on function public.save_personal_hq_task(text, bigint, text, text, date, text, text, text, text, text) to authenticated;
grant execute on function public.delete_personal_hq_task(text, bigint) to authenticated;
grant execute on function public.restore_personal_hq_task(text, bigint) to authenticated;

-- Keep app writes on the CAS task RPCs. Other record types remain read-only
-- until their own conflict-safe write operations are implemented.
revoke insert, update, delete on public.personal_hq_tasks,
  public.personal_hq_habits, public.personal_hq_habit_logs,
  public.personal_hq_moments from anon, authenticated;
grant select on public.personal_hq_tasks, public.personal_hq_habits,
  public.personal_hq_habit_logs, public.personal_hq_moments to authenticated;

