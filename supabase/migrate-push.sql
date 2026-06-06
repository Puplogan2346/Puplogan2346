-- Upgrade for push reminders (fire even when the app is closed).
-- Run once in Supabase → SQL Editor. Safe to re-run. (Also in schema.sql.)

alter table public.tasks    add column if not exists notified_at timestamptz;
alter table public.profiles add column if not exists timezone text;

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;
drop policy if exists push_own on public.push_subscriptions;
create policy push_own on public.push_subscriptions
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
