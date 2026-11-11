// Supabase Edge Function: push
// Sends phone and desktop notifications (web push) for the workspace's notifications: messages, tags, tasks,
// approvals… the same ones you see under the bell. Works in Chrome, Edge and Firefox on computers, in Chrome on
// Android, and in the Tcipher Android app (which runs the workspace in Chrome).
//
// Paste this into Supabase > Edge Functions > Deploy a new function > Via Editor, name it exactly: push
// and switch OFF "Enforce JWT verification" (the database calls it with PUSH_SECRET; people are checked here).
// Secrets (Edge Functions > Secrets): VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT, PUSH_SECRET.
// For the iPhone app (Apple's push service): APNS_KEY (the whole text of the .p8 key file), APNS_KEY_ID, APNS_TEAM_ID,
// and APNS_BUNDLE_ID (com.tcipher.workspace). Without them, iPhones are simply skipped.
// For the Android app (Firebase Cloud Messaging): FCM_SERVICE_ACCOUNT (the whole text of the Firebase service-account
// .json key). Without it, Android phones are simply skipped.
//
// Calls:
//   from the database (upgrade-2026-11cz.sql), header x-push-secret:  { id: "<notification id>" }
//   from the app, signed in:                                         { action: "test" }  (a test to your own devices)
// What is NOT sent: notifications already read, chats you muted (unless you're tagged), people whose account is off,
// and anything when "Phone and desktop notifications" are off on that device (the device has no subscription then).
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-push-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
function secretKey(): string {
  try { const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); if (keys && keys.default) return keys.default; } catch (_) { /* legacy key */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}
const APP_URL = Deno.env.get("APP_URL") ?? "https://internal.tcipher.com/";
const PUSH_SECRET = Deno.env.get("PUSH_SECRET") ?? "";
const PUB = Deno.env.get("VAPID_PUBLIC_KEY") ?? "", PRIV = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
const SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:notifications@tcipher.com";
// deno-lint-ignore no-explicit-any
type Any = any;

const APNS_KEY = (Deno.env.get("APNS_KEY") ?? "").replace(/\\n/g, "\n"), APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "", APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "com.tcipher.workspace";
const b64url = (b: ArrayBuffer | Uint8Array) => btoa(String.fromCharCode(...new Uint8Array(b as ArrayBuffer))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
let apnsJwt = { token: "", at: 0 };
// Apple's sign-in for push: a short token signed with the .p8 key, reused for 50 minutes
async function apnsToken(): Promise<string> {
  if (apnsJwt.token && Date.now() - apnsJwt.at < 50 * 60000) return apnsJwt.token;
  const pem = APNS_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const head = enc({ alg: "ES256", kid: APNS_KEY_ID }), body = enc({ iss: APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) });
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(head + "." + body));
  apnsJwt = { token: head + "." + body + "." + b64url(sig), at: Date.now() };
  return apnsJwt.token;
}
// one message to one iPhone; returns "gone" when Apple says the app was removed from that phone
async function sendApns(s: Any, payload: Any): Promise<"ok" | "gone" | string> {
  if (!APNS_KEY || !APNS_KEY_ID || !APNS_TEAM_ID) return "iPhone push isn’t set up (APNS_* secrets)";
  const host = s.kind === "apns-sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const res = await fetch(host + "/3/device/" + String(s.endpoint).slice(5), {
    method: "POST",
    headers: { authorization: "bearer " + await apnsToken(), "apns-topic": APNS_BUNDLE_ID, "apns-push-type": "alert", "apns-priority": payload.urgent ? "10" : "5",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 6 * 3600), ...(payload.tag ? { "apns-collapse-id": String(payload.tag).slice(0, 64) } : {}) },
    body: JSON.stringify({ aps: { alert: { title: payload.title, body: payload.body }, sound: "default", "thread-id": payload.tag || "tcipher" }, url: payload.url }),
  });
  if (res.ok) return "ok";
  const why = await res.text().catch(() => "");
  if (res.status === 410 || /BadDeviceToken|Unregistered|DeviceTokenNotForTopic/.test(why)) return "gone";
  return res.status + " " + why.slice(0, 200);
}

// ---- Android app: Firebase Cloud Messaging (HTTP v1) ----
let fcmAuth = { token: "", at: 0, project: "" };
async function fcmAccess(): Promise<{ token: string; project: string }> {
  if (fcmAuth.token && Date.now() - fcmAuth.at < 50 * 60000) return fcmAuth;
  const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
  if (!sa.private_key || !sa.client_email || !sa.project_id) throw new Error("Android push isn’t set up (FCM_SERVICE_ACCOUNT)");
  const pem = String(sa.private_key).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const now = Math.floor(Date.now() / 1000);
  const unsigned = enc({ alg: "RS256", typ: "JWT" }) + "." + enc({ iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 });
  const jwt = unsigned + "." + b64url(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" + jwt });
  const j = await r.json();
  if (!j.access_token) throw new Error("Firebase sign-in failed: " + JSON.stringify(j).slice(0, 200));
  fcmAuth = { token: j.access_token, at: Date.now(), project: sa.project_id };
  return fcmAuth;
}
// a data message, so the app shows it the same way whether it's open, in the background or closed
async function sendFcm(s: Any, payload: Any): Promise<"ok" | "gone" | string> {
  if (!Deno.env.get("FCM_SERVICE_ACCOUNT")) return "Android push isn’t set up (FCM_SERVICE_ACCOUNT)";
  const a = await fcmAccess();
  const res = await fetch("https://fcm.googleapis.com/v1/projects/" + a.project + "/messages:send", {
    method: "POST", headers: { Authorization: "Bearer " + a.token, "Content-Type": "application/json" },
    body: JSON.stringify({ message: { token: String(s.endpoint).slice(4),
      data: { title: String(payload.title || ""), body: String(payload.body || ""), url: String(payload.url || APP_URL), tag: String(payload.tag || "") },
      android: { priority: "HIGH", ttl: "21600s", ...(payload.tag ? { collapse_key: String(payload.tag).slice(0, 60) } : {}) } } }),
  });
  if (res.ok) return "ok";
  const why = await res.text().catch(() => "");
  if (res.status === 404 || /UNREGISTERED|registration-token-not-registered|INVALID_ARGUMENT.*token/i.test(why)) return "gone";
  return res.status + " " + why.slice(0, 200);
}

const db = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), { auth: { persistSession: false, autoRefreshToken: false } });

// send one message to every device of one person; devices that are gone (uninstalled, notifications blocked) are removed
async function sendTo(userId: string, payload: Any) {
  const { data: subs } = await db.from("push_subscriptions").select("*").eq("user_id", userId);
  let sent = 0;
  for (const s of subs ?? []) {
    if (String(s.kind || "web").startsWith("apns") || s.kind === "fcm") {
      try {
        const r = s.kind === "fcm" ? await sendFcm(s, payload) : await sendApns(s, payload);
        if (r === "ok") { sent++; await db.from("push_subscriptions").update({ last_ok_at: new Date().toISOString(), last_error: "" }).eq("id", s.id); }
        else if (r === "gone") await db.from("push_subscriptions").delete().eq("id", s.id);
        else await db.from("push_subscriptions").update({ last_error: r.slice(0, 300) }).eq("id", s.id);
      } catch (e) { await db.from("push_subscriptions").update({ last_error: String(e).slice(0, 300) }).eq("id", s.id); }
      continue;
    }
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

  if (!PUSH_SECRET || req.headers.get("x-push-secret") !== PUSH_SECRET) return json({ error: "Not allowed." }, 403);
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
