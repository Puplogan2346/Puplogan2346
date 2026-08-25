# Supabase Security and Migration Runbook

**Applies to:** Puplogan2346 Workday Checklist / DayDash  
**Database project:** `workday-checklist` (`olvorvnqamkwtxvdenxo`)  
**Owner:** Repository maintainers  
**Review cadence:** Weekly automated verification and after every schema, policy, function, or Edge Function change.

## 1. Purpose and current security boundary

This runbook keeps database changes reproducible and prevents regressions in Row Level Security (RLS), grants, database functions, and server-side sharing flows.

The current boundary is deliberate:

| Surface | Intended access |
|---|---|
| `profiles` | A signed-in user can read their own profile and profiles already shared on lists they own. The application does not expose a global profile directory. |
| `lists`, `tasks`, `templates`, `history` | Signed-in owners and authorized members receive only the operations allowed by the table-specific RLS policy. |
| `list_shares` | Signed-in users can inspect only their own share rows or rows for lists they own. Owners can remove a share. Browser clients do not directly add or update share rows. |
| `security_audit_events` | Server-only. `anon` and `authenticated` are denied by an explicit no-access policy. |
| Sharing workflow | The authenticated `share-list` Edge Function performs recipient lookup and server-side writes after it proves the caller owns the list. It uses JWT verification. |
| Member listing | `get_list_shares(target_list)` is a `SECURITY INVOKER` function with `search_path = ''`; it remains constrained by the caller’s RLS rights. |

> **Core rule:** A grant decides whether a role may attempt an operation. An RLS policy decides which rows that operation may reach. Every exposed table requires both layers. [1]

## 2. Source of truth

All database changes belong in versioned files under `supabase/migrations/`. Never treat a dashboard-only SQL edit as the final source of truth. If an urgent live change is necessary, capture the exact idempotent migration immediately afterward and merge it through review.

The baseline security migrations are:

| Migration | Purpose |
|---|---|
| `20260822183000_lock_down_profile_directory.sql` | Replaces broad profile reads with a restricted profile policy and creates the member-list RPC. |
| `20260822184000_scope_member_list_access.sql` | Makes member listing run with caller privileges and limits member profile access to list owners. |
| `20260822193000_replace_share_rpc_with_edge_function.sql` | Removes the public privileged sharing RPC, restricts direct list-share writes, and creates the audit-log table. |
| `20260822194000_mark_audit_log_server_only.sql` | Makes the audit log explicitly inaccessible to browser roles. |

Keep the bootstrap schema, migrations, client code, tests, and Edge Function source aligned. A migration is incomplete if the client still calls a retired RPC or reads data through a policy the migration removes.

## 3. Required process for every database change

### Step 1: Classify the data and caller

Before writing SQL, specify the table, columns, and operations required by each caller. Treat `anon`, `authenticated`, server-side code, database triggers, and Edge Functions as separate callers. Record whether the table is browser-readable, browser-writable, or server-only.

For a new exposed table, start from no browser access. Enable RLS, revoke the default client-role privileges, and grant back only the operations the application actually uses. [1]

### Step 2: Implement grant and policy together

Use a migration that does all of the following in one reviewable change:

```sql
alter table public.example enable row level security;
revoke all on table public.example from anon, authenticated;
grant select, insert on table public.example to authenticated;

create policy example_select_own
on public.example
for select
to authenticated
using (owner_id = (select auth.uid()));

create policy example_insert_own
on public.example
for insert
to authenticated
with check (owner_id = (select auth.uid()));
```

Use separate policies for `select`, `insert`, `update`, and `delete` when the access conditions differ. For updates, include both `using` and `with check` so a caller cannot reassign ownership through the modified row. [1]

### Step 3: Select the right server-side boundary

Use a client-callable database function only when the operation is naturally data-centric and can safely execute as the caller. Prefer `SECURITY INVOKER`, which is the default. A client-callable `SECURITY DEFINER` function is an exception and requires a written justification, a fixed empty `search_path`, fully schema-qualified relations, explicit privilege revocation, and narrow re-grants. [2]

Use an authenticated Edge Function when an operation needs service-role access, recipient lookup before an RLS relationship exists, external APIs, or audit logging. Keep service-role credentials inside the function environment. The browser must not receive them.

### Step 4: Test allow and deny paths

Run the repository test suite:

```bash
npm test
```

For policy changes, add or update database-level tests under `supabase/tests/` where available. Test at least these cases:

| Case | Expected result |
|---|---|
| `anon` caller | No access unless a feature is intentionally public. |
| Owner | Can perform the minimum intended operations. |
| Authorized member | Can perform only the operations granted by their role. |
| Unrelated authenticated user | Cannot see or modify another user’s data. |
| Server-side workflow | Can perform its documented operation without broadening browser access. |

