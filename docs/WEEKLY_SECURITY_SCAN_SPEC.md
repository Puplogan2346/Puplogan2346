# Weekly Puplogan2346 Security and RLS Verification

**Schedule:** Every Monday at 09:00 America/Los_Angeles  
**Scope:** `Puplogan2346/Puplogan2346` and the `workday-checklist` Supabase project (`olvorvnqamkwtxvdenxo`)  
**Mode:** Read-only. The task does not apply migrations, edit policies, deploy functions, alter credentials, or change GitHub state.

## 1. Purpose

This weekly check detects drift between the merged repository source and the live Supabase security boundary. It is a verification and escalation mechanism, not an automated remediation system. Any failed control is reported with evidence, severity, and a safe next action for human approval.

## 2. Exact check sequence

| Step | Evidence collected | Pass condition | Failure condition |
|---|---|---|---|
| 1. Source baseline | Default branch, current commit, migration filenames, current test result | Source is readable and tests pass. | Source cannot be read or tests fail. |
| 2. Migration reconciliation | Source migration filenames and live Supabase migration records | Each expected security migration is recorded live, with no unexplained drift. | A source migration is missing live, or a live migration is undocumented. |
| 3. RLS coverage | `relrowsecurity` for each public application table | Every exposed application table has RLS enabled. | Any exposed application table has RLS disabled. |
| 4. Policy scope | Public-table policy name, operation, role, `USING`, and `WITH CHECK` expressions | Policies match the documented ownership and member-access model. | A broad private-data read, unexpected role, or missing deny/ownership condition appears. |
| 5. Browser grants | `anon` and `authenticated` table and column privileges | Client roles have only required operations. | A new, broad, or unexplained grant appears. |
| 6. Function exposure | Function security mode, fixed search path, result type, and client execution privilege | Browser-callable functions are intentionally scoped; trigger functions are not browser-executable. | An unexpected callable privileged function or unsafe search path appears. |
| 7. Edge Function boundary | `share-list` status and JWT requirement | Function is `ACTIVE` and `verify_jwt` is `true`. | Function is missing, inactive, or accepts unauthenticated requests. |
| 8. Supabase advisor | Security Advisor lints | No unexpected security lint remains. | Any new security lint appears. |
| 9. Report and evidence | Timestamp, source commit, summarized result, and sanitized evidence | A complete PASS/FAIL report is produced. | An incomplete run is marked `INCONCLUSIVE`, never `PASS`. |

## 3. Logging rules

The scan logs metadata and access-control evidence, not application records. It must never log user emails, profile rows, tasks, access tokens, service-role credentials, request bodies, or audit-event contents.

| Log field | Example | Purpose |
|---|---|---|
| `run_id` | `weekly-2026-08-25-0900-PT` | Links summary and evidence. |
| `started_at` and `finished_at` | ISO 8601 timestamps | Establishes the observation window. |
| `source_commit` | Short default-branch SHA | Identifies the source baseline. |
| `migration_status` | `4 expected / 4 live / PASS` | Detects source-to-live drift. |
| `rls_status` | `7 exposed tables / 7 RLS-enabled / PASS` | Confirms RLS coverage. |
| `policy_status` | `21 policies reviewed / PASS` | Captures policy-scope review. |
| `grant_status` | `No unexpected anon/authenticated grants / PASS` | Captures privilege review. |
| `function_status` | `1 client callable invoker; 2 privileged triggers not executable by client roles / PASS` | Captures function exposure review. |
| `edge_function_status` | `share-list ACTIVE, JWT required / PASS` | Confirms server-side sharing boundary. |
| `advisor_status` | `0 security lints / PASS` | Captures advisor result. |
| `test_status` | `npm test passed / PASS` | Captures application regression result. |

## 4. Baseline evidence log

The scheduled task has not yet reached its first Monday run. The following manually collected baseline uses the same read-only checks and is the reference point for future drift detection.

