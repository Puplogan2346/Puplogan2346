-- Workday Checklist — database schema
-- Run this once in your Supabase project: SQL Editor → paste → Run.
-- Safe to re-run: uses IF NOT EXISTS / CREATE OR REPLACE where possible.

-- ---------------------------------------------------------------------------
-- Profiles: one row per auth user, so we can look people up by email to share.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text unique,
  display_name text,
  created_at timestamptz not null default now()
);

-- Keep profiles in sync with auth.users automatically.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'display_name', new.email))
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Lists: a checklist a user owns. Sharing happens at the list level.
-- ---------------------------------------------------------------------------
create table if not exists public.lists (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users (id) on delete cascade,
  name text not null default 'My Day',
  created_at timestamptz not null default now()
);

-- Who a list is shared with, and what they can do.
create table if not exists public.list_shares (
  list_id uuid not null references public.lists (id) on delete cascade,
  shared_with uuid not null references auth.users (id) on delete cascade,
  role text not null default 'editor' check (role in ('editor', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (list_id, shared_with)
);

-- ---------------------------------------------------------------------------
-- Tasks.
-- ---------------------------------------------------------------------------
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.lists (id) on delete cascade,
  text text not null,
  done boolean not null default false,
  due text default '',            -- "HH:MM" local time, or empty
  note text default '',
  position double precision not null default 0,
  created_at timestamptz not null default now(),
  done_at timestamptz
);
create index if not exists tasks_list_id_idx on public.tasks (list_id);

-- ---------------------------------------------------------------------------
-- Templates: recurring tasks, per list.
-- ---------------------------------------------------------------------------
create table if not exists public.templates (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.lists (id) on delete cascade,
  text text not null,
  due text default '',
  position double precision not null default 0
);
create index if not exists templates_list_id_idx on public.templates (list_id);

-- ---------------------------------------------------------------------------
-- History: one row per list per day, for streaks & stats.
-- ---------------------------------------------------------------------------
create table if not exists public.history (
  list_id uuid not null references public.lists (id) on delete cascade,
  day date not null,
  completed int not null default 0,
  total int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (list_id, day)
);

-- Internal audit trail for the Edge Function. It stores a hash of the recipient
-- identifier rather than the raw email and is not accessible from the browser.
create table if not exists public.security_audit_events (
  id bigint generated always as identity primary key,
  actor uuid not null references auth.users (id) on delete cascade,
  action text not null check (action in ('list_share_attempt', 'list_share_success', 'list_share_rejected')),
  list_id uuid references public.lists (id) on delete set null,
  target_hash text not null,
  outcome text not null,
  occurred_at timestamptz not null default now()
);
create index if not exists security_audit_events_actor_action_time_idx
  on public.security_audit_events (actor, action, occurred_at desc);

-- ---------------------------------------------------------------------------
-- Helper: can the current user access a given list (owner or shared)?
-- ---------------------------------------------------------------------------
create or replace function public.can_access_list(target uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.lists l where l.id = target and l.owner = auth.uid()
  ) or exists (
    select 1 from public.list_shares s where s.list_id = target and s.shared_with = auth.uid()
  );
$$;

create or replace function public.can_edit_list(target uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.lists l where l.id = target and l.owner = auth.uid()
  ) or exists (
    select 1 from public.list_shares s
    where s.list_id = target and s.shared_with = auth.uid() and s.role = 'editor'
  );
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security.
-- ---------------------------------------------------------------------------
alter table public.profiles    enable row level security;
alter table public.lists       enable row level security;
alter table public.list_shares enable row level security;
alter table public.tasks       enable row level security;
alter table public.templates   enable row level security;
alter table public.history     enable row level security;
alter table public.security_audit_events enable row level security;

-- Client roles receive only the operations required by the application. The
-- Edge Function owns privileged recipient lookup and share creation.
revoke all on table public.profiles, public.lists, public.list_shares,
  public.tasks, public.templates, public.history, public.security_audit_events
  from anon, authenticated;
grant select (id, email, display_name) on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;
grant select, insert, update, delete on table public.lists, public.tasks,
  public.templates, public.history to authenticated;
grant select, delete on table public.list_shares to authenticated;
-- No client role receives any privilege on security_audit_events. The explicit
-- deny policy documents that this audit trail is server-only.
drop policy if exists security_audit_events_no_direct_access on public.security_audit_events;
create policy security_audit_events_no_direct_access on public.security_audit_events
  for all to anon, authenticated using (false) with check (false);
drop policy if exists profiles_read on public.profiles;
drop policy if exists profiles_select_self on public.profiles;
drop policy if exists profiles_select_self_or_owned_share on public.profiles;
drop policy if exists profiles_update on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
-- A user may read their own profile and profiles of people already shared on
-- lists they own. This supports member management without a global directory.
create policy profiles_select_self_or_owned_share on public.profiles
  for select to authenticated using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.list_shares as s
      join public.lists as l on l.id = s.list_id
      where s.shared_with = profiles.id
        and l.owner = (select auth.uid())
    )
  );
