# Workday Checklist

A plug-and-play checklist to track your work day. It runs as a **static site**
(no build step) and works two ways:

- **Local mode** (default, zero setup) — open `index.html` and everything is
  saved in your browser. No login, fully offline.
- **Cloud mode** (optional) — add your free [Supabase](https://supabase.com)
  keys and you get **accounts, cross-device sync, and shareable lists** so you
  can keep Work and Personal separate by simply signing into different accounts.

## Features

- Add / complete / edit (double-click) / delete tasks, with **undo** on deletes
- Reorder by drag handle or ▲▼ buttons (touch-friendly)
- **Due times** with overdue highlighting and optional browser **reminders**
- **Per-task notes**
- **Daily templates** — recurring tasks you can apply in one click or each new day
- **Start a new day** carries unfinished tasks forward and clears completed ones
- **History & streaks** — perfect-day tracking and a 14-day chart
- **Accounts, sync & sharing** (cloud mode) — share a list with someone by email; edits sync live
- **Sign in with Google** (one tap) or email + password
- **Password reset by email** and a live **sync status** indicator (cloud mode)
- Light/dark theme, keyboard shortcut (`/` to focus), accessibility-minded (focus-trapped dialogs, `Esc` to close)
- Installable **PWA** with proper home-screen icons and offline support
- **Export / import** JSON backups

## Run locally

Just open `index.html` in a browser. (For the PWA/service worker to register,
serve over http — e.g. `python3 -m http.server` — rather than `file://`.)

## Enable cloud accounts, sync & sharing

1. Create a free project at <https://supabase.com>.
2. In the project, open **SQL Editor**, paste the contents of
   [`supabase/schema.sql`](supabase/schema.sql), and click **Run**. This creates
   the tables, Row Level Security policies, and the share-by-email function.
3. Open **Project Settings → API** and copy the **Project URL** and the
   **anon public** key.
4. Paste both into [`assets/config.js`](assets/config.js):

   ```js
   window.WC_CONFIG = {
     supabaseUrl: "https://YOUR-PROJECT.supabase.co",
     supabaseAnonKey: "YOUR-ANON-KEY",
     appName: "Workday Checklist",
   };
   ```

5. (Optional) In Supabase **Authentication → Providers**, decide whether email
   confirmation is required. With it off, sign-up logs you straight in.
6. For **password reset** links to work, add your site URL under Supabase
   **Authentication → URL Configuration** (Site URL and Redirect URLs) — e.g.
   `https://<user>.github.io/<repo>/`. The “Forgot password?” link emails a
   reset link back to the app, which then prompts for a new password.

The anon key is meant to be public — Row Level Security in `schema.sql` is what
protects each account's data.

### Enable "Sign in with Google" (optional)

The app shows a **Continue with Google** button automatically; it only works
once Google is configured as a provider:

1. In **Google Cloud Console** → APIs & Services → **Credentials**, create an
   **OAuth client ID** (type *Web application*).
2. Under **Authorized redirect URIs**, add your Supabase callback:
   `https://YOUR-PROJECT.supabase.co/auth/v1/callback`.
3. Copy the **Client ID** and **Client secret** into Supabase →
   **Authentication → Providers → Google**, and enable it.
4. Make sure your site URL is in Supabase → **Authentication → URL
   Configuration** (Site URL + Redirect URLs), e.g.
   `https://<user>.github.io/<repo>/`, so Google can return you to the app.

Google sign-in brings over the account's name and profile photo. No Google
app-verification review is needed for basic sign-in.

### Using Work vs Personal

Create two accounts (e.g. your work and personal emails) and sign into whichever
you need. Each account has its own lists, tasks, templates, and history. To
collaborate, open a list, click **👥 Share**, and enter the other person's
account email.

## Host it (shareable URL)

A GitHub Actions workflow ([`.github/workflows/pages.yml`](.github/workflows/pages.yml))
deploys the site to **GitHub Pages** on every push to `main`. Enable it once:

> Repository **Settings → Pages → Build and deployment → Source: GitHub Actions**.

Your app will be live at `https://<user>.github.io/<repo>/`, which is also what
makes the PWA installable and enables cloud login.

## Tests

The data layer is covered by headless tests that exercise **both** backends
(local storage and a mock of Supabase):

```
npm test        # or: node tests/run.js
```

CI runs them on every push and pull request
([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

## Project layout

```
index.html              App shell (markup + script/style includes)
assets/app.css          Styles (light + dark themes)
assets/config.js        Your Supabase keys (or blank for local mode)
assets/supabase.js      Backend client bootstrap
assets/store.js         Data layer — local + cloud backends behind one API
assets/auth.js          Sign in / sign up UI
assets/history.js       Streak & stats helpers
assets/app.js           UI controller (rendering + interactions)
supabase/schema.sql     Database tables, RLS policies, share RPC
manifest.json, sw.js    PWA manifest + offline service worker
icon.svg, icon-*.png    App icons (scalable + PNG/maskable for installs)
apple-touch-icon.png    iOS home-screen icon
tools/generate_icons.py Regenerates the PNG icons from the SVG artwork
```
