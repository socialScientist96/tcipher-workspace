// Supabase Edge Function: whatsapp-send (2026-11es)
// Sends WhatsApp messages from the business number for people signed in to the workspace. Meta's key stays here;
// the browser never sees it. Only people who can see the lead (or deal) can message it, and every message records
// who sent it.
//   - Within 24 hours of the person's last message: any text, photo or document.
//   - Otherwise: only a template Meta has approved, and only if they agreed to WhatsApp messages and didn't send STOP.
//
// Deploy: Supabase › Edge Functions › Deploy a new function › Via Editor, name it exactly: whatsapp-send
// Keep "Verify JWT" ON (only signed-in people can call it).
// Secrets: META_SYSTEM_TOKEN, WA_PHONE_NUMBER_ID, WA_WABA_ID (template list), optional META_GRAPH_VERSION (default v24.0).
// Needs upgrade-2026-11es.sql.
//
// POST (JSON, or multipart with "payload" = JSON and "file" = the photo/document)
//   { "action": "status" }                                  → is WhatsApp Business connected? { connected, number }
//   { "action": "templates" }                               → approved templates [{ name, language, body, params }]
//   { "action": "send", "lead_id" | "deal_id": "…", "kind": "text", "text": "…" }
//   { "action": "send", …, "kind": "template", "template": { "name": "…", "language": "en", "params": ["Priya"] } }
//   { "action": "send", …, "kind": "file", "caption": "…" } + file
import { createClient } from "npm:@supabase/supabase-js@2";

// deno-lint-ignore no-explicit-any
type Any = any;
function secretKey(): string {
  try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); if (k && k.default) return k.default; } catch (_) { /* legacy */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}
function anonKey(): string {
  try { const k = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}"); if (k && k.default) return k.default; } catch (_) { /* legacy */ }
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
}
const URL_ = Deno.env.get("SUPABASE_URL")!;
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const admin = createClient(URL_, secretKey(), opts);
const env = (k: string) => (Deno.env.get(k) ?? "").trim();
const GRAPH = () => "https://graph.facebook.com/" + (env("META_GRAPH_VERSION") || "v24.0") + "/";
const DAY = 24 * 3600 * 1000;
const cors = (req: Request) => ({
  "Access-Control-Allow-Origin": req.headers.get("origin") || "*", "Vary": "Origin",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
});
const json = (req: Request, b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors(req), "Content-Type": "application/json" } });
class Plain extends Error { code?: number; constructor(m: string, code?: number) { super(m); this.code = code; } }
// WhatsApp numbers: digits with the country code; a 10-digit Indian number gets 91
function waNumber(p: unknown) { let d = String(p ?? "").replace(/\D/g, ""); if (d.length === 10) d = "91" + d; return d; }

// Meta's error codes, in words the team can act on
function explain(code: number, msg: string): string {
  if (code === 131047) return "More than 24 hours since their last message: pick an approved template.";
  if (code === 131026) return "This number can't receive WhatsApp messages (it may not be on WhatsApp).";
  if (code === 131021) return "That's the business number itself.";
  if (code === 131030) return "While WhatsApp is in test mode, only the test numbers added in Meta can receive messages.";
  if (code === 131051 || code === 131052 || code === 131053) return "WhatsApp couldn't take this file. Try a PDF, JPG or PNG under 5 MB.";
  if (code >= 132000 && code <= 132015) return "This template can't be used right now (it may be paused, or the details don't fit it). An admin has been told.";
  if (code === 133010) return "The business number isn't registered with WhatsApp yet.";
  if (code === 131031 || code === 368) return "Meta has restricted the business account. An admin needs to check WhatsApp Manager.";
  if (code === 190) return "The WhatsApp connection's key has expired. An admin needs to add a new one.";
  if (code === 130429 || code === 131056 || code === 80007) return "WhatsApp is limiting how fast we send. Try again in a minute.";
  return "WhatsApp didn't send it: " + (msg || "unknown error") + (code ? " (" + code + ")" : "");
}

async function graph(path: string, init: RequestInit = {}, retry = true): Promise<Any> {
  const tok = env("META_SYSTEM_TOKEN");
  if (!tok) throw new Plain("WhatsApp Business isn't connected yet (an admin adds Meta's key in Supabase).");
  const r = await fetch(GRAPH() + path, { ...init, headers: { Authorization: "Bearer " + tok, ...(init.headers || {}) } });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || j.error) {
    const code = +(j.error?.code || 0), sub = +(j.error?.error_subcode || 0);
    if (retry && [130429, 131056, 80007].includes(code)) { await new Promise((ok) => setTimeout(ok, 1500)); return graph(path, init, false); }
    throw new Plain(explain(code || sub, j.error?.error_data?.details || j.error?.error_user_msg || j.error?.message || String(r.status)), code || sub || r.status);
  }
  return j;
}

