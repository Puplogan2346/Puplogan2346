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
  flagged boolean not null default false,
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
  days text default '',           -- comma list of weekdays 0..6 (Sun..Sat); empty = every day
  position double precision not null default 0
);
create index if not exists templates_list_id_idx on public.templates (list_id);

-- Upgrades for existing databases (safe to re-run).
alter table public.tasks add column if not exists flagged boolean not null default false;
alter table public.templates add column if not exists days text not null default '';

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

-- ---------------------------------------------------------------------------
-- Helper: can the current user access a given list (owner or shared)?
-- These are SECURITY DEFINER (they read lists/list_shares past RLS) and are used
-- INSIDE the policies below, so they live in a `private` schema that PostgREST
-- does NOT expose — they must not be callable as REST RPCs (linter 0028/0029).
-- Signed-in users still get EXECUTE so RLS can evaluate them.
-- ---------------------------------------------------------------------------
create schema if not exists private;

create or replace function private.can_access_list(target uuid)
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

create or replace function private.can_edit_list(target uuid)
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

revoke all on function private.can_access_list(uuid) from public;
revoke all on function private.can_edit_list(uuid) from public;
grant execute on function private.can_access_list(uuid) to authenticated;
grant execute on function private.can_edit_list(uuid) to authenticated;

-- Drop any older public copies (pre-hardening) now that policies use private.*.
drop function if exists public.can_access_list(uuid);
drop function if exists public.can_edit_list(uuid);

-- ---------------------------------------------------------------------------
-- Row Level Security.
-- ---------------------------------------------------------------------------
alter table public.profiles    enable row level security;
alter table public.lists       enable row level security;
alter table public.list_shares enable row level security;
alter table public.tasks       enable row level security;
alter table public.templates   enable row level security;
alter table public.history     enable row level security;

-- Profiles: anyone signed in can look up profiles (needed to share by email);
-- you may only edit your own.
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated using (true);
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated using (id = auth.uid());

-- Lists: owner full control; shared users can read.
drop policy if exists lists_select on public.lists;
create policy lists_select on public.lists
  for select to authenticated using (private.can_access_list(id));
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
create policy shares_write on public.list_shares
  for all to authenticated using (
    exists (select 1 from public.lists l where l.id = list_id and l.owner = auth.uid())
  ) with check (
    exists (select 1 from public.lists l where l.id = list_id and l.owner = auth.uid())
  );

-- Tasks / templates / history: gated by list access.
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks
  for select to authenticated using (private.can_access_list(list_id));
drop policy if exists tasks_write on public.tasks;
create policy tasks_write on public.tasks
  for all to authenticated
  using (private.can_edit_list(list_id))
  with check (private.can_edit_list(list_id));

drop policy if exists templates_select on public.templates;
create policy templates_select on public.templates
  for select to authenticated using (private.can_access_list(list_id));
drop policy if exists templates_write on public.templates;
create policy templates_write on public.templates
  for all to authenticated
  using (private.can_edit_list(list_id))
  with check (private.can_edit_list(list_id));

drop policy if exists history_select on public.history;
create policy history_select on public.history
  for select to authenticated using (private.can_access_list(list_id));
drop policy if exists history_write on public.history;
create policy history_write on public.history
  for all to authenticated
  using (private.can_edit_list(list_id))
  with check (private.can_edit_list(list_id));

-- ---------------------------------------------------------------------------
-- RPC: share a list with someone by email (returns the new share row).
-- SECURITY INVOKER: the caller must be the list owner anyway, and RLS already
-- lets an owner read profiles (to resolve the email) and write list_shares, so
-- no elevated privileges are needed. Keeping it INVOKER avoids the linter's
-- SECURITY DEFINER warning (lint 0029).
-- ---------------------------------------------------------------------------
create or replace function public.share_list_by_email(target_list uuid, target_email text, target_role text default 'editor')
returns public.list_shares
language plpgsql
security invoker set search_path = public
as $$
declare
  target_user uuid;
  result public.list_shares;
begin
  if not exists (select 1 from public.lists l where l.id = target_list and l.owner = auth.uid()) then
    raise exception 'Only the list owner can share it.';
  end if;

  select id into target_user from public.profiles where lower(email) = lower(target_email);
  if target_user is null then
    raise exception 'No account found for %', target_email;
  end if;

  insert into public.list_shares (list_id, shared_with, role)
  values (target_list, target_user, coalesce(target_role, 'editor'))
  on conflict (list_id, shared_with) do update set role = excluded.role
  returning * into result;

  return result;
end;
$$;

-- Lock down EXECUTE on the functions in the exposed schema.
-- Trigger function: fires on auth.users insert; never called over the API.
revoke all on function public.handle_new_user() from public, anon, authenticated;
-- Share RPC: signed-in users only, never anonymous.
revoke all on function public.share_list_by_email(uuid, text, text) from public, anon;
grant execute on function public.share_list_by_email(uuid, text, text) to authenticated;

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
