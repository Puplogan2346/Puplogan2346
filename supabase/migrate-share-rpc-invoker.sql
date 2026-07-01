-- Silence the last Supabase linter warning (lint 0029) for share_list_by_email.
-- Run once in Supabase → SQL Editor. Safe to re-run. (Also folded into schema.sql.)
--
-- The share RPC was SECURITY DEFINER, which the linter flags as callable by
-- signed-in users. It doesn't need elevated privileges: the caller must be the
-- list owner, and RLS already lets an owner read profiles (to resolve the email)
-- and insert into list_shares. Switching to SECURITY INVOKER keeps sharing
-- working and clears the warning.

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

-- Signed-in users only, never anonymous (CREATE OR REPLACE keeps grants, but be explicit).
revoke all on function public.share_list_by_email(uuid, text, text) from public, anon;
grant execute on function public.share_list_by_email(uuid, text, text) to authenticated;
