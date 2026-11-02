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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const KEY = Deno.env.get("LEAD_CAPTURE_KEY") ?? "";
  if (!KEY || req.headers.get("x-api-key") !== KEY) return json({ error: "Not allowed." }, 403);
  try {
    const b: Any = await req.json().catch(() => ({}));
    const name = String(clean(b.name, 120) || "").trim();
    const email = String(clean(b.email, 200) || "").toLowerCase();
    const phone = String(clean(b.phone, 40) || "");
    if (!name && !email && !phone) return json({ error: "Send at least a name, email or phone." }, 422);
    if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "That email address doesn’t look right." }, 422);
    const pipeline = b.pipeline === "Instagram" ? "Instagram" : "General";

    // the form's own answers, kept exactly as asked (any number of fields)
    const fields = Array.isArray(b?.form?.fields) ? b.form.fields.slice(0, 50).map((f: Any) => ({
      key: String(f?.key || "").toLowerCase().replace(/[^a-z0-9_]/g, "_").slice(0, 64),
      label: String(clean(f?.label, 200) || f?.key || ""),
      value: Array.isArray(f?.value) ? f.value.slice(0, 20).map((x: unknown) => clean(String(x), 200)) : (typeof f?.value === "string" ? clean(f.value) : f?.value ?? null),
    })).filter((f: Any) => f.key) : [];
    const utm = b.utm && typeof b.utm === "object" ? Object.fromEntries(["source", "medium", "campaign", "term", "content"].map((k) => [k, clean(b.utm[k], 200) || null])) : {};
    const submission = { form_name: String(clean(b?.form?.name, 64) || "website"), form_title: String(clean(b?.form?.title, 150) || ""),
      page_url: String(clean(b.page_url, 500) || ""), utm, fields, submitted_at: new Date().toISOString() };

    // same person, same pipeline? add the submission instead of a new lead
    let existing: Any = null;
    if (email) existing = (await db.from("leads").select("id,form_submissions,name").eq("pipeline", pipeline).ilike("email", email).limit(1)).data?.[0] ?? null;
    if (!existing && phone) {
      const { data } = await db.from("leads").select("id,form_submissions,phone,name").eq("pipeline", pipeline).not("phone", "is", null).limit(1000);
      existing = (data || []).find((l: Any) => digits(l.phone) && digits(l.phone) === digits(phone)) ?? null;
    }
    if (existing) {
      const subs = [...(existing.form_submissions || []), submission].slice(-20);
      const { error } = await db.from("leads").update({ form_submissions: subs }).eq("id", existing.id);
      if (error) throw error;
      return json({ ok: true, reused: true, lead_id: existing.id });
    }
    const row = {
      name: name || email || phone, email, phone, company: String(clean(b.company, 150) || ""),
      pipeline, status: pipeline === "Instagram" ? "Lead" : "New",
      source: String(clean(b.source, 60) || (utm as Any).source || (pipeline === "Instagram" ? "Instagram" : "Website")),
      lead_type: String(clean(b.lead_type, 60) || ""), form_submissions: [submission],
      notes: String(clean(b.message, 2000) || ""),
    };
    const { data, error } = await db.from("leads").insert(row).select("id,lead_number").single();
    if (error) throw error;
    // tell Marketing and Sales
    const { data: people } = await db.from("profiles").select("id,is_admin,vertical").eq("is_active", true);
    const to = (people || []).filter((p: Any) => p.is_admin || p.vertical === "Marketing" || (pipeline === "Instagram" && p.vertical === "Sales")).map((p: Any) => p.id);
    if (to.length) await db.from("notifications").insert(to.map((id: string) => ({ user_id: id, title: "New website lead: " + row.name, body: submission.form_title || submission.page_url || pipeline, tbl: "leads", entity_id: data.id })));
    return json({ ok: true, reused: false, lead_id: data.id, lead_number: data.lead_number });
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500);
  }
});
