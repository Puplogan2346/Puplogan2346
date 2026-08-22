-- Replace the public SECURITY DEFINER sharing RPC with an authenticated Edge
-- Function. The Edge Function uses a server-only key only after proving that
-- the caller owns the target list through an RLS-scoped client.

begin;

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
alter table public.security_audit_events enable row level security;

-- Existing projects may retain Supabase's broad default table grants. Revoke
-- them and add back only the browser operations used by the application.
revoke all on table public.profiles, public.lists, public.list_shares,
  public.tasks, public.templates, public.history, public.security_audit_events
  from anon, authenticated;

grant select (id, email, display_name) on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;
grant select, insert, update, delete on table public.lists, public.tasks,
  public.templates, public.history to authenticated;
grant select, delete on table public.list_shares to authenticated;

-- Direct list-share writes now belong to the Edge Function's server-side path.
drop policy if exists shares_write on public.list_shares;
drop policy if exists shares_insert on public.list_shares;
drop policy if exists shares_update on public.list_shares;
drop policy if exists shares_delete on public.list_shares;
create policy shares_delete on public.list_shares
  for delete to authenticated using (
    exists (
      select 1 from public.lists as l
      where l.id = list_id and l.owner = (select auth.uid())
    )
  );

-- The user-authenticated Edge Function replaces this public privileged API.
revoke all on function public.share_list_by_email(uuid, text, text)
  from public, anon, authenticated;
drop function if exists public.share_list_by_email(uuid, text, text);

commit;
