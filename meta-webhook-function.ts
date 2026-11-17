// Supabase Edge Function: meta-webhook (2026-11es)
// Meta (Facebook / Instagram / WhatsApp) calls this for two things:
//   1. Lead Ads: someone submits a Facebook or Instagram lead form → a lead in the workspace (or the submission is
//      added to the same person's lead), with the ad, ad set and campaign names.
//   2. WhatsApp: a message to the business number → saved on the matching lead (a new lead if the number is unknown),
//      and the lead's owner is told; delivery receipts (sent, delivered, read, failed) update messages we sent.
//
// Deploy: Supabase › Edge Functions › Deploy a new function › Via Editor, name it exactly: meta-webhook
// Turn OFF "Verify JWT" (Meta can't send a Supabase login; every call is checked with Meta's signature instead).
// Callback URL for Meta: https://<project>.supabase.co/functions/v1/meta-webhook
//
// Secrets (Edge Functions › Secrets):
//   META_APP_SECRET     the Meta app's secret (App settings › Basic): checks that each call really came from Meta
//   META_VERIFY_TOKEN   any long random text; the same text goes in Meta's webhook settings ("Verify token")
//   META_SYSTEM_TOKEN   the System User's permanent access token (reads lead answers, downloads WhatsApp media)
//   META_PAGE_ID        optional: only this Facebook Page's leads are accepted
//   WA_PHONE_NUMBER_ID  optional: only messages to this WhatsApp number are accepted
//   META_GRAPH_VERSION  optional, default v24.0
// Needs upgrade-2026-11es.sql.
import { createClient } from "npm:@supabase/supabase-js@2";

// deno-lint-ignore no-explicit-any
type Any = any;
function secretKey(): string {
  try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); if (k && k.default) return k.default; } catch (_) { /* legacy */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}
const db = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), { auth: { persistSession: false, autoRefreshToken: false } });
const env = (k: string) => (Deno.env.get(k) ?? "").trim();
const GRAPH = () => "https://graph.facebook.com/" + (env("META_GRAPH_VERSION") || "v24.0") + "/";
const clean = (v: unknown, max = 2000) => typeof v === "string" ? v.replace(/<[^>]*>/g, "").replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, " ").trim().slice(0, max) : "";
const digits = (p: unknown) => String(p ?? "").replace(/\D/g, "");
const last10 = (p: unknown) => digits(p).slice(-10);
const likeExact = (v: string) => v.replace(/[\\%_]/g, "\\$&");
const text = (s: string, status = 200) => new Response(s, { status, headers: { "Content-Type": "text/plain" } });
const ALERT_LIMIT = 15, WINDOW_MS = 10 * 60 * 1000;

/* ---------- Meta's signature: HMAC-SHA256 of the exact body with the app secret ---------- */
async function signatureOk(raw: string, header: string | null): Promise<boolean> {
  const secret = env("META_APP_SECRET");
  if (!secret || !header || !header.startsWith("sha256=")) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw)));
  const want = Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("");
  const got = header.slice(7).toLowerCase();
  if (got.length !== want.length) return false;
  let diff = 0; for (let i = 0; i < want.length; i++) diff |= want.charCodeAt(i) ^ got.charCodeAt(i);   // same time whatever matches
  return diff === 0;
}

async function graph(path: string): Promise<Any> {
  const tok = env("META_SYSTEM_TOKEN");
  if (!tok) throw new Error("META_SYSTEM_TOKEN is not set");
  const r = await fetch(GRAPH() + path, { headers: { Authorization: "Bearer " + tok } });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || j.error) throw new Error("Meta: " + ((j.error && (j.error.error_user_msg || j.error.message)) || r.status));
  return j;
}

async function notifyPeople(ids: string[], title: string, body: string, tbl: string, entity: string) {
  const to = [...new Set(ids.filter(Boolean))];
  if (to.length) await db.from("notifications").insert(to.map((id) => ({ user_id: id, title: title.slice(0, 200), body: body.slice(0, 300), tbl, entity_id: entity })));
}
async function marketingPeople(alsoSales = false): Promise<string[]> {
  const { data } = await db.from("profiles").select("id,is_admin,vertical").eq("is_active", true);
  return (data || []).filter((p: Any) => p.is_admin || p.vertical === "Marketing" || (alsoSales && p.vertical === "Sales")).map((p: Any) => p.id);
}
async function flooding(): Promise<boolean> {
  const { count } = await db.from("leads").select("id", { count: "exact", head: true }).gte("created_at", new Date(Date.now() - WINDOW_MS).toISOString());
  return (count ?? 0) > ALERT_LIMIT;
}

