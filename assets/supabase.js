/*
 * Thin wrapper around the Supabase client.
 * Exposes WC.sb (the client or null) and WC.cloudEnabled.
 * The supabase-js UMD bundle is loaded from a CDN in index.html and exposes
 * a global `supabase` with createClient().
 */
(function () {
  const WC = (window.WC = window.WC || {});
  const cfg = window.WC_CONFIG || {};

  const hasConfig = !!(cfg.supabaseUrl && cfg.supabaseAnonKey);
  const hasLib = typeof window.supabase !== "undefined" && typeof window.supabase.createClient === "function";

  WC.cloudEnabled = hasConfig && hasLib;
  WC.sb = WC.cloudEnabled
    ? window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, {
        auth: { persistSession: true, autoRefreshToken: true },
      })
    : null;

  if (hasConfig && !hasLib) {
    console.warn("[Workday Checklist] Supabase config present but the supabase-js library failed to load. Running in local mode.");
  }
})();
