# CLAUDE.md

Guidance for AI assistants working in this repository.

## What this is

**Workday Checklist** — a daily task checklist that ships as a **static site with
no build step**. Plain HTML, CSS, and vanilla JavaScript (ES, no framework, no
bundler, no transpiler). It runs two ways from the exact same code:

- **Local mode** (default, zero setup): open `index.html`; all data lives in
  `localStorage`. No account, fully offline.
- **Cloud mode** (optional): add Supabase credentials to `assets/config.js` to
  get accounts, cross-device sync, live realtime updates, and list sharing.
  Which mode is active is decided at runtime by whether config + the
  supabase-js CDN library are both present.

There is no compiler involved — the files served are the files you edit.

## Repository layout

```
index.html              App shell: markup + ordered <script>/<style> includes
manifest.json           PWA manifest
sw.js                   Service worker (offline cache; bump CACHE_VERSION on asset changes)
icon.svg                App icon
package.json            Only a "test" script; no runtime dependencies
assets/
  app.css               All styling (light + dark themes via [data-theme])
  config.js             Supabase URL + anon key (blank => local mode); window.WC_CONFIG
  supabase.js           Backend bootstrap; sets WC.sb (client|null) + WC.cloudEnabled
  store.js              Data layer — single API over local + cloud backends
  history.js            Pure streak/stats helpers over history records
  auth.js               Sign-in/up modal + account bar; also defines WC.escapeHtml
  app.js                UI controller (rendering + all DOM interactions)
supabase/
  schema.sql            Tables, RLS policies, share-by-email RPC, realtime setup
tests/
  run.js                Headless Node tests for the data layer (both backends)
  fake-supabase.js      In-memory mock of the Supabase client used by tests
.github/workflows/
  ci.yml                Runs node tests/run.js on every push + PR
  pages.yml             Deploys repo root to GitHub Pages on push to main
```

## Architecture

Everything hangs off a single global namespace, `window.WC`. Scripts are plain
IIFEs that attach to it; **load order in `index.html` matters** and is:

```
supabase-js (CDN) → config.js → supabase.js → store.js → history.js → auth.js → app.js
```

Layers:

- **`WC.Store`** (`store.js`) is the heart. It exposes one uniform async API
  (addTask, updateTask, removeTask, reorder, templates, history, lists,
  sharing, auth…). The UI **never** touches `localStorage` or Supabase
  directly — only through `Store`.
  - `Store.mode` is `"local"` or `"cloud"`; `Store.cloud` is the boolean
    getter. Almost every mutation branches on `if (this.cloud) … else …`.
  - In local mode, state is held in memory and flushed via `persistLocal()` to
    `localStorage` keys (`wc_local_*`).
  - In cloud mode, mutations write to Supabase, then `reload()` re-fetches the
    current list's rows. Realtime subscriptions (`subscribeRealtime`) re-fetch
    on external changes so shared lists stay live.
  - After any change, `Store.onChange()` fires; on login/logout
    `Store.onAuthChange()` fires. `app.js` wires both to re-render.
- **`WC.History`** (`history.js`) is pure functions over
  `[{ day, completed, total }]` records — streaks and stats. Keep it
  side-effect free (it's the easiest part to unit test).
- **`WC.Auth`** (`auth.js`) owns only the auth UI; it calls `Store.signIn/Up/Out`.
  It also defines `WC.escapeHtml`, used by `app.js` when injecting user text.
- **`app.js`** is the controller: builds DOM, binds events, renders on
  `onChange`, and owns view-only concerns (theme, confetti, toasts, reminders,
  modals, filter, drag-and-drop, PWA install, export/import).

### Data model

- A **task**: `{ id, text, done, due, note, createdAt, doneAt }`. `due` is a
  `"HH:MM"` local-time string or `""`.
- A **template**: a recurring task `{ id, text, due }`, applied per day.
- **History**: one record per day, `{ day: "YYYY-MM-DD", completed, total }`.
  A day is "perfect" (counts toward a streak) when `total > 0 && completed >= total`.
- **Cloud only**: data is scoped to a **list** (`Store.currentListId`). Lists
  can be shared by email with `editor`/`viewer` roles. `Store.canEdit` is false
  for viewers, which disables mutating UI. Local mode has a single implicit list.

Cloud rows use snake_case columns (`done_at`, `list_id`, `created_at`);
`normalizeTask()` in `store.js` maps DB rows back to the in-memory camelCase
shape. Keep that mapping in sync when changing the schema.

## Development workflow

- **Run locally**: serve over http (not `file://`) so the service worker and
  PWA register, e.g. `python3 -m http.server` then open the printed URL.
- **No build, no install** for the app itself — there are no runtime npm deps.
- **Tests**: `npm test` (alias for `node tests/run.js`). They stub the few
  browser globals the store needs and exercise **both** backends — local
  (real `localStorage` stub) and cloud (the in-memory `fake-supabase.js`).
  These are the primary safety net; the UI is not unit-tested.
- **CI** (`ci.yml`) runs the tests on every push and PR. Keep them green.
- **Deploy**: pushing to `main` triggers `pages.yml`, which publishes the repo
  root to GitHub Pages (no build, `path: "."`).

### When you change things — checklist

- **Data-layer change** (`store.js`/`history.js`): add or update an assertion in
  `tests/run.js`, and if it's cloud behavior, make sure `fake-supabase.js`
  supports the query/RPC you use. Run `npm test`.
- **Add/remove/rename an asset file**: update the `<script>`/`<link>` includes
  in `index.html` **and** the `ASSETS` array in `sw.js`, and **bump
  `CACHE_VERSION`** in `sw.js` so clients pick up the change.
- **Schema change** (`supabase/schema.sql`): keep it idempotent
  (`if not exists` / `create or replace`), and remember RLS — every table is
  gated by `can_access_list` / `can_edit_list`. The anon key is public *by
  design*; RLS is the actual protection. Update `normalizeTask` and the cloud
  read/write paths in `store.js` to match.
- **New mutation**: implement both branches (cloud writes + `reload()`; local
  `persistLocal()`), call `onChange()`, and respect `Store.canEdit`.

## Conventions

- Vanilla JS only. No frameworks, no new build tooling, no npm runtime
  dependencies. The "no build step" property is a core feature — preserve it.
- Each asset file is an IIFE that reads/writes `window.WC`. Match the existing
  terse, single-purpose style and the section-header comment banners.
- Always escape user-provided text with `WC.escapeHtml` before putting it in
  `innerHTML` (see `app.js` modal builders).
- Mutating actions should be undoable where the UI already does so (toasts with
  an undo callback) — see `snapshot()`/`undoRemoval()` in `app.js`.
- Keep `history.js` pure (no DOM, no storage) so it stays trivially testable.
- 2-space indentation; double-quoted strings; semicolons.

## Git / PR workflow

- Develop on the branch you were assigned for the task; create it locally if
  needed. Don't push to other branches without explicit permission.
- Commit with clear messages. After pushing, open a **draft** PR if none exists.
- Be sparing with GitHub comments — only when genuinely useful.