```text
run_id: baseline-2026-08-25-1729-PT
mode: READ_ONLY
repository: Puplogan2346/Puplogan2346
project: workday-checklist

[PASS] source_migrations
  expected: 4
  live: 4
  names:
    - lock_down_profile_directory
    - scope_member_list_access
    - replace_share_rpc_with_edge_function
    - mark_audit_log_server_only

[PASS] rls_coverage
  public_application_tables: 7
  rls_enabled: 7
  tables: history, list_shares, lists, profiles, security_audit_events, tasks, templates

[PASS] policy_scope
  policies_reviewed: 21
  profiles: self_or_owned_share read; self-only update
  list_shares: member-or-owner read; owner-only delete
  security_audit_events: explicit deny-all for anon and authenticated

[PASS] browser_grants
  anon: no application-table grants observed
  authenticated: only documented task, list, history, template, share-read/delete, and column-scoped profile operations

[PASS] function_exposure
  client_callable: get_list_shares(uuid), SECURITY INVOKER, empty search path, authenticated only
  trigger_only: handle_new_user(), not executable by anon or authenticated
  event_trigger_only: rls_auto_enable(), not executable by anon or authenticated

[PASS] edge_function
  name: share-list
  status: ACTIVE
  verify_jwt: true

[PASS] security_advisor
  lints: 0

[PASS] source_tests
  command: npm test
  result: all tests passed

overall: PASS
```

## 5. Required weekly report format

Every scheduled run should deliver this format. Do not claim `PASS` when any required check is unavailable.

```markdown
# Weekly Puplogan2346 Security and RLS Verification

**Status:** PASS | FAIL | INCONCLUSIVE  
**Run:** <run_id>  
**Observed:** <timestamp in America/Los_Angeles>  
**Source:** <default branch and short commit SHA>  
**Mode:** Read-only

## Executive result

<One sentence: no drift detected, or the specific control that failed.>

| Control | Result | Evidence | Severity if failed |
|---|---|---|---|
| Source and tests | PASS/FAIL/INCONCLUSIVE | <test command and result> | Medium |
| Migration reconciliation | PASS/FAIL/INCONCLUSIVE | <expected count versus live count> | Medium |
| RLS coverage | PASS/FAIL/INCONCLUSIVE | <enabled count versus exposed count> | High |
| Policy scope | PASS/FAIL/INCONCLUSIVE | <affected table and policy only> | High |
| Browser grants | PASS/FAIL/INCONCLUSIVE | <role and unexpected operation only> | High |
| Function exposure | PASS/FAIL/INCONCLUSIVE | <function name and safety property> | High |
| Edge Function | PASS/FAIL/INCONCLUSIVE | <status and JWT setting> | High |
| Security Advisor | PASS/FAIL/INCONCLUSIVE | <lint IDs or zero findings> | Medium to High |

## Drift and remediation

<If PASS: “No drift detected. No action required.”>

<If FAIL: list only the affected control, severity, safe next action, and whether human approval is required. Do not change production during this run.>

## Sanitized evidence log

```text
<Metadata and policy/grant/function summaries only. Never include user rows, emails, tokens, or credentials.>
```
```

## 6. Escalation rules

| Result | Required response |
|---|---|
| `PASS` | Deliver the summary and retain sanitized evidence in the task record. |
| `INCONCLUSIVE` | State which check could not run, mark the result as inconclusive, and request a rerun or access review. |
| High-severity `FAIL` | Report immediately. Do not auto-remediate. Recommend a reviewed emergency migration or temporary client-access containment. |
| Medium-severity `FAIL` | Open a remediation plan before the next feature release. |

## References

[1]: https://supabase.com/docs/guides/database/postgres/row-level-security "Supabase: Row Level Security"
[2]: https://supabase.com/docs/guides/database/functions "Supabase: Database Functions"
[3]: https://supabase.com/docs/guides/database/database-advisors "Supabase: Database Advisors"
