// Supabase Edge Function: send-reminders
// ----------------------------------------------------------------------------
// Sends web-push notifications for tasks that are due "now" (in each user's own
// timezone) and haven't been notified yet. Intended to run on a schedule (e.g.
// every 5 minutes) via Supabase's scheduled functions or pg_cron + pg_net.
//
// Reminders are sent to the OWNER of each list (using the owner's saved
// timezone). Shared collaborators getting their own reminders is a future
// enhancement.
//
// Required secrets (set with `supabase secrets set`):
//   SUPABASE_URL                 - your project URL
//   SUPABASE_SERVICE_ROLE_KEY    - service role key (bypasses RLS; keep secret)
//   VAPID_PUBLIC_KEY             - VAPID public key (same one in assets/config.js)
//   VAPID_PRIVATE_KEY            - VAPID private key (keep secret)
//   VAPID_SUBJECT                - a "mailto:you@example.com" contact
//
// Deploy:  supabase functions deploy send-reminders
// ----------------------------------------------------------------------------
import { createClient } from "jsr:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE_KEY")!;
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@example.com";

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);

const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });

// Current HH:MM in a given IANA timezone (24h).
function nowHHMM(tz: string): string {
  try {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: tz, hour: "2-digit", minute: "2-digit", hour12: false,
    }).formatToParts(new Date());
    const h = parts.find((p) => p.type === "hour")?.value ?? "00";
    const m = parts.find((p) => p.type === "minute")?.value ?? "00";
    return `${h}:${m}`;
  } catch {
    return new Date().toISOString().slice(11, 16);
  }
}

Deno.serve(async () => {
  // 1) Everyone who has at least one push subscription.
  const { data: subs, error: subErr } = await admin
    .from("push_subscriptions")
    .select("user_id, endpoint, p256dh, auth");
  if (subErr) return json({ error: subErr.message }, 500);
  if (!subs?.length) return json({ sent: 0, note: "no subscriptions" });

  // Group subscriptions by user.
  const byUser = new Map<string, typeof subs>();
  for (const s of subs) {
    if (!byUser.has(s.user_id)) byUser.set(s.user_id, []);
    byUser.get(s.user_id)!.push(s);
  }

  let sent = 0;
  for (const [userId, userSubs] of byUser) {
    // Owner's timezone (default UTC).
    const { data: prof } = await admin.from("profiles").select("timezone").eq("id", userId).single();
    const tz = prof?.timezone || "UTC";
    const cutoff = nowHHMM(tz);

    // Lists this user owns.
    const { data: lists } = await admin.from("lists").select("id").eq("owner", userId);
    const listIds = (lists ?? []).map((l) => l.id);
    if (!listIds.length) continue;

    // Due, not-done, not-yet-notified tasks whose time has arrived.
    const { data: due } = await admin
      .from("tasks")
      .select("id, text, due, note, list_id")
      .in("list_id", listIds)
      .eq("done", false)
      .is("notified_at", null)
      .neq("due", "")
      .lte("due", cutoff);
    if (!due?.length) continue;

    for (const task of due) {
      const payload = JSON.stringify({
        title: "⏰ " + task.text,
        body: task.note || ("Due at " + task.due),
        tag: "wc-" + task.id,
        url: "./index.html",
      });
      // Push to every device this user has.
      await Promise.all(userSubs.map(async (s) => {
        try {
          await webpush.sendNotification(
            { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
            payload,
          );
          sent++;
        } catch (e: any) {
          // 404/410 = expired subscription; clean it up.
          if (e?.statusCode === 404 || e?.statusCode === 410) {
            await admin.from("push_subscriptions").delete().eq("endpoint", s.endpoint);
          }
        }
      }));
      // Mark notified so we don't push it again.
      await admin.from("tasks").update({ notified_at: new Date().toISOString() }).eq("id", task.id);
    }
  }

  return json({ sent });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
