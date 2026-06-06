-- Upgrade for the "smarter tasks" feature (flagged tasks + recurring templates).
-- Run this once in Supabase → SQL Editor. Safe to re-run.
--
-- (These same lines are already included in schema.sql; this file is just a
--  convenient copy-paste for an existing database.)

alter table public.tasks add column if not exists flagged boolean not null default false;
alter table public.templates add column if not exists days text not null default '';
