-- Lock down profile-directory access while preserving owner-managed sharing.
-- Apply after the base schema in supabase/schema.sql has been deployed.

begin;

-- Profiles contain email addresses. Do not let authenticated users enumerate
-- the table merely to support list sharing.
alter table public.profiles enable row level security;
revoke all on table public.profiles from anon, authenticated;

drop policy if exists profiles_read on public.profiles;
drop policy if exists profiles_select_self on public.profiles;
drop policy if exists profiles_update on public.profiles;
drop policy if exists profiles_update_self on public.profiles;

-- The current client does not query profiles directly. These self-only grants
-- preserve a future safe path for displaying or editing a user's own name.
grant select (id, display_name) on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;

create policy profiles_select_self
on public.profiles
for select
to authenticated
using (id = (select auth.uid()));

create policy profiles_update_self
on public.profiles
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

-- Keep the privileged email lookup and member-list join behind tightly scoped
-- RPCs. The caller must own the target list. No RPC returns an unbounded
-- directory of profiles.
create or replace function public.get_list_shares(target_list uuid)
returns table (
  shared_with uuid,
  role text,
  email text,
  display_name text
)
language sql
security definer
set search_path = ''
stable
as $$
  select s.shared_with, s.role, p.email, p.display_name
  from public.list_shares as s
  join public.profiles as p on p.id = s.shared_with
  where s.list_id = target_list
    and exists (
      select 1
      from public.lists as l
      where l.id = target_list
        and l.owner = (select auth.uid())
    )
  order by p.email;
$$;

revoke all on function public.get_list_shares(uuid) from public, anon;
grant execute on function public.get_list_shares(uuid) to authenticated;

-- Harden the existing sharing RPC with the same least-privilege boundary.
create or replace function public.share_list_by_email(
  target_list uuid,
  target_email text,
  target_role text default 'editor'
)
returns public.list_shares
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user uuid;
  result public.list_shares;
begin
  if coalesce(target_role, 'editor') not in ('editor', 'viewer') then
    raise exception 'Invalid sharing role.';
  end if;

  if not exists (
    select 1
    from public.lists as l
    where l.id = target_list
      and l.owner = (select auth.uid())
  ) then
    raise exception 'You are not permitted to share this list.';
  end if;

  select p.id
  into target_user
  from public.profiles as p
  where lower(p.email) = lower(trim(target_email));

  if target_user is null then
    raise exception 'No account was found for that email address.';
  end if;

  insert into public.list_shares (list_id, shared_with, role)
  values (target_list, target_user, coalesce(target_role, 'editor'))
  on conflict (list_id, shared_with) do update
    set role = excluded.role
  returning * into result;

  return result;
end;
$$;

revoke all on function public.share_list_by_email(uuid, text, text) from public, anon;
grant execute on function public.share_list_by_email(uuid, text, text) to authenticated;

commit;
