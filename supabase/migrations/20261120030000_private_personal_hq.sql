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

-- The hardened RPCs arrive in the next migration. Keep this initial schema
-- private and read-only if migrations are applied one at a time.
revoke all on public.personal_hq_tasks, public.personal_hq_habits,
  public.personal_hq_habit_logs, public.personal_hq_moments from anon, authenticated;
grant select on public.personal_hq_tasks, public.personal_hq_habits,
  public.personal_hq_habit_logs, public.personal_hq_moments to authenticated;