// template text from Meta's components: the body, with {{1}}, {{2}}… the places to fill in
function templateInfo(t: Any) {
  const body = (t.components || []).find((c: Any) => c.type === "BODY")?.text || "";
  const params = [...new Set((body.match(/\{\{\s*(\d+)\s*\}\}/g) || []).map((x: string) => +x.replace(/\D/g, "")))].sort((a, b) => (a as number) - (b as number));
  const header = (t.components || []).find((c: Any) => c.type === "HEADER");
  return { name: t.name, language: t.language, category: t.category, body, params: params.length, header: header ? header.format : null };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Use POST." }, 405);
  // who is asking
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  const u = token ? await admin.auth.getUser(token) : null;
  if (!u || u.error || !u.data?.user) return json(req, { error: "Please sign in again." }, 401);
  const me = (await admin.from("profiles").select("id,full_name,is_admin,is_active").eq("id", u.data.user.id).maybeSingle()).data;
  if (!me || me.is_active === false) return json(req, { error: "Your account is turned off." }, 403);
  const asMe = createClient(URL_, anonKey(), { ...opts, global: { headers: { Authorization: "Bearer " + token } } });

  try {
    let b: Any = {}, file: File | null = null;
    if ((req.headers.get("content-type") || "").includes("multipart/form-data")) {
      const fd = await req.formData();
      b = JSON.parse(String(fd.get("payload") || "{}"));
      const f = fd.get("file"); if (f && typeof f !== "string") file = f;
    } else b = await req.json().catch(() => ({}));
    const action = String(b.action || "");

    if (action === "status") {
      const connected = !!(env("META_SYSTEM_TOKEN") && env("WA_PHONE_NUMBER_ID"));
      let number = null, name = null, quality = null;
      if (connected) {
        try { const n = await graph(encodeURIComponent(env("WA_PHONE_NUMBER_ID")) + "?fields=display_phone_number,verified_name,quality_rating"); number = n.display_phone_number; name = n.verified_name; quality = n.quality_rating; }
        catch (e) { return json(req, { connected: false, problem: (e as Error).message }); }
      }
      return json(req, { connected, number, name, quality, templates: !!env("WA_WABA_ID") });
    }

    if (action === "templates") {
      const waba = env("WA_WABA_ID");
      if (!waba) throw new Plain("WA_WABA_ID isn't set, so templates can't be listed.");
      const j = await graph(encodeURIComponent(waba) + "/message_templates?fields=name,status,language,category,components&limit=200");
      const list = (j.data || []).filter((t: Any) => t.status === "APPROVED").map(templateInfo).filter((t: Any) => !t.header || t.header === "TEXT");
      return json(req, { templates: list });
    }

    if (action !== "send") return json(req, { error: "Unknown action." }, 400);

    // the lead or deal, read with the person's own access rules: if they can't see it, they can't message it
    let lead: Any = null, deal: Any = null;
    if (b.lead_id) lead = (await asMe.from("leads").select("id,name,phone,deal_id,whatsapp_consent_at,whatsapp_opted_out_at").eq("id", String(b.lead_id)).maybeSingle()).data;
    if (b.deal_id) deal = (await asMe.from("deals").select("id,title,contact_name,phone,lead_id").eq("id", String(b.deal_id)).maybeSingle()).data;
    if (!lead && !deal) return json(req, { error: "You can't message this record (it may have been deleted, or you don't have access)." }, 403);
    if (!lead && deal?.lead_id) lead = (await admin.from("leads").select("id,name,phone,deal_id,whatsapp_consent_at,whatsapp_opted_out_at").eq("id", deal.lead_id).maybeSingle()).data;
    const phone = waNumber(b.phone || (deal && deal.phone) || (lead && lead.phone));
    if (phone.length < 11) return json(req, { error: "There's no phone number with a country code on this record." }, 422);

    // the 24-hour window: since their last message to us
    const last = (await admin.from("whatsapp_messages").select("sent_at").eq("phone", phone).eq("direction", "in").order("sent_at", { ascending: false }).limit(1)).data?.[0];
    const open = !!last && Date.now() - Date.parse(last.sent_at) < DAY;
    const kind = String(b.kind || "text");
    if (kind !== "template" && !open) return json(req, { error: explain(131047, ""), needs_template: true }, 422);
    if (kind === "template") {
      if (lead && lead.whatsapp_opted_out_at) return json(req, { error: "They asked not to get WhatsApp messages (sent STOP)." }, 422);
      if (!open && lead && !lead.whatsapp_consent_at) return json(req, { error: "Record that they agreed to WhatsApp messages first (\"They agreed\" on the lead).", needs_consent: true }, 422);
      if (!open && !lead) return json(req, { error: "Messages we start need the person's agreement, which is recorded on a lead. Link this deal to a lead first." }, 422);
    }

    // build Meta's message
    const msg: Any = { messaging_product: "whatsapp", recipient_type: "individual", to: phone };
    let body = "", type = kind, templateName: string | null = null; const meta: Any = {};
    if (kind === "text") {
      body = String(b.text || "").trim().slice(0, 4096);
      if (!body) return json(req, { error: "Type a message first." }, 422);
      msg.type = "text"; msg.text = { body, preview_url: /https?:\/\//.test(body) };
    } else if (kind === "template") {
      const t = b.template || {};
      templateName = String(t.name || "").slice(0, 512);
      if (!templateName) return json(req, { error: "Pick a template." }, 422);
      const params = (Array.isArray(t.params) ? t.params : []).map((x: unknown) => String(x ?? "").replace(/[\n\t]+/g, " ").replace(/ {4,}/g, "   ").trim().slice(0, 1000));
      if (params.some((p: string) => !p)) return json(req, { error: "Fill in every blank in the template." }, 422);
      msg.type = "template";
      msg.template = { name: templateName, language: { code: String(t.language || "en") }, ...(params.length ? { components: [{ type: "body", parameters: params.map((p: string) => ({ type: "text", text: p })) }] } : {}) };
      body = String(t.preview || "").slice(0, 4096) || ("Template: " + templateName);
    } else if (kind === "file") {
      if (!file) return json(req, { error: "Choose a file." }, 422);
      if (file.size > 16 * 1048576) return json(req, { error: "That file is over 16 MB, which WhatsApp doesn't allow for documents." }, 422);
      const mime = (file.type || "application/octet-stream").split(";")[0];
      const isImg = /^image\/(jpeg|png)$/.test(mime) && file.size <= 5 * 1048576;
      const fd = new FormData(); fd.append("messaging_product", "whatsapp"); fd.append("type", mime); fd.append("file", file, file.name || "file");
      const up = await graph(encodeURIComponent(env("WA_PHONE_NUMBER_ID")) + "/media", { method: "POST", body: fd });
      const caption = String(b.caption || "").trim().slice(0, 1024);
      type = isImg ? "image" : "document";
      msg.type = type;
      msg[type] = isImg ? { id: up.id, ...(caption ? { caption } : {}) } : { id: up.id, filename: String(file.name || "document").slice(0, 200), ...(caption ? { caption } : {}) };
      body = caption || (isImg ? "Photo" : String(file.name || "Document"));
      meta.filename = file.name; meta.mime = mime;
      if (b.file_id) meta.file_id = String(b.file_id);
    } else return json(req, { error: "Unknown kind of message." }, 400);

    const leadId = lead ? lead.id : null, dealId = deal ? deal.id : (lead && lead.deal_id) || null;
    let sent: Any;
    try { sent = await graph(encodeURIComponent(env("WA_PHONE_NUMBER_ID")) + "/messages", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(msg) }); }
    catch (e) {
      const code = (e as Plain).code || null;
      // keep the failed attempt on the conversation, so everyone sees what happened
      await admin.from("whatsapp_messages").insert({ direction: "out", phone, lead_id: leadId, deal_id: dealId, type, body, template_name: templateName, meta, status: "failed",
        error_code: code, error_text: (e as Error).message, sent_by: me.id });
      if (code && code >= 132000 && code <= 132015) {   // a template problem: tell the admins
        const { data: admins } = await admin.from("profiles").select("id").eq("is_admin", true).eq("is_active", true);
        if (admins?.length) await admin.from("notifications").insert(admins.map((a: Any) => ({ user_id: a.id, title: "WhatsApp template “" + templateName + "” couldn't be sent", body: (e as Error).message.slice(0, 280), tbl: leadId ? "leads" : "deals", entity_id: leadId || dealId })));
      }
      throw e;
    }
    const wamid = sent?.messages?.[0]?.id || null;
    const row = (await admin.from("whatsapp_messages").insert({ wamid, direction: "out", phone, lead_id: leadId, deal_id: dealId, type, body, template_name: templateName,
      file_id: meta.file_id || null, meta, status: "sent", sent_by: me.id }).select().single()).data;

    // the communication log and "last contacted", as the WhatsApp button already did
    const now = new Date().toISOString(), day = new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
    const who = (deal && (deal.contact_name || deal.title)) || (lead && lead.name) || "";
    await admin.from("activities").insert({ kind: "WhatsApp", subject: "WhatsApp" + (templateName ? ": " + templateName : "") + (who ? " to " + who : ""), activity_date: day,
      lead_id: leadId, deal_id: dealId, owner_id: me.id, created_by: me.id, outcome: body.slice(0, 2000), direction: "out" }).then(() => {}, () => {});
    if (leadId) await admin.from("leads").update({ last_contacted_at: now }).eq("id", leadId);
    if (dealId) await admin.from("deals").update({ last_contacted_at: now }).eq("id", dealId);
    return json(req, { ok: true, message: row });
  } catch (e) {
    const plain = e instanceof Plain;
    if (!plain) console.error("whatsapp-send", e);
    return json(req, { error: plain ? (e as Error).message : "Something went wrong sending it: " + ((e as Error).message || e) }, plain ? 422 : 500);
  }
});
