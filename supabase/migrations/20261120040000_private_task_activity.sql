-- Owner-private, append-only task activity. The log records field names and
-- status transitions, never the contents of notes or next actions.

create table if not exists public.personal_hq_task_events (
  owner_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null default gen_random_uuid(),
  task_id text not null check (length(task_id) between 1 and 120),
  task_title text not null check (length(task_title) between 1 and 500),
  area text not null check (length(area) between 1 and 160),
  occurred_at timestamptz not null default now(),
  action text not null check (action in ('created', 'updated', 'status', 'archived', 'restored')),
  changed_fields text[] not null check (
    cardinality(changed_fields) > 0 and
    array_position(changed_fields, null) is null and
    changed_fields <@ array['title', 'area', 'due', 'status', 'next_action', 'private_context', 'archived']::text[]
  ),
  previous_status text check (previous_status is null or previous_status in ('Not started', 'In progress', 'Waiting', 'Done')),
  status text not null check (status in ('Not started', 'In progress', 'Waiting', 'Done')),
  task_revision bigint not null check (task_revision > 0),
  primary key (owner_id, event_id)
);

create index if not exists personal_hq_task_events_owner_time_idx
  on public.personal_hq_task_events (owner_id, occurred_at desc, event_id desc);

alter table public.personal_hq_task_events enable row level security;
drop policy if exists personal_hq_task_events_owner on public.personal_hq_task_events;
create policy personal_hq_task_events_owner on public.personal_hq_task_events
  for select to authenticated
  using (owner_id = (select auth.uid()));

revoke all on public.personal_hq_task_events from public, anon, authenticated;
grant select on public.personal_hq_task_events to authenticated;

create or replace function personal_hq_internal.capture_personal_hq_task_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text;
  v_fields text[] := array[]::text[];
  v_previous_status text;
begin
  if tg_op = 'INSERT' then
    v_action := 'created';
    v_fields := array['title', 'area', 'due', 'status', 'next_action', 'private_context']::text[];
  else
    if new.owner_id is distinct from old.owner_id or new.task_id is distinct from old.task_id then
      raise exception 'Task identity cannot change' using errcode = '22023';
    end if;
    if new.title is distinct from old.title then v_fields := array_append(v_fields, 'title'); end if;
    if new.area is distinct from old.area then v_fields := array_append(v_fields, 'area'); end if;
    if new.due is distinct from old.due then v_fields := array_append(v_fields, 'due'); end if;
    if new.status is distinct from old.status then v_fields := array_append(v_fields, 'status'); end if;
    if new.next_action is distinct from old.next_action then v_fields := array_append(v_fields, 'next_action'); end if;
    if new.notes is distinct from old.notes then v_fields := array_append(v_fields, 'private_context'); end if;
    if new.deleted_at is distinct from old.deleted_at then
      if new.deleted_at is null then
        v_action := 'restored';
      else
        v_action := 'archived';
      end if;
      v_fields := array_append(v_fields, 'archived');
    end if;
    if cardinality(v_fields) = 0 then
      return new;
    end if;
    if v_action is null then
      if new.status is distinct from old.status then
        v_action := 'status';
      else
        v_action := 'updated';
      end if;
    end if;
    v_previous_status := old.status;
  end if;

  insert into public.personal_hq_task_events (
    owner_id, task_id, task_title, area, occurred_at, action,
    changed_fields, previous_status, status, task_revision
  ) values (
    new.owner_id, new.task_id, new.title, new.area, new.updated_at, v_action,
    v_fields, v_previous_status, new.status, new.revision
  );
  return new;
end;
$$;

revoke all on function personal_hq_internal.capture_personal_hq_task_event() from public, anon, authenticated;

drop trigger if exists personal_hq_tasks_capture_activity on public.personal_hq_tasks;
create trigger personal_hq_tasks_capture_activity
  after insert or update on public.personal_hq_tasks
  for each row execute function personal_hq_internal.capture_personal_hq_task_event();
