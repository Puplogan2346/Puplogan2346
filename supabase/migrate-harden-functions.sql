-- Harden SECURITY DEFINER functions flagged by the Supabase database linter.
-- Run once in Supabase → SQL Editor. Safe to re-run. (Also folded into schema.sql.)
--
-- Why: the linter (lints 0028/0029) warns that SECURITY DEFINER functions in the
-- exposed `public` schema are callable as REST RPCs by anon / authenticated.
-- Your data is still protected (every function gates on auth.uid() and RLS is on),
-- but we tighten the surface here:
--
--   * can_access_list / can_edit_list are used INSIDE RLS policies, so signed-in
--     users must keep EXECUTE. We move them to a `private` schema that PostgREST
--     does NOT expose, so they vanish from the REST API while RLS keeps using them.
--   * handle_new_user is a trigger function — nothing should call it via the API.
--   * share_list_by_email stays callable by signed-in users (that's its purpose)
--     but never by anonymous callers.

-- ---------------------------------------------------------------------------
-- 1) Private schema for internal RLS helpers (not in PostgREST's exposed list).
-- ---------------------------------------------------------------------------
create schema if not exists private;

create or replace function private.can_access_list(target uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.lists l where l.id = target and l.owner = auth.uid())
      or exists (select 1 from public.list_shares s where s.list_id = target and s.shared_with = auth.uid());
$$;

create or replace function private.can_edit_list(target uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.lists l where l.id = target and l.owner = auth.uid())
      or exists (select 1 from public.list_shares s
                 where s.list_id = target and s.shared_with = auth.uid() and s.role = 'editor');
$$;

-- Only signed-in users (whose queries trigger RLS) need these; never anon/PUBLIC.
revoke all on function private.can_access_list(uuid) from public;
revoke all on function private.can_edit_list(uuid) from public;
grant execute on function private.can_access_list(uuid) to authenticated;
grant execute on function private.can_edit_list(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Repoint every policy that used the public helpers at the private ones.
-- ---------------------------------------------------------------------------
drop policy if exists lists_select on public.lists;
create policy lists_select on public.lists
  for select to authenticated using (private.can_access_list(id));

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
-- 3) Drop the public (PostgREST-exposed) copies now that nothing references them.
-- ---------------------------------------------------------------------------
drop function if exists public.can_access_list(uuid);
drop function if exists public.can_edit_list(uuid);

-- ---------------------------------------------------------------------------
-- 4) Lock down the remaining SECURITY DEFINER functions in public.
-- ---------------------------------------------------------------------------
-- Trigger function: fires on auth.users insert; never called over the API.
revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Share RPC: signed-in users only, never anonymous.
revoke all on function public.share_list_by_email(uuid, text, text) from public, anon;
grant execute on function public.share_list_by_email(uuid, text, text) to authenticated;

-- If a stray Supabase helper named rls_auto_enable() exists, lock it down too.
do $$
begin
  if exists (
    select 1 from pg_proc
    where proname = 'rls_auto_enable' and pronamespace = 'public'::regnamespace
  ) then
    execute 'revoke all on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end $$;
