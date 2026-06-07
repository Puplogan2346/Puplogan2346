-- Performance hardening for RLS policies (Supabase linter 0003 + 0006).
-- Run once in Supabase → SQL Editor. Safe to re-run. (Also folded into schema.sql.)
--
-- These are PERFORMANCE warnings only — access control is unchanged.
--   1) auth_rls_initplan (0003): wrap auth.uid() in (select auth.uid()) so the
--      planner evaluates it once per query instead of once per row.
--   2) multiple_permissive_policies (0006): the FOR ALL write policies also
--      covered SELECT, so two permissive policies ran on every read. Split them
--      into INSERT / UPDATE / DELETE so SELECT is governed by one policy only.

-- profiles --------------------------------------------------------------------
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated using (id = (select auth.uid()));

-- lists -----------------------------------------------------------------------
drop policy if exists lists_insert on public.lists;
create policy lists_insert on public.lists
  for insert to authenticated with check (owner = (select auth.uid()));
drop policy if exists lists_update on public.lists;
create policy lists_update on public.lists
  for update to authenticated using (owner = (select auth.uid()));
drop policy if exists lists_delete on public.lists;
create policy lists_delete on public.lists
  for delete to authenticated using (owner = (select auth.uid()));

-- list_shares: wrap auth.uid(), and split FOR ALL into per-action policies -----
drop policy if exists shares_select on public.list_shares;
create policy shares_select on public.list_shares
  for select to authenticated using (
    shared_with = (select auth.uid())
    or exists (select 1 from public.lists l where l.id = list_id and l.owner = (select auth.uid()))
  );
drop policy if exists shares_write on public.list_shares;
drop policy if exists shares_insert on public.list_shares;
create policy shares_insert on public.list_shares
  for insert to authenticated with check (
    exists (select 1 from public.lists l where l.id = list_id and l.owner = (select auth.uid()))
  );
drop policy if exists shares_update on public.list_shares;
create policy shares_update on public.list_shares
  for update to authenticated using (
    exists (select 1 from public.lists l where l.id = list_id and l.owner = (select auth.uid()))
  ) with check (
    exists (select 1 from public.lists l where l.id = list_id and l.owner = (select auth.uid()))
  );
drop policy if exists shares_delete on public.list_shares;
create policy shares_delete on public.list_shares
  for delete to authenticated using (
    exists (select 1 from public.lists l where l.id = list_id and l.owner = (select auth.uid()))
  );

-- tasks: split writes per action (SELECT stays governed by can_access_list) ----
drop policy if exists tasks_write on public.tasks;
drop policy if exists tasks_insert on public.tasks;
create policy tasks_insert on public.tasks
  for insert to authenticated with check (private.can_edit_list(list_id));
drop policy if exists tasks_update on public.tasks;
create policy tasks_update on public.tasks
  for update to authenticated
  using (private.can_edit_list(list_id)) with check (private.can_edit_list(list_id));
drop policy if exists tasks_delete on public.tasks;
create policy tasks_delete on public.tasks
  for delete to authenticated using (private.can_edit_list(list_id));

-- templates -------------------------------------------------------------------
drop policy if exists templates_write on public.templates;
drop policy if exists templates_insert on public.templates;
create policy templates_insert on public.templates
  for insert to authenticated with check (private.can_edit_list(list_id));
drop policy if exists templates_update on public.templates;
create policy templates_update on public.templates
  for update to authenticated
  using (private.can_edit_list(list_id)) with check (private.can_edit_list(list_id));
drop policy if exists templates_delete on public.templates;
create policy templates_delete on public.templates
  for delete to authenticated using (private.can_edit_list(list_id));

-- history ---------------------------------------------------------------------
drop policy if exists history_write on public.history;
drop policy if exists history_insert on public.history;
create policy history_insert on public.history
  for insert to authenticated with check (private.can_edit_list(list_id));
drop policy if exists history_update on public.history;
create policy history_update on public.history
  for update to authenticated
  using (private.can_edit_list(list_id)) with check (private.can_edit_list(list_id));
drop policy if exists history_delete on public.history;
create policy history_delete on public.history
  for delete to authenticated using (private.can_edit_list(list_id));

-- push_subscriptions: wrap auth.uid() (only if the push table exists yet) ------
do $$
begin
  if to_regclass('public.push_subscriptions') is not null then
    drop policy if exists push_own on public.push_subscriptions;
    create policy push_own on public.push_subscriptions
      for all to authenticated
      using (user_id = (select auth.uid()))
      with check (user_id = (select auth.uid()));
  end if;
end $$;
