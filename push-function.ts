// Supabase Edge Function: push
// Sends phone and desktop notifications (web push) for the workspace's notifications: messages, tags, tasks,
// approvals… the same ones you see under the bell. Works in Chrome, Edge and Firefox on computers, in Chrome on
// Android, and in the Tcipher Android app (which runs the workspace in Chrome).
//
// Paste this into Supabase > Edge Functions > Deploy a new function > Via Editor, name it exactly: push
// and switch OFF "Enforce JWT verification" (the database calls it with CRON_SECRET; people are checked here).
// Secrets (Edge Functions > Secrets): VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT, and CRON_SECRET (already there).
//
// Calls:
//   from the database (upgrade-2026-11cz.sql), header x-cron-secret:  { id: "<notification id>" }
//   from the app, signed in:                                         { action: "test" }  (a test to your own devices)
// What is NOT sent: notifications already read, chats you muted (unless you're tagged), people whose account is off,
// and anything when "Phone and desktop notifications" are off on that device (the device has no subscription then).
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
function secretKey(): string {
  try { const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); if (keys && keys.default) return keys.default; } catch (_) { /* legacy key */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}
const APP_URL = Deno.env.get("APP_URL") ?? "https://internal.tcipher.com/";
const CRON = Deno.env.get("CRON_SECRET") ?? "";
const PUB = Deno.env.get("VAPID_PUBLIC_KEY") ?? "", PRIV = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
const SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:notifications@tcipher.com";
// deno-lint-ignore no-explicit-any
type Any = any;

const db = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), { auth: { persistSession: false, autoRefreshToken: false } });

// send one message to every device of one person; devices that are gone (uninstalled, notifications blocked) are removed
async function sendTo(userId: string, payload: Any) {
  const { data: subs } = await db.from("push_subscriptions").select("*").eq("user_id", userId);
  let sent = 0;
  for (const s of subs ?? []) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(payload),
        { TTL: 6 * 3600, urgency: payload.urgent ? "high" : "normal", topic: String(payload.tag || "").replace(/[^A-Za-z0-9_-]/g, "").slice(0, 32) || undefined });
      sent++;
      await db.from("push_subscriptions").update({ last_ok_at: new Date().toISOString(), last_error: "" }).eq("id", s.id);
    } catch (e: Any) {
      const code = e && e.statusCode;
      if (code === 404 || code === 410) await db.from("push_subscriptions").delete().eq("id", s.id);
      else await db.from("push_subscriptions").update({ last_error: String((e && (e.body || e.message)) || e).slice(0, 300) }).eq("id", s.id);
    }
  }
  return sent;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  if (!PUB || !PRIV) return json({ error: "Push isn’t set up yet: add VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY in Edge Functions › Secrets." }, 500);
  webpush.setVapidDetails(SUBJECT, PUB, PRIV);
  const body = await req.json().catch(() => ({}));

  // a test from the app: to your own devices
  if (body.action === "test") {
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: who } = token ? await db.auth.getUser(token) : { data: null };
    if (!who?.user) return json({ error: "Sign in again." }, 401);
    const n = await sendTo(who.user.id, { title: "Notifications are on", body: "This is how messages and updates from the Tcipher workspace will look.", url: APP_URL, tag: "test", urgent: true });
    return json({ sent: n });
  }

  if (!CRON || req.headers.get("x-cron-secret") !== CRON) return json({ error: "Not allowed." }, 403);
  const id = String(body.id ?? "");
  if (!id) return json({ error: "Missing notification id." }, 400);
  const { data: n } = await db.from("notifications").select("*").eq("id", id).maybeSingle();
  if (!n || n.is_read) return json({ skipped: "read or gone" });
  const { data: p } = await db.from("profiles").select("id,is_active,client_id,portal_active").eq("id", n.user_id).maybeSingle();
  if (!p || (!p.is_active && !(p.client_id && p.portal_active))) return json({ skipped: "inactive" });
  const direct = /mentioned you|tagged you/i.test(String(n.title || ""));
  if (n.tbl === "chat" && n.entity_id && !direct) {
    const { data: m } = await db.from("chat_mutes").select("channel_id").eq("user_id", n.user_id).eq("channel_id", n.entity_id).maybeSingle();
    if (m) return json({ skipped: "muted" });
  }
  const portal = !!(p.client_id && p.portal_active);
  const url = APP_URL + (n.tbl && n.entity_id ? (portal ? "#p/home" : "#open/" + encodeURIComponent(n.tbl) + "/" + encodeURIComponent(n.entity_id)) : "");
  const sent = await sendTo(n.user_id, {
    title: String(n.title || "Tcipher workspace").slice(0, 120), body: String(n.body || "").slice(0, 240), url,
    // one notification per conversation (a newer message replaces the older one); one per item otherwise
    tag: n.tbl === "chat" ? "chat-" + n.entity_id : "n-" + (n.entity_id || n.id), urgent: n.tbl === "chat" || direct, id: n.id,
  });
  return json({ sent });
});