/* =====================================================================================================================
   1. Lead Ads
   ===================================================================================================================== */
const names = new Map<string, Any>();   // ad / form names, cached while this instance runs
async function cachedName(key: string, path: string): Promise<Any> {
  if (names.has(key)) return names.get(key);
  let v: Any = {};
  try { v = await graph(path); } catch (e) { console.warn("name lookup", key, (e as Error).message); }
  names.set(key, v); return v;
}
// Meta's standard question keys → lead columns
const STD: Record<string, string> = { full_name: "name", email: "email", phone_number: "phone", company_name: "company", city: "city", state: "state", country: "country", zip_code: "pincode", post_code: "pincode", street_address: "address" };

async function handleLead(v: Any) {
  const leadgenId = String(v.leadgen_id || "");
  if (!leadgenId) return;
  const page = env("META_PAGE_ID");
  if (page && String(v.page_id || "") !== page) { console.warn("lead for another page", v.page_id); return; }
  // a repeated event (Meta retries) is ignored
  const dup = await db.from("leads").select("id").filter("form_submissions", "cs", JSON.stringify([{ leadgen_id: leadgenId }])).limit(1);
  if ((dup.data || []).length) return;

  const lead = await graph(encodeURIComponent(leadgenId) + "?fields=created_time,field_data,ad_id,adset_id,campaign_id,form_id,platform,is_organic");
  const formId = String(lead.form_id || v.form_id || "");
  const adId = String(lead.ad_id || v.ad_id || "");
  const form = formId ? await cachedName("form:" + formId, encodeURIComponent(formId) + "?fields=name") : {};
  const ad = adId ? await cachedName("ad:" + adId, encodeURIComponent(adId) + "?fields=name,adset{name},campaign{name}") : {};
  const ig = String(lead.platform || "").toLowerCase() === "ig";
  const campaignName = clean(ad?.campaign?.name, 200);

  const col: Record<string, string> = {}; let first = "", last = "", consent = false;
  const fields: Any[] = [];
  for (const f of (lead.field_data || []).slice(0, 60)) {
    const key = String(f?.name || "").toLowerCase().replace(/[^a-z0-9_]/g, "_").slice(0, 64);
    const vals = Array.isArray(f?.values) ? f.values.map((x: unknown) => clean(String(x ?? ""), 500)) : [];
    const val = vals.length > 1 ? vals : (vals[0] ?? "");
    if (!key) continue;
    if (STD[key]) { col[STD[key]] = String(vals[0] || ""); continue; }
    if (key === "first_name") { first = String(vals[0] || ""); continue; }
    if (key === "last_name") { last = String(vals[0] || ""); continue; }
    if (/whatsapp/.test(key) && /^(yes|true|agree|i agree|ok)/i.test(String(vals[0] || ""))) consent = true;
    fields.push({ key, label: key.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase()), value: val });
  }
  const name = clean(col.name || [first, last].filter(Boolean).join(" "), 120);
  const email = clean(col.email, 200).toLowerCase();
  const phone = clean(col.phone, 40);
  const submission = {
    form_name: "meta_" + formId, form_title: clean(form?.name, 150) || (ig ? "Instagram lead form" : "Facebook lead form"),
    page_url: "", utm: { source: ig ? "instagram" : "facebook", medium: "paid", campaign: campaignName || null, term: null, content: clean(ad?.name, 200) || null },
    fields, submitted_at: lead.created_time ? new Date(lead.created_time).toISOString() : new Date().toISOString(), leadgen_id: leadgenId,
  };
  const sourceMeta = { leadgen_id: leadgenId, platform: ig ? "instagram" : "facebook", form_id: formId, form_name: clean(form?.name, 150), ad_id: adId, ad_name: clean(ad?.name, 200),
    adset_id: String(lead.adset_id || ""), adset_name: clean(ad?.adset?.name, 200), campaign_id: String(lead.campaign_id || ""), campaign_name: campaignName, organic: !!lead.is_organic };
  const consentCols = consent && phone ? { whatsapp_consent_at: new Date().toISOString(), whatsapp_consent_source: "Meta lead form: " + submission.form_title } : null;

  // same person (General pipeline)? add the submission to their lead
  const pipeline = "General";
  let existing: Any = null;
  if (email) existing = (await db.from("leads").select("id,form_submissions,name").eq("pipeline", pipeline).ilike("email", likeExact(email)).limit(1)).data?.[0] ?? null;
  if (!existing && last10(phone).length >= 8) {
    const m = (await db.rpc("wa_match", { p_phone: phone })).data || {};
    if (m.lead_id) existing = (await db.from("leads").select("id,form_submissions,name,pipeline").eq("id", m.lead_id).maybeSingle()).data;
    if (existing && existing.pipeline !== pipeline) existing = null;
  }
  if (existing) {
    await db.from("leads").update({ form_submissions: [...(existing.form_submissions || []), submission].slice(-20) }).eq("id", existing.id);
    if (consentCols) await db.from("leads").update(consentCols).eq("id", existing.id).is("whatsapp_consent_at", null);
    return;
  }
  const row = { name: name || email || phone || "Meta lead", email, phone, company: clean(col.company, 150), city: clean(col.city, 80), state: clean(col.state, 80),
    country: clean(col.country, 80), pincode: clean(col.pincode, 20), address: clean(col.address, 300),
    pipeline, status: "New", source: ig ? "Instagram Ads" : "Meta Ads", form_submissions: [submission], source_meta: sourceMeta, ...(consentCols || {}) };
  const ins = await db.from("leads").insert(row).select("id").single();
  if (ins.error || !ins.data) throw ins.error || new Error("Lead not saved");
  if (await flooding()) return;
  await notifyPeople(await marketingPeople(), "New " + (ig ? "Instagram" : "Facebook") + " ad lead: " + row.name, [submission.form_title, campaignName].filter(Boolean).join(" · "), "leads", ins.data.id);
}

