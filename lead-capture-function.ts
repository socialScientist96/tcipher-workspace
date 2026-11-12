// Supabase Edge Function: lead-capture
// Website forms (e.g. tcipher.com/ai-design-guide) post here; each submission becomes a lead
// in the workspace, or is added to the existing lead if the same person submits again.
//
// Deploy: Supabase > Edge Functions > Deploy a new function > Via Editor, name it exactly: lead-capture
// Secret (Edge Functions > Secrets): LEAD_CAPTURE_KEY = any long random text; the website sends it
// in the "x-api-key" header. Turn off "Verify JWT" in the function's settings.
//
// POST https://<project>.supabase.co/functions/v1/lead-capture
// {
//   "name": "Priya Sharma", "email": "priya@shop.in", "phone": "+91 98765 43210", "company": "Shop",
//   "pipeline": "Instagram",            // or "General" (default)
//   "source": "Instagram",              // optional
//   "lead_type": "Vendor",              // optional
//   "page_url": "https://tcipher.com/ai-design-guide",
//   "utm": { "source": "instagram", "medium": "paid", "campaign": "ai_guide" },
//   "whatsapp_consent": true,           // (2026-11dr) the person ticked "You can message me on WhatsApp"
//   "form": { "name": "ai_design_guide", "title": "AI Design Skills guide",
//             "fields": [ { "key": "ai_website", "label": "Is your website AI-generated?", "value": "Partly" } ] }
// }
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-api-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
function secretKey(): string {
  try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); if (k && k.default) return k.default; } catch (_) { /* legacy */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}
// deno-lint-ignore no-explicit-any
type Any = any;
const db = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), { auth: { persistSession: false, autoRefreshToken: false } });
const clean = (v: unknown, max = 2000) => typeof v === "string" ? v.replace(/<[^>]*>/g, "").replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, max) : v;
const digits = (p: string) => String(p || "").replace(/\D/g, "").slice(-10);
// only a real web address is kept (a "javascript:" link would run code when someone clicks it in the workspace)
const webUrl = (v: unknown) => { const u = String(clean(v, 500) || ""); try { return /^https?:$/.test(new URL(u).protocol) ? u : ""; } catch (_) { return ""; } };
// for ilike: "_" and "%" in an email are letters, not wildcards
const likeExact = (v: string) => v.replace(/[\\%_]/g, "\\$&");