A denied RLS `using` clause often returns zero rows rather than an error. Test both the denied operation and the fact that the intended row remains unchanged. [1]

### Step 5: Deploy and verify

Apply database DDL as a named migration. Deploy any related Edge Function in the same release window. Then confirm all of the following before closing the change:

1. The live migration inventory contains the new migration.
2. Every new public table has RLS enabled.
3. Browser-role grants match the documented operations.
4. Policies do not use broad `USING (true)` access for private data.
5. Retired functions and policies are actually removed.
6. The Security Advisor reports no unexpected security finding.
7. The relevant Edge Function is active and verifies JWTs when invoked by the browser.
8. The repository pull request is merged only after the source tests pass.

## 4. Policy design rules

Use `to authenticated` or `to anon` explicitly. Do not rely on a policy’s default role scope. Keep policy names descriptive and operation-specific, such as `tasks_select_member` or `shares_delete_owner`.

Use `(select auth.uid())` rather than repeatedly calling `auth.uid()` directly inside a row predicate. It allows Postgres to evaluate the identity once per statement where the expression is safe to cache. [1]

Do not expose a directory of emails, identities, or user metadata merely to make sharing convenient. Use a narrowly authenticated server-side workflow for recipient lookup. Keep audit tables server-only unless there is a specific user-facing requirement.

Do not create views over protected data without checking their security mode. In supported Postgres versions, a browser-facing view must use `security_invoker = true` or have client-role access revoked. [1]

## 5. Function and Edge Function rules

| Rule | Required practice |
|---|---|
| Database functions | Prefer `SECURITY INVOKER`. |
| `SECURITY DEFINER` functions | Set `search_path = ''`, schema-qualify relations, revoke `PUBLIC` execution, and grant only the narrowly intended role. |
| Trigger and event-trigger functions | Confirm `anon` and `authenticated` have no execute privilege. |
| Edge Functions | Require JWT verification for browser calls, verify authorization before any service-role work, validate inputs, and record safe audit events. |
| Logging | Do not log email addresses, access tokens, service-role credentials, or full request bodies. Store a stable hash for recipient audit events where appropriate. |

## 6. Weekly verification

A weekly Monday 09:00 America/Los_Angeles read-only verification is scheduled in Manus. It checks the merged source, live migration record, RLS coverage, policies, grants, privileged functions, the active `share-list` Edge Function, the Security Advisor, and repository tests. It does not change GitHub or Supabase.

Treat a weekly failure as a security event when it reports any of the following:

| Finding | Severity | First response |
|---|---:|---|
| RLS disabled on an exposed table | High | Restrict client-role grants and restore RLS through an emergency migration. |
| Global profile read or broad private-data policy | High | Revoke broad access, identify exposed rows, and replace the policy. |
| Browser-callable `SECURITY DEFINER` function without a documented exception | High | Revoke execution first, then redesign the workflow. |
| Missing or inactive sharing Edge Function | High if sharing is live | Disable the corresponding UI action until the server-side path is restored. |
| Unexpected advisor warning | Medium to High | Triage the policy, grant, view, or function before the next feature release. |
| Source and live migration drift | Medium | Stop further schema work and reconcile the drift in a reviewed migration. |

## 7. Incident response

If an RLS regression or data exposure is suspected:

1. Record the time, affected table, role, policy, and deployment that introduced the change.
2. Contain browser access first by revoking the relevant `anon` or `authenticated` grants or disabling the client route.
3. Preserve evidence. Do not delete logs or rewrite migration history during initial triage.
4. Deploy the smallest reviewed corrective migration that restores the intended boundary.
5. Re-run the live RLS audit, Security Advisor, and targeted allow/deny tests.
6. Rotate credentials only if a secret or server-role credential may have been exposed. A policy-only incident does not automatically require key rotation.
7. Add a regression test and a short incident note to the pull request.

## 8. Release checklist

- [ ] Migration is present in `supabase/migrations/`.
- [ ] RLS, grants, and policies are reviewed together.
- [ ] Client code does not retain a retired direct query or RPC.
- [ ] New or changed browser paths have allow and deny tests.
- [ ] `npm test` passes.
- [ ] Security Advisor is reviewed after deployment.
- [ ] Live migration record matches source.
- [ ] Any function or Edge Function has an explicit authorization model.
- [ ] The weekly verification remains active.

## References

[1]: https://supabase.com/docs/guides/database/postgres/row-level-security "Supabase: Row Level Security"
[2]: https://supabase.com/docs/guides/database/functions "Supabase: Database Functions"
[3]: https://supabase.com/docs/guides/database/database-advisors "Supabase: Database Advisors"