/* =====================================================================================================================
   2. WhatsApp
   ===================================================================================================================== */
function describe(m: Any): { type: string; body: string; media?: string; meta: Any } {
  const t = String(m.type || "unsupported");
  const meta: Any = {}; if (m.context?.id) meta.reply_to = m.context.id;
  switch (t) {
    case "text": return { type: t, body: clean(m.text?.body, 4096), meta };
    case "image": case "video": case "audio": case "sticker": case "document": {
      const x = m[t] || {};
      if (x.filename) meta.filename = clean(x.filename, 200);
      if (x.mime_type) meta.mime = String(x.mime_type);
      if (t === "audio" && x.voice) meta.voice = true;
      const what = { image: "Photo", video: "Video", audio: x.voice ? "Voice message" : "Audio", sticker: "Sticker", document: meta.filename || "Document" }[t] as string;
      return { type: t, body: clean(x.caption, 1024) || what, media: x.id, meta };
    }
    case "location": { const l = m.location || {}; Object.assign(meta, { lat: l.latitude, lng: l.longitude, name: clean(l.name, 200), address: clean(l.address, 300) });
      return { type: t, body: "Location: " + ([meta.name, meta.address].filter(Boolean).join(", ") || l.latitude + ", " + l.longitude), meta }; }
    case "button": meta.payload = clean(m.button?.payload, 300); return { type: t, body: clean(m.button?.text, 300), meta };
    case "interactive": { const r = m.interactive?.button_reply || m.interactive?.list_reply || {}; meta.reply_id = clean(r.id, 200); return { type: t, body: clean(r.title, 300) || "(reply)", meta }; }
    case "reaction": meta.message_id = m.reaction?.message_id; return { type: t, body: String(m.reaction?.emoji || "(removed a reaction)"), meta };
    case "contacts": return { type: t, body: "Shared a contact: " + ((m.contacts || []).map((c: Any) => clean(c?.name?.formatted_name, 80)).filter(Boolean).join(", ") || "contact"), meta: { contacts: m.contacts } };
    default: return { type: "unsupported", body: "(a message type the dashboard can't show yet — open it on Meta's WhatsApp Manager)", meta };
  }
}