// Spam limits. The key is visible in the website's code, so it only keeps out casual misuse:
// - LEAD_CAPTURE_ORIGINS (optional secret): comma-separated sites allowed to post, e.g. "https://tcipher.com,https://www.tcipher.com"
// - a hidden "website" field on the form that people leave empty and bots fill in (send it as b.hp)
// - at most PER_IP submissions per address in 10 minutes (per server instance), and
// - when more than ALERT_LIMIT new leads arrived in 10 minutes, leads are still saved but no one is notified about each one
const PER_IP = 5, ALERT_LIMIT = 15, WINDOW_MS = 10 * 60 * 1000;
const hits = new Map<string, number[]>();
function tooMany(ip: string) {
  const now = Date.now(), list = (hits.get(ip) || []).filter((t) => now - t < WINDOW_MS);
  list.push(now); hits.set(ip, list);
  if (hits.size > 5000) for (const [k, v] of hits) if (!v.some((t) => now - t < WINDOW_MS)) hits.delete(k);
  return list.length > PER_IP;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const KEY = Deno.env.get("LEAD_CAPTURE_KEY") ?? "";
  if (!KEY || req.headers.get("x-api-key") !== KEY) return json({ error: "Not allowed." }, 403);
  const origins = (Deno.env.get("LEAD_CAPTURE_ORIGINS") ?? "").split(",").map((x) => x.trim().replace(/\/$/, "")).filter(Boolean);
  if (origins.length && !origins.includes(req.headers.get("origin") ?? "")) return json({ error: "Not allowed." }, 403);
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
  if (tooMany(ip)) return json({ error: "Too many submissions. Please try again in a few minutes." }, 429);
  try {
    const b: Any = await req.json().catch(() => ({}));
    if (b.hp) return json({ ok: true });   // the hidden field was filled in: a bot (told "ok" so it doesn't retry)
    const name = String(clean(b.name, 120) || "").trim();
    const email = String(clean(b.email, 200) || "").toLowerCase();
    const phone = String(clean(b.phone, 40) || "");
    if (!name && !email && !phone) return json({ error: "Send at least a name, email or phone." }, 422);
    if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "That email address doesn’t look right." }, 422);
    const pipeline = b.pipeline === "Instagram" ? "Instagram" : "General";
    // (2026-11dr) WhatsApp Business needs the person's agreement before we message them: keep when and where
    const consent = b.whatsapp_consent === true && phone ? { whatsapp_consent_at: new Date().toISOString(), whatsapp_consent_source: "Website form" + (b?.form?.title ? ": " + String(clean(b.form.title, 80)) : "") } : null;

    // the form's own answers, kept exactly as asked (any number of fields)
    const fields = Array.isArray(b?.form?.fields) ? b.form.fields.slice(0, 50).map((f: Any) => ({
      key: String(f?.key || "").toLowerCase().replace(/[^a-z0-9_]/g, "_").slice(0, 64),
      label: String(clean(f?.label, 200) || f?.key || ""),
      value: Array.isArray(f?.value) ? f.value.slice(0, 20).map((x: unknown) => clean(String(x), 200)) : (typeof f?.value === "string" ? clean(f.value) : f?.value ?? null),
    })).filter((f: Any) => f.key) : [];
    const utm = b.utm && typeof b.utm === "object" ? Object.fromEntries(["source", "medium", "campaign", "term", "content"].map((k) => [k, clean(b.utm[k], 200) || null])) : {};
    const submission = { form_name: String(clean(b?.form?.name, 64) || "website"), form_title: String(clean(b?.form?.title, 150) || ""),
      page_url: webUrl(b.page_url), utm, fields, submitted_at: new Date().toISOString() };

    // same person, same pipeline? add the submission instead of a new lead
    let existing: Any = null;
    if (email) existing = (await db.from("leads").select("id,form_submissions,name").eq("pipeline", pipeline).ilike("email", likeExact(email)).limit(1)).data?.[0] ?? null;
    if (!existing && phone) {
      const { data } = await db.from("leads").select("id,form_submissions,phone,name").eq("pipeline", pipeline).not("phone", "is", null).limit(1000);
      existing = (data || []).find((l: Any) => digits(l.phone) && digits(l.phone) === digits(phone)) ?? null;
    }
    if (existing) {
      const subs = [...(existing.form_submissions || []), submission].slice(-20);
      const { error } = await db.from("leads").update({ form_submissions: subs }).eq("id", existing.id);
      if (error) throw error;
      if (consent) await db.from("leads").update(consent).eq("id", existing.id).is("whatsapp_consent_at", null);   // fails quietly if the column isn't there yet
      return json({ ok: true, reused: true, lead_id: existing.id });
    }
    const row = {
      name: name || email || phone, email, phone, company: String(clean(b.company, 150) || ""),
      pipeline, status: pipeline === "Instagram" ? "Lead" : "New",
      source: String(clean(b.source, 60) || (utm as Any).source || (pipeline === "Instagram" ? "Instagram" : "Website")),
      lead_type: String(clean(b.lead_type, 60) || ""), form_submissions: [submission],
      notes: String(clean(b.message, 2000) || ""),
    };
    let ins = await db.from("leads").insert(consent ? { ...row, ...consent } : row).select("id,lead_number").single();
    if (ins.error && consent && /whatsapp_consent/.test(ins.error.message || "")) ins = await db.from("leads").insert(row).select("id,lead_number").single();   // upgrade-2026-11dr.sql not run yet
    if (ins.error || !ins.data) throw ins.error || new Error("Lead not saved.");
    const data: Any = ins.data;
    // tell Marketing and Sales, unless a flood of leads is arriving (then they're saved but not announced one by one)
    const since = new Date(Date.now() - WINDOW_MS).toISOString();
    const { count } = await db.from("leads").select("id", { count: "exact", head: true }).gte("created_at", since);
    if ((count ?? 0) > ALERT_LIMIT) return json({ ok: true, reused: false, lead_id: data.id, lead_number: data.lead_number });
    const { data: people } = await db.from("profiles").select("id,is_admin,vertical").eq("is_active", true);
    const to = (people || []).filter((p: Any) => p.is_admin || p.vertical === "Marketing" || (pipeline === "Instagram" && p.vertical === "Sales")).map((p: Any) => p.id);
    if (to.length) await db.from("notifications").insert(to.map((id: string) => ({ user_id: id, title: "New website lead: " + row.name, body: submission.form_title || submission.page_url || pipeline, tbl: "leads", entity_id: data.id })));
    return json({ ok: true, reused: false, lead_id: data.id, lead_number: data.lead_number });
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500);
  }
});
