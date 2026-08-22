-- The audit log has no client grants. This explicit deny policy documents the
-- server-only boundary and prevents an ambiguous no-policy advisor finding.

begin;

drop policy if exists security_audit_events_no_direct_access on public.security_audit_events;
create policy security_audit_events_no_direct_access on public.security_audit_events
  for all to anon, authenticated using (false) with check (false);

commit;
