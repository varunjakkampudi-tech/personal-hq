-- Private Personal HQ storage for Supabase/Postgres.
-- Apply only after creating a Supabase project and reviewing its region/retention.
-- Every row is owned by auth.uid(); never expose a service-role key to Pages.

create table if not exists public.personal_hq_tasks (
  owner_id uuid not null references auth.users(id) on delete cascade,
  task_id text not null check (length(task_id) between 1 and 120),
  title text not null check (length(title) between 1 and 500),
  area text not null check (length(area) between 1 and 160),
  due date,
  status text not null check (status in ('Not started', 'In progress', 'Waiting', 'Done')),
  next_action text not null default '',
  notes text not null default '',
  owner_label text not null default '',
  source text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  primary key (owner_id, task_id)
);

create table if not exists public.personal_hq_habits (
  owner_id uuid not null references auth.users(id) on delete cascade,
  habit_id text not null check (length(habit_id) between 1 and 120),
  name text not null check (length(name) between 1 and 240),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  primary key (owner_id, habit_id)
);

create table if not exists public.personal_hq_habit_logs (
  owner_id uuid not null references auth.users(id) on delete cascade,
  log_date date not null,
  habit_id text not null check (length(habit_id) between 1 and 120),
  completed boolean not null default false,
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  primary key (owner_id, log_date, habit_id),
  foreign key (owner_id, habit_id)
    references public.personal_hq_habits(owner_id, habit_id) on delete cascade
);

create table if not exists public.personal_hq_moments (
  owner_id uuid not null references auth.users(id) on delete cascade,
  moment_id text not null check (length(moment_id) between 1 and 120),
  occurred_at timestamptz not null,
  content text not null check (length(content) between 1 and 10000),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  primary key (owner_id, moment_id)
);

alter table public.personal_hq_tasks enable row level security;
alter table public.personal_hq_habits enable row level security;
alter table public.personal_hq_habit_logs enable row level security;
alter table public.personal_hq_moments enable row level security;

-- Explicit owner-only policies. No anonymous policies are created.
drop policy if exists personal_hq_tasks_owner on public.personal_hq_tasks;
create policy personal_hq_tasks_owner on public.personal_hq_tasks
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists personal_hq_habits_owner on public.personal_hq_habits;
create policy personal_hq_habits_owner on public.personal_hq_habits
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists personal_hq_habit_logs_owner on public.personal_hq_habit_logs;
create policy personal_hq_habit_logs_owner on public.personal_hq_habit_logs
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists personal_hq_moments_owner on public.personal_hq_moments;
create policy personal_hq_moments_owner on public.personal_hq_moments
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- Compare-and-swap task save: expected revision 0 means create; otherwise update
-- only the exact revision the client read. A missing return row means a conflict.
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
language plpgsql
security invoker
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
        deleted_at = null,
        updated_at = now(),
        revision = t.revision + 1
    where t.owner_id = v_owner_id
      and t.task_id = p_task_id
      and t.revision = p_expected_revision
    returning t.* into v_row;
  end if;

  if v_row.task_id is null then
    return;
  end if;
  return query select v_row.task_id, v_row.revision, v_row.updated_at;
end;
$$;

revoke all on function public.save_personal_hq_task(text, bigint, text, text, date, text, text, text, text, text) from public, anon;
grant execute on function public.save_personal_hq_task(text, bigint, text, text, date, text, text, text, text, text) to authenticated;

create or replace function public.delete_personal_hq_task(
  p_task_id text,
  p_expected_revision bigint
)
returns table(task_id text, revision bigint, updated_at timestamptz)
language plpgsql
security invoker
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

revoke all on function public.delete_personal_hq_task(text, bigint) from public, anon;
grant execute on function public.delete_personal_hq_task(text, bigint) to authenticated;

-- No grants to anon: signed-in users only, with RLS applied to every table.
revoke all on public.personal_hq_tasks, public.personal_hq_habits,
  public.personal_hq_habit_logs, public.personal_hq_moments from anon, authenticated;
grant select, insert, update on public.personal_hq_tasks to authenticated;
grant select, insert, update, delete on public.personal_hq_habits to authenticated;
grant select, insert, update, delete on public.personal_hq_habit_logs to authenticated;
grant select, insert, update, delete on public.personal_hq_moments to authenticated;