create policy profiles_update_self on public.profiles
  for update to authenticated using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Lists: owner full control; shared users can read.
drop policy if exists lists_select on public.lists;
create policy lists_select on public.lists
  for select to authenticated using (public.can_access_list(id));
drop policy if exists lists_insert on public.lists;
create policy lists_insert on public.lists
  for insert to authenticated with check (owner = auth.uid());
drop policy if exists lists_update on public.lists;
create policy lists_update on public.lists
  for update to authenticated using (owner = auth.uid());
drop policy if exists lists_delete on public.lists;
create policy lists_delete on public.lists
  for delete to authenticated using (owner = auth.uid());

-- List shares: the list owner manages who it's shared with; a user can see
-- shares that target them.
drop policy if exists shares_select on public.list_shares;
create policy shares_select on public.list_shares
  for select to authenticated using (
    shared_with = auth.uid()
    or exists (select 1 from public.lists l where l.id = list_id and l.owner = auth.uid())
  );
drop policy if exists shares_write on public.list_shares;
drop policy if exists shares_insert on public.list_shares;
drop policy if exists shares_update on public.list_shares;
drop policy if exists shares_delete on public.list_shares;
create policy shares_delete on public.list_shares
  for delete to authenticated using (
    exists (select 1 from public.lists l where l.id = list_id and l.owner = auth.uid())
  );

-- Tasks / templates / history: gated by list access.
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks
  for select to authenticated using (public.can_access_list(list_id));
drop policy if exists tasks_write on public.tasks;
create policy tasks_write on public.tasks
  for all to authenticated
  using (public.can_edit_list(list_id))
  with check (public.can_edit_list(list_id));

drop policy if exists templates_select on public.templates;
create policy templates_select on public.templates
  for select to authenticated using (public.can_access_list(list_id));
drop policy if exists templates_write on public.templates;
create policy templates_write on public.templates
  for all to authenticated
  using (public.can_edit_list(list_id))
  with check (public.can_edit_list(list_id));

drop policy if exists history_select on public.history;
create policy history_select on public.history
  for select to authenticated using (public.can_access_list(list_id));
drop policy if exists history_write on public.history;
create policy history_write on public.history
  for all to authenticated
  using (public.can_edit_list(list_id))
  with check (public.can_edit_list(list_id));

-- ---------------------------------------------------------------------------
-- Owner-scoped member-list RPC. Recipient lookup and share creation occur only
-- in the authenticated Edge Function, never through a public privileged RPC.
-- ---------------------------------------------------------------------------
create or replace function public.get_list_shares(target_list uuid)
returns table (shared_with uuid, role text, email text, display_name text)
language sql
security invoker
set search_path = ''
stable
as $$
  select s.shared_with, s.role, p.email, p.display_name
  from public.list_shares as s
  join public.profiles as p on p.id = s.shared_with
  where s.list_id = target_list
    and exists (
      select 1 from public.lists as l
      where l.id = target_list and l.owner = (select auth.uid())
    )
  order by p.email;
$$;
revoke all on function public.get_list_shares(uuid) from public, anon;
grant execute on function public.get_list_shares(uuid) to authenticated;

revoke all on function public.share_list_by_email(uuid, text, text)
  from public, anon, authenticated;
drop function if exists public.share_list_by_email(uuid, text, text);

-- ---------------------------------------------------------------------------
-- Realtime: make sure these tables broadcast changes.
-- (Supabase → Database → Replication also exposes them; this is idempotent.)
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    alter publication supabase_realtime add table public.tasks;
  exception when duplicate_object then null; end;
  begin
    alter publication supabase_realtime add table public.templates;
  exception when duplicate_object then null; end;
  begin
    alter publication supabase_realtime add table public.history;
  exception when duplicate_object then null; end;
end $$;
