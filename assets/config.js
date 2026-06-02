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
  supabaseUrl: "",
  supabaseAnonKey: "",

  // Optional: site name shown in the header.
  appName: "Workday Checklist",
};
