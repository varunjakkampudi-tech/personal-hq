-- Owner-private routines, check-ins and life-log snapshot.
-- Keep this state separate from task revisions; clients write only through CAS.

create table if not exists public.personal_hq_lifestyle_state (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  schema_version integer not null check (schema_version = 1),
  state jsonb not null check (
    jsonb_typeof(state) = 'object' and
    jsonb_typeof(state -> 'habits') = 'array' and
    jsonb_typeof(state -> 'habitLog') = 'object' and
    jsonb_typeof(state -> 'moments') = 'array' and
    octet_length(convert_to(state::text, 'UTF8')) <= 1048576
  ),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0)
);

alter table public.personal_hq_lifestyle_state enable row level security;
drop policy if exists personal_hq_lifestyle_state_owner on public.personal_hq_lifestyle_state;
create policy personal_hq_lifestyle_state_owner on public.personal_hq_lifestyle_state
  for select to authenticated
  using (owner_id = (select auth.uid()));

revoke all on public.personal_hq_lifestyle_state from public, anon, authenticated;
grant select on public.personal_hq_lifestyle_state to authenticated;

create or replace function personal_hq_internal.save_personal_hq_lifestyle_state(
  p_expected_revision bigint,
  p_schema_version integer,
  p_state jsonb
)
returns table(schema_version integer, state jsonb, revision bigint, updated_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := (select auth.uid());
  v_row public.personal_hq_lifestyle_state%rowtype;
  v_entry jsonb;
  v_value jsonb;
  v_key text;
begin
  if v_owner_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'Expected revision must be zero or greater' using errcode = '22023';
  end if;
  if p_schema_version is distinct from 1 then
    raise exception 'Unsupported lifestyle state schema version' using errcode = '22023';
  end if;
  if p_state is null or jsonb_typeof(p_state) is distinct from 'object' or
     jsonb_typeof(p_state -> 'habits') is distinct from 'array' or
     jsonb_typeof(p_state -> 'habitLog') is distinct from 'object' or
     jsonb_typeof(p_state -> 'moments') is distinct from 'array' or
     octet_length(convert_to(p_state::text, 'UTF8')) > 1048576 then
    raise exception 'Invalid or oversized lifestyle state' using errcode = '22023';
  end if;

  for v_entry in select value from jsonb_array_elements(p_state -> 'habits') loop
    if jsonb_typeof(v_entry) is distinct from 'object' or
       jsonb_typeof(v_entry -> 'name') is distinct from 'string' or
       length(v_entry ->> 'name') > 240 then
      raise exception 'Invalid routine name' using errcode = '22023';
    end if;
  end loop;

  for v_key, v_value in select key, value from jsonb_each(p_state -> 'habitLog') loop
    if v_key !~ '^\d{4}-\d{2}-\d{2}$' or jsonb_typeof(v_value) is distinct from 'object' then
      raise exception 'Invalid routine check-in date' using errcode = '22023';
    end if;
    if exists (
      select 1 from jsonb_each(v_value) as checkin(key, value)
      where checkin.key !~ '^\d{1,3}$' or jsonb_typeof(checkin.value) is distinct from 'boolean'
    ) then
      raise exception 'Invalid routine check-in value' using errcode = '22023';
    end if;
  end loop;

  for v_entry in select value from jsonb_array_elements(p_state -> 'moments') loop
    if jsonb_typeof(v_entry) is distinct from 'object' or
       jsonb_typeof(v_entry -> 'id') is distinct from 'string' or length(v_entry ->> 'id') > 120 or
       jsonb_typeof(v_entry -> 'title') is distinct from 'string' or length(v_entry ->> 'title') > 140 or
       jsonb_typeof(v_entry -> 'kind') is distinct from 'string' or length(v_entry ->> 'kind') > 40 or
       jsonb_typeof(v_entry -> 'date') is distinct from 'string' or (v_entry ->> 'date') !~ '^\d{4}-\d{2}-\d{2}$' or
       (v_entry ? 'note' and jsonb_typeof(v_entry -> 'note') not in ('string', 'null')) or
       length(coalesce(v_entry ->> 'note', '')) > 1000 or
       (v_entry ? 'createdAt' and jsonb_typeof(v_entry -> 'createdAt') not in ('string', 'null')) or
       length(coalesce(v_entry ->> 'createdAt', '')) > 40 then
      raise exception 'Invalid life-log entry' using errcode = '22023';
    end if;
  end loop;

  if p_expected_revision = 0 then
    insert into public.personal_hq_lifestyle_state as s (
      owner_id, schema_version, state, revision
    ) values (v_owner_id, p_schema_version, p_state, 1)
    on conflict (owner_id) do nothing
    returning s.* into v_row;
  else
    update public.personal_hq_lifestyle_state as s
    set schema_version = p_schema_version,
        state = p_state,
        updated_at = now(),
        revision = s.revision + 1
    where s.owner_id = v_owner_id
      and s.revision = p_expected_revision
    returning s.* into v_row;
  end if;

  if v_row.owner_id is null then
    return;
  end if;
  return query select v_row.schema_version, v_row.state, v_row.revision, v_row.updated_at;
end;
$$;

revoke all on function personal_hq_internal.save_personal_hq_lifestyle_state(bigint, integer, jsonb) from public, anon, authenticated;
grant execute on function personal_hq_internal.save_personal_hq_lifestyle_state(bigint, integer, jsonb) to authenticated;

create or replace function public.save_personal_hq_lifestyle_state(
  p_expected_revision bigint,
  p_schema_version integer,
  p_state jsonb
)
returns table(schema_version integer, state jsonb, revision bigint, updated_at timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select * from personal_hq_internal.save_personal_hq_lifestyle_state(
    p_expected_revision, p_schema_version, p_state
  );
$$;

revoke all on function public.save_personal_hq_lifestyle_state(bigint, integer, jsonb) from public, anon;
grant execute on function public.save_personal_hq_lifestyle_state(bigint, integer, jsonb) to authenticated;
