# TODO: Finish push-reminders setup (Edge Function deploy + cron)

All push-reminder **code** is merged to `main` (PR #10) and the live site is up at
<https://puplogan2346.github.io/Puplogan2346/>. What's left is the backend wiring,
which needs the Supabase CLI. This doc tracks the remaining steps so they can be
done later.

## Background

- Front-end (service worker `push`/`notificationclick`, `store.js` subscribe logic,
  `app.js` 🔔 Reminders button) is live.
- The VAPID **public** key is already committed in `assets/config.js`.
- The Edge Function lives at `supabase/functions/send-reminders/index.ts`.
- Until the steps below are done, reminders fall back to **in-tab only** (they fire
  while the app is open in a tab). Nothing is broken in the meantime.

## VAPID keys

- **Public key** (already in `config.js`, safe to share):
  `BJ8LvooPsrtEL6QA5_ral6ChVbYxTR20LRXOdlnccReHwZSftVXa8ha9bKW3qDjCmmIbNpeiX01JpdjjaWdeXPA`
- **Private key:** intentionally **NOT stored in this repo** (it's a public repo).
  It was delivered in the Claude Code chat session. Set it as a Supabase secret
  (step 2) and never commit it. If lost, regenerate the pair with
  `npx web-push generate-vapid-keys` and update the public key in `config.js` to match.

## Remaining steps

- [ ] **1. Run the push migration** (Supabase → SQL Editor) — creates
  `push_subscriptions`, `tasks.notified_at`, `profiles.timezone`. Idempotent.
  Source: [`supabase/migrate-push.sql`](../supabase/migrate-push.sql).

  ```sql
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
    for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
  ```

- [ ] **2. Set the function secrets.** Install the CLI (`npm i -g supabase`), then
  `supabase login` and `supabase link --project-ref olvorvnqamkwtxvdenxo`. Paste the
  **private** key from the chat session in place of `<PRIVATE_KEY_FROM_CHAT>`:

  ```bash
  supabase secrets set \
    VAPID_PUBLIC_KEY="BJ8LvooPsrtEL6QA5_ral6ChVbYxTR20LRXOdlnccReHwZSftVXa8ha9bKW3qDjCmmIbNpeiX01JpdjjaWdeXPA" \
    VAPID_PRIVATE_KEY="<PRIVATE_KEY_FROM_CHAT>" \
    VAPID_SUBJECT="mailto:collin.brown@rho.co"
  ```

  (`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.)

- [ ] **3. Deploy the function:**

  ```bash
  supabase functions deploy send-reminders
  ```

- [ ] **4. Schedule it** every 5 minutes — Supabase → **Database → Cron** (or
  Integrations → Cron), calling the function URL on `*/5 * * * *`:

  ```
  https://olvorvnqamkwtxvdenxo.supabase.co/functions/v1/send-reminders
  ```

- [ ] **5. Turn it on & test** — open the app, tap **🔔 Reminders**, grant
  permission, create a task due in ~1 minute, and confirm a push arrives with the
  app closed. (After step 1 you can subscribe even before the function is deployed;
  pushes start once steps 2–4 are done.)

## Notes

- Reminders are sent to the **owner** of each list, in their saved timezone.
  Shared-collaborator reminders are a future enhancement.
- Full prose docs are in the [README](../README.md) under
  "Push reminders that fire when the app is closed."
- The Edge Function + live push round-trip couldn't be exercised in CI, so step 5
  is the first real runtime test. If anything misfires, capture the browser console
  and the function logs (`supabase functions logs send-reminders`) for debugging.
