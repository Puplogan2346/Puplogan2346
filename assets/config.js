/*
 * Workday Checklist — configuration
 * ----------------------------------
 * PLUG-AND-PLAY SETUP (for cloud accounts, sync, and sharing):
 *
 *   1. Create a free project at https://supabase.com
 *   2. In the project: SQL Editor → paste the contents of supabase/schema.sql → Run
 *   3. Project Settings → API → copy the "Project URL" and the "anon public" key
 *   4. Paste them below and save.
 *
 * The anon key is SAFE to ship publicly — Row Level Security (defined in
 * schema.sql) is what actually protects each user's data. This is the standard
 * Supabase pattern for static / front-end apps.
 *
 * Leave these blank to run in LOCAL mode: everything works offline in this
 * browser with no login (great for trying it out or single-device use).
 */
window.WC_CONFIG = {
  supabaseUrl: "https://olvorvnqamkwtxvdenxo.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9sdm9ydm5xYW1rd3R4dmRlbnhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0MzAyMTksImV4cCI6MjA5NjAwNjIxOX0.MSM3taj0e5KBbFG88gikRtmVn0qUF0c7uVo43beTuAY",

  // Optional: site name shown in the header.
  appName: "Workday Checklist",

  // Optional: enable push reminders that fire even when the app is closed.
  // Paste your VAPID *public* key here (see README → "Push reminders" for how to
  // generate keys and deploy the reminder function). Leave blank to keep
  // reminders in-tab only.
  vapidPublicKey: "BJ8LvooPsrtEL6QA5_ral6ChVbYxTR20LRXOdlnccReHwZSftVXa8ha9bKW3qDjCmmIbNpeiX01JpdjjaWdeXPA",
};
