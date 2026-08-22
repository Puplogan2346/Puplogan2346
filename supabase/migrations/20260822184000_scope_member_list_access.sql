-- Remove the unnecessary SECURITY DEFINER member-list RPC.
-- Owners can read only their own profile plus recipients already shared on lists
-- they own; the member-list RPC can therefore run under caller privileges.

begin;

revoke all on table public.profiles from anon, authenticated;

drop policy if exists profiles_select_self on public.profiles;
drop policy if exists profiles_select_self_or_owned_share on public.profiles;

grant select (id, email, display_name) on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;

create policy profiles_select_self_or_owned_share
on public.profiles
for select
to authenticated
using (
  id = (select auth.uid())
  or exists (
    select 1
    from public.list_shares as s
    join public.lists as l on l.id = s.list_id
    where s.shared_with = profiles.id
      and l.owner = (select auth.uid())
  )
);

create or replace function public.get_list_shares(target_list uuid)
returns table (
  shared_with uuid,
  role text,
  email text,
  display_name text
)
language sql
security invoker
set search_path = ''
stable
as $$
  select s.shared_with, s.role, p.email, p.display_name
  from public.list_shares as s
  join public.profiles as p on p.id = s.shared_with
  where s.list_id = target_list
  order by p.email;
$$;

revoke all on function public.get_list_shares(uuid) from public, anon;
grant execute on function public.get_list_shares(uuid) to authenticated;

commit;