async function saveMedia(mediaId: string, info: { type: string; meta: Any }, tbl: string, entity: string): Promise<string | null> {
  try {
    const m = await graph(encodeURIComponent(mediaId));
    if (+m.file_size > 25 * 1048576) return null;   // very large: left on Meta (kept 30 days)
    const r = await fetch(m.url, { headers: { Authorization: "Bearer " + env("META_SYSTEM_TOKEN") } });
    if (!r.ok) throw new Error("download " + r.status);
    const bytes = new Uint8Array(await r.arrayBuffer());
    const mime = String(m.mime_type || info.meta.mime || "application/octet-stream").split(";")[0];
    const ext = (mime.split("/")[1] || "bin").replace(/[^a-z0-9]/g, "").slice(0, 8);
    const name = info.meta.filename || ("WhatsApp " + info.type + " " + new Date().toISOString().slice(0, 16).replace("T", " ") + "." + ext);
    const path = tbl + "/" + entity + "/" + Date.now() + "-wa-" + String(name).replace(/[^\w.\-]+/g, "_").slice(-90);
    const up = await db.storage.from("files").upload(path, bytes, { contentType: mime, upsert: false });
    if (up.error) throw up.error;
    const f = await db.from("files").insert({ tbl, entity_id: entity, name, path, size: bytes.length, mime, uploaded_by: null }).select("id").single();
    if (f.error) { await db.storage.from("files").remove([path]); throw f.error; }
    return f.data.id;
  } catch (e) { console.error("media", mediaId, (e as Error).message); return null; }
}

async function handleMessage(m: Any, contacts: Any[]) {
  const wamid = String(m.id || ""), from = digits(m.from);
  if (!wamid || !from) return;
  if ((await db.from("whatsapp_messages").select("id").eq("wamid", wamid).limit(1)).data?.length) return;   // repeat
  const profile = clean((contacts.find((c: Any) => digits(c.wa_id) === from) || contacts[0] || {})?.profile?.name, 120);
  const info = describe(m);

  let match: Any = (await db.rpc("wa_match", { p_phone: from })).data || {};
  let created = false;
  if (!match.lead_id && !match.deal_id && !match.contact_id) {
    const ins = await db.from("leads").insert({ name: profile || "+" + from, phone: "+" + from, pipeline: "General", status: "New", source: "WhatsApp",
      notes: "Wrote to the WhatsApp business number." }).select("id").single();
    if (ins.error || !ins.data) throw ins.error || new Error("lead not saved");
    match = { lead_id: ins.data.id }; created = true;
  }
  const tbl = match.lead_id ? "leads" : match.deal_id ? "deals" : "contacts";
  const entity = match.lead_id || match.deal_id || match.contact_id;
  const fileId = info.media ? await saveMedia(info.media, info, tbl, entity) : null;
  const ins = await db.from("whatsapp_messages").insert({
    wamid, direction: "in", phone: from, profile_name: profile || null, lead_id: match.lead_id || null, deal_id: match.deal_id || null, contact_id: match.contact_id || null,
    type: info.type, body: info.body, media_id: fileId ? null : (info.media || null), file_id: fileId, meta: info.meta, status: "received",
    sent_at: m.timestamp ? new Date(+m.timestamp * 1000).toISOString() : new Date().toISOString(),
  }).select("id").single();
  if (ins.error) { if (/duplicate|unique/i.test(ins.error.message)) return; throw ins.error; }

  // STOP / START
  const word = info.body.trim().toUpperCase().replace(/[^A-Z ]/g, "");
  if (match.lead_id && ["STOP", "UNSUBSCRIBE", "STOP ALL", "OPT OUT"].includes(word)) await db.from("leads").update({ whatsapp_opted_out_at: new Date().toISOString() }).eq("id", match.lead_id);
  if (match.lead_id && ["START", "SUBSCRIBE", "OPT IN"].includes(word)) await db.from("leads").update({ whatsapp_opted_out_at: null }).eq("id", match.lead_id);

  // tell someone, once per burst: not again while an earlier message from them in the last 10 minutes is unread
  const earlier = await db.from("whatsapp_messages").select("id").eq("phone", from).eq("direction", "in").is("read_at", null).neq("id", ins.data.id)
    .gte("sent_at", new Date(Date.now() - WINDOW_MS).toISOString()).limit(1);
  if ((earlier.data || []).length) return;
  let who: string[] = [], label = profile || "+" + from;
  if (match.lead_id) { const l = (await db.from("leads").select("name,owner_id,sales_owner_id").eq("id", match.lead_id).maybeSingle()).data; if (l) { label = l.name || label; who = [l.sales_owner_id, l.owner_id].filter(Boolean); } }
  else if (match.deal_id) { const d = (await db.from("deals").select("title,contact_name,owner_id").eq("id", match.deal_id).maybeSingle()).data; if (d) { label = d.contact_name || d.title || label; who = [d.owner_id].filter(Boolean); } }
  if (!who.length) { if (created && await flooding()) return; who = await marketingPeople(); }
  await notifyPeople(who, (created ? "New WhatsApp lead: " : "WhatsApp from ") + label, info.body.slice(0, 160), tbl, entity);
}

