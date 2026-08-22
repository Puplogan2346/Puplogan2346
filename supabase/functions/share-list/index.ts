import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;
const RATE_LIMIT_MAX_ATTEMPTS = 10;
const EMAIL_MAX_LENGTH = 320;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type ShareRequest = {
  targetList?: unknown;
  targetEmail?: unknown;
  targetRole?: unknown;
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function parseRequest(value: ShareRequest) {
  const targetList = typeof value.targetList === "string" ? value.targetList.trim() : "";
  const targetEmail = typeof value.targetEmail === "string" ? value.targetEmail.trim().toLowerCase() : "";
  const targetRole = typeof value.targetRole === "string" ? value.targetRole : "editor";

  if (!UUID_PATTERN.test(targetList)) throw new Error("invalid_list");
  if (!targetEmail || targetEmail.length > EMAIL_MAX_LENGTH || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(targetEmail)) {
    throw new Error("invalid_email");
  }
  if (targetRole !== "editor" && targetRole !== "viewer") throw new Error("invalid_role");

  return { targetList, targetEmail, targetRole };
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function getKey(variableName: string): string {
  const raw = Deno.env.get(variableName);
  if (!raw) throw new Error(`Missing ${variableName}`);
  const parsed = JSON.parse(raw) as Record<string, string>;
  if (!parsed.default) throw new Error(`Missing default key in ${variableName}`);
  return parsed.default;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  if (!authorization) return json({ error: "Unauthorized" }, 401);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    if (!supabaseUrl) throw new Error("Missing SUPABASE_URL");

    const publishableKey = getKey("SUPABASE_PUBLISHABLE_KEYS");
    const secretKey = getKey("SUPABASE_SECRET_KEYS");
    const userClient = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const adminClient = createClient(supabaseUrl, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await userClient.auth.getUser();
    const actor = authData.user;
    if (authError || !actor) return json({ error: "Unauthorized" }, 401);

    let payload: ShareRequest;
    try {
      payload = await request.json();
    } catch {
      return json({ error: "Invalid request" }, 400);
    }

    let targetList: string;
    let targetEmail: string;
    let targetRole: "editor" | "viewer";
    try {
      ({ targetList, targetEmail, targetRole } = parseRequest(payload));
    } catch {
      return json({ error: "Invalid request" }, 400);
    }

    const targetHash = await sha256(`${secretKey}:${targetEmail}`);
    const since = new Date(Date.now() - RATE_LIMIT_WINDOW_MS).toISOString();
    const { count: attemptCount, error: rateError } = await adminClient
      .from("security_audit_events")
      .select("id", { count: "exact", head: true })
      .eq("actor", actor.id)
      .eq("action", "list_share_attempt")
      .gte("occurred_at", since);

    if (rateError) throw rateError;
    if ((attemptCount ?? 0) >= RATE_LIMIT_MAX_ATTEMPTS) {
      await adminClient.from("security_audit_events").insert({
        actor: actor.id,
        action: "list_share_rejected",
        list_id: targetList,
        target_hash: targetHash,
        outcome: "rate_limited",
      });
      return json({ error: "Too many share attempts. Try again later." }, 429);
    }

    await adminClient.from("security_audit_events").insert({
      actor: actor.id,
      action: "list_share_attempt",
      list_id: targetList,
      target_hash: targetHash,
      outcome: "started",
    });

    const { data: ownedList, error: ownershipError } = await userClient
      .from("lists")
      .select("id")
      .eq("id", targetList)
      .eq("owner", actor.id)
      .maybeSingle();

    if (ownershipError) throw ownershipError;
    if (!ownedList) {
      await adminClient.from("security_audit_events").insert({
        actor: actor.id,
        action: "list_share_rejected",
        list_id: targetList,
        target_hash: targetHash,
        outcome: "not_owner",
      });
      return json({ error: "Not permitted" }, 403);
    }

    const { data: recipient, error: recipientError } = await adminClient
      .from("profiles")
      .select("id")
      .eq("email", targetEmail)
      .maybeSingle();

    if (recipientError) throw recipientError;
    if (!recipient) {
      await adminClient.from("security_audit_events").insert({
        actor: actor.id,
        action: "list_share_rejected",
        list_id: targetList,
        target_hash: targetHash,
        outcome: "recipient_unavailable",
      });
      return json({ error: "Share request could not be completed" }, 422);
    }

    const { error: shareError } = await adminClient
      .from("list_shares")
      .upsert(
        { list_id: targetList, shared_with: recipient.id, role: targetRole },
        { onConflict: "list_id,shared_with" },
      );

    if (shareError) throw shareError;

    await adminClient.from("security_audit_events").insert({
      actor: actor.id,
      action: "list_share_success",
      list_id: targetList,
      target_hash: targetHash,
      outcome: targetRole,
    });

    return json({ ok: true, role: targetRole });
  } catch (error) {
    console.error("share-list failed", error instanceof Error ? error.message : "unknown_error");
    return json({ error: "Share request could not be completed" }, 500);
  }
});