const RANK: Record<string, number> = { sending: 0, sent: 1, delivered: 2, read: 3, failed: 4 };
async function handleStatus(s: Any) {
  const wamid = String(s.id || ""), st = String(s.status || "");
  if (!wamid || !(st in RANK)) return;
  const cur = (await db.from("whatsapp_messages").select("id,status").eq("wamid", wamid).maybeSingle()).data;
  if (!cur) return;   // sent from somewhere else (e.g. Meta's own tools)
  if (st !== "failed" && (RANK[cur.status] ?? 0) >= RANK[st]) return;   // receipts can arrive out of order
  const err = (s.errors || [])[0];
  await db.from("whatsapp_messages").update(st === "failed" && err
    ? { status: st, error_code: +err.code || null, error_text: clean(err.error_data?.details || err.message || err.title, 500) }
    : { status: st }).eq("id", cur.id);
}

async function handleWhatsApp(entry: Any) {
  const only = env("WA_PHONE_NUMBER_ID");
  for (const ch of entry.changes || []) {
    if (ch.field !== "messages") continue;
    const v = ch.value || {};
    if (only && String(v.metadata?.phone_number_id || "") !== only) { console.warn("message for another number", v.metadata?.phone_number_id); continue; }
    for (const m of v.messages || []) { try { await handleMessage(m, v.contacts || []); } catch (e) { console.error("wa message", (e as Error).message); } }
    for (const s of v.statuses || []) { try { await handleStatus(s); } catch (e) { console.error("wa status", (e as Error).message); } }
  }
}

async function handle(body: Any) {
  for (const entry of body.entry || []) {
    if (body.object === "page") {
      for (const ch of entry.changes || []) if (ch.field === "leadgen") { try { await handleLead(ch.value || {}); } catch (e) { console.error("leadgen", (e as Error).message); } }
    } else if (body.object === "whatsapp_business_account") await handleWhatsApp(entry);
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method === "GET") {
    // Meta's one-time check when the webhook is saved
    const tok = env("META_VERIFY_TOKEN");
    if (tok && url.searchParams.get("hub.mode") === "subscribe" && url.searchParams.get("hub.verify_token") === tok) return text(url.searchParams.get("hub.challenge") || "");
    return text("Not allowed.", 403);
  }
  if (req.method !== "POST") return text("Use POST.", 405);
  const raw = await req.text();
  if (!(await signatureOk(raw, req.headers.get("x-hub-signature-256")))) return text("Bad signature.", 401);
  let body: Any; try { body = JSON.parse(raw); } catch (_) { return text("ok"); }
  // answer Meta at once and do the work after (Meta retries anything slow, and the checks above stop duplicates)
  const work = handle(body).catch((e) => console.error("meta-webhook", (e as Error).message));
  const rt = (globalThis as Any).EdgeRuntime;
  if (rt && typeof rt.waitUntil === "function") rt.waitUntil(work); else await work;
  return text("ok");
});
