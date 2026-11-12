// Supabase Edge Function: demo-booking (2026-11dr; one database call since 2026-11ds; one demo at a time and guests since 2026-11dv)
// The public demo booking page (internal.tcipher.com/book.html) asks this small function for free times and books
// one. It is kept separate from google-sync so the page opens quickly: no client library, a few database reads.
// Only times are shown, never names or events. When booking, the time is checked again, the demo goes to whoever on
// the demo team is free (Google-connected first, then the lighter day), the lead is found or created, and the
// google-sync function is asked to send the Google Calendar invite with a Meet link from that person's calendar.
//
// Deploy: Supabase › Edge Functions › Deploy a new function › Via Editor, name it exactly: demo-booking
// Turn OFF "Verify JWT" in its settings (visitors aren't signed in). It uses the CRON_SECRET secret that
// google-sync already has (Edge Functions › Secrets are shared by all functions); nothing new to add.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
// deno-lint-ignore no-explicit-any
type Any = any;
function secretKey(): string {
  try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); if (k && k.default) return k.default; } catch (_) { /* legacy */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}
const BASE = Deno.env.get("SUPABASE_URL") ?? "", KEY = secretKey(), CRON = Deno.env.get("CRON_SECRET") ?? "";
const TZ = "Asia/Kolkata";

/* ---------------- database (PostgREST, as the server) ---------------- */
function headers(extra: Record<string, string> = {}) {
  const h: Record<string, string> = { apikey: KEY, "Content-Type": "application/json", ...extra };
  if (KEY.startsWith("eyJ")) h.Authorization = "Bearer " + KEY;   // a legacy service_role JWT; new secret keys go in "apikey" only
  return h;
}
async function rest(path: string, init: RequestInit = {}) {
  const r = await fetch(BASE + "/rest/v1/" + path, { ...init, headers: headers({ Prefer: "return=representation", ...((init.headers as Record<string, string>) || {}) }) });
  const t = await r.text();
  const b = t ? JSON.parse(t) : null;
  if (!r.ok) throw new Error((b && (b.message || b.error)) || "Database error " + r.status);
  return b;
}
async function count(path: string) {
  const r = await fetch(BASE + "/rest/v1/" + path, { method: "HEAD", headers: headers({ Prefer: "count=exact" }) });
  return +(String(r.headers.get("content-range") || "").split("/")[1] || 0);
}
const q = encodeURIComponent;
const inList = (ids: string[]) => "(" + ids.map((x) => '"' + x + '"').join(",") + ")";

/* ---------------- dates in India time ---------------- */
const dayIn = (d: Date) => new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
const today = () => dayIn(new Date());
const addDays = (s: string, n: number) => { const d = new Date(s + "T12:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const weekday = (s: string) => new Date(s + "T12:00:00Z").getUTCDay();
const hmMin = (t: string) => { const [a, b] = String(t || "0:0").split(":").map(Number); return (a || 0) * 60 + (b || 0); };
const minHM = (n: number) => String(Math.floor(n / 60)).padStart(2, "0") + ":" + String(n % 60).padStart(2, "0");
const minIn = (d: Date) => hmMin(new Intl.DateTimeFormat("en-GB", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(d));
const t12 = (t: string) => { const m = hmMin(t), h = Math.floor(m / 60); return ((h % 12) || 12) + ":" + String(m % 60).padStart(2, "0") + (h < 12 ? " am" : " pm"); };
const isUuid = (v: unknown) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(v || ""));
function occursOn(m: Any, d: string, wd: number[], hol: string[]) {
  if (!m.meeting_date || d < m.meeting_date) return false;
  if (!m.repeat || m.repeat === "Does not repeat") return d === m.meeting_date;
  if (m.repeat === "Every week") return weekday(d) === weekday(m.meeting_date);
  if (m.repeat === "Selected days") return (m.repeat_days || []).includes(weekday(d)) && !hol.includes(d);
  return wd.includes(weekday(d)) && !hol.includes(d);
}

/* ---------------- free times ---------------- */
function configFrom(st: Any, people: Any[]) {
  return {
    on: st.demo_public === true, parallel: st.demo_parallel === true, team: people.filter((p) => p.is_active).map((p) => p.id) as string[], people,
    len: Math.max(15, +st.demo_minutes || 45), buffer: st.demo_buffer_min != null && st.demo_buffer_min !== "" ? Math.max(0, +st.demo_buffer_min) : 15,
    ahead: Math.min(30, Math.max(3, +st.demo_days_ahead || 10)), notice: Math.max(0, st.demo_notice_hours != null && st.demo_notice_hours !== "" ? +st.demo_notice_hours : 3),
    start: hmMin(st.work_start || "10:00"), end: hmMin(st.work_end || "18:00"), wd: (st.working_days || [1, 2, 3, 4, 5, 6]) as number[],
    hol: ((st.holidays || []) as Any[]).map((h) => h.date) as string[], company: String(st.company || "Tcipher Technologies"),
  };
}
// (2026-11ds) everything in one database call (demo_booking_data); the older way, five reads, if that SQL isn't run yet
async function gather(lead?: string) {
  const t0 = today(), to = addDays(t0, 30), leadId = isUuid(lead) ? String(lead) : null;
  const r = await fetch(BASE + "/rest/v1/rpc/demo_booking_data", { method: "POST", headers: headers(), body: JSON.stringify({ p_from: t0, p_to: to, p_lead: leadId }) });
  if (r.ok) {
    const d: Any = await r.json();
    return { C: configFrom(d.settings || {}, d.people || []), ms: d.meetings || [], evs: d.events || [], lv: d.leave || [], linked: new Set<string>(d.linked || []), lead: d.lead || null };
  }
  if (r.status !== 404) throw new Error("Database error " + r.status);
  const st = ((await rest("settings?select=data&id=eq.1"))[0] || { data: {} }).data || {};
  const ids: string[] = (Array.isArray(st.demo_team) ? st.demo_team : []).filter(isUuid);
  const people: Any[] = ids.length ? await rest("profiles?select=id,full_name,is_active&id=in." + q(inList(ids))) : [];
  const C = configFrom(st, people);
  const team = C.team.length ? q(inList(C.team)) : "";
  const [ms, evs, lv, links, leads] = await Promise.all([
    rest("meetings?select=kind,meeting_date,start_time,duration_min,repeat,repeat_days,attendees&start_time=not.is.null&meeting_date=lte." + to),
    team ? rest("calendar_events?select=user_id,starts_at,ends_at&all_day=eq.false&start_date=lte." + to + "&end_date=gte." + t0 + "&user_id=in." + team) : Promise.resolve([]),
    team ? rest("leave_requests?select=user_id,start_date,end_date,type&status=eq.Approved&start_date=lte." + to + "&end_date=gte." + t0 + "&user_id=in." + team) : Promise.resolve([]),
    team ? rest("google_links?select=user_id&user_id=in." + team) : Promise.resolve([]),
    leadId ? rest("leads?select=name,email,phone,company&id=eq." + leadId) : Promise.resolve([]),
  ]);
  return { C, ms, evs, lv, linked: new Set<string>((links as Any[]).map((l) => l.user_id)), lead: (leads as Any[])[0] || null };
}
function freeTimes(C: Any, ms: Any[], evs: Any[], lv: Any[]) {
  const t0 = today(), to = addDays(t0, C.ahead), team: string[] = C.team;
  const busy: Record<string, Record<string, number[][]>> = {};
  const add = (u: string, d: string, a: number, b: number) => { const x = busy[u] = busy[u] || {}; (x[d] = x[d] || []).push([a, b]); };
  for (const m of ms) {
    const rep = m.repeat && m.repeat !== "Does not repeat";
    if (!rep && (m.meeting_date < t0 || m.meeting_date > to)) continue;
    let who = (m.attendees || []).length ? (m.attendees as string[]).filter((a) => team.includes(a)) : team;
    if (!who.length) continue;
    // (2026-11dv) one demo at a time: a booked demo blocks its time for the whole demo team
    if (m.kind === "Sales demo" && !C.parallel) who = team;
    for (let d = rep ? t0 : m.meeting_date; d <= to; d = addDays(d, 1)) {
      if (occursOn(m, d, C.wd, C.hol)) { const a = hmMin(m.start_time); for (const u of who) add(u, d, a, a + (+m.duration_min || 30)); }
      if (!rep) break;
    }
  }
  for (const e of evs) {
    if (!e.starts_at || !team.includes(e.user_id)) continue;
    const a = new Date(e.starts_at), b = new Date(e.ends_at || e.starts_at), first = dayIn(a), last = dayIn(b);
    for (let d = first, i = 0; d <= last && i < 40; d = addDays(d, 1), i++) add(e.user_id, d, d === first ? minIn(a) : 0, d === last ? minIn(b) : 1440);
  }
  for (const l of lv) if (l.type !== "Work from home" && team.includes(l.user_id)) for (let d = l.start_date, i = 0; d <= l.end_date && i < 60; d = addDays(d, 1), i++) add(l.user_id, d, 0, 1440);
  const nowAbs = minIn(new Date()) + C.notice * 60;
  const days: Any[] = [];
  for (let d = t0, i = 0; d <= to; d = addDays(d, 1), i++) {
    if (!C.wd.includes(weekday(d)) || C.hol.includes(d)) continue;
    const slots: Any[] = [];
    for (let s = Math.ceil(C.start / 30) * 30; s + C.len <= C.end; s += 30) {
      if (i * 1440 + s < nowAbs) continue;
      const free = team.filter((u) => !((busy[u] || {})[d] || []).some(([a, b]) => a < s + C.len + C.buffer && b > s - C.buffer));
      if (free.length) slots.push({ start: s, free });
    }
    days.push({ day: d, slots });
  }
  return { days, busy };
}

/* ---------------- actions ---------------- */
async function slots(body: Any) {
  const G = await gather(body.lead);
  if (!G.C.on || !G.C.team.length) return { open: false, company: G.C.company };
  const { days } = freeTimes(G.C, G.ms, G.evs, G.lv);
  const l = G.lead;
  return { open: true, company: G.C.company, minutes: G.C.len, timezone: "India (IST)",
    lead: l ? { name: l.name || "", email: l.email || "", phone: l.phone || "", company: l.company || "" } : null,
    days: days.map((x: Any) => ({ day: x.day, times: x.slots.map((s: Any) => minHM(s.start)) })) };
}
async function book(body: Any, ip: string) {
  const clean = (v: unknown, n: number) => String(v ?? "").replace(/[\u0000-\u001f]+/g, " ").trim().slice(0, n);
  const name = clean(body.name, 80), email = clean(body.email, 120).toLowerCase(), phone = clean(body.phone, 24), company = clean(body.company, 100), note = clean(body.note, 600);
  const day = clean(body.day, 10), time = clean(body.time, 5), waOk = body.whatsapp === true;
  // (2026-11dv) colleagues the lead wants on the call (up to 5 emails)
  const extra = [...new Set(String(body.guests ?? "").toLowerCase().split(/[\s,;]+/).map((x) => x.trim()).filter(Boolean))];
  if (extra.some((e) => !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e))) throw new Error("One of the other people’s emails doesn’t look right.");
  if (extra.length > 5) throw new Error("You can add up to 5 other people.");
  if (clean(body.website, 200)) return { ok: true, day, time };   // hidden field only robots fill in
  if (name.length < 2) throw new Error("Please enter your name.");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) throw new Error("Please enter a valid email address.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !/^\d{2}:\d{2}$/.test(time)) throw new Error("Please pick a time.");
  const hourAgo = new Date(Date.now() - 3600e3).toISOString(), weekAgo = new Date(Date.now() - 7 * 864e5).toISOString();
  if (await count("booking_log?select=id&ip=eq." + q(ip) + "&at=gte." + q(hourAgo)) >= 5) throw new Error("Too many tries from this connection. Please try again in an hour, or reply to our email.");
  await rest("booking_log", { method: "POST", body: JSON.stringify({ ip, email, ok: false }), headers: { Prefer: "return=minimal" } });
  if (await count("booking_log?select=id&ok=eq.true&email=eq." + q(email) + "&at=gte." + q(weekAgo)) >= 2) throw new Error("You already have a demo booked with us. Check your email for the invite, or reply to it to change the time.");
  const G = await gather(), C = G.C;
  if (!C.on || !C.team.length) throw new Error("Online booking is closed right now. Please reply to our email and we’ll find a time.");
  const { days, busy } = freeTimes(C, G.ms, G.evs, G.lv);
  const slot = (days.find((x: Any) => x.day === day)?.slots || []).find((x: Any) => x.start === hmMin(time));
  if (!slot) { const e = new Error("That time was just taken. Please pick another one."); (e as Any).status = 409; throw e; }
  const linked = G.linked;
  const who = (slot.free as string[]).slice().sort((a, b) => (+linked.has(b) - +linked.has(a)) || (((busy[a] || {})[day] || []).length - ((busy[b] || {})[day] || []).length))[0];
  // the lead: the one the personal link was for, else the newest lead with this email, else a new one
  let lead: Any = isUuid(body.lead) ? (await rest("leads?select=*&id=eq." + body.lead))[0] : null;
  if (!lead) lead = (await rest("leads?select=*&order=created_at.desc&limit=1&email=ilike." + q(email.replace(/[\\%_*]/g, "\\$&"))))[0] || null;
  if (lead) {
    const patch: Any = {};
    if (!lead.email) patch.email = email;
    if (!lead.phone && phone) patch.phone = phone;
    if (!lead.company && company) patch.company = company;
    if (lead.pipeline === "Instagram" && ["Lead", "Called", "Picked up", "Qualified"].includes(lead.status)) patch.status = "Demo booked";
    if (Object.keys(patch).length) lead = (await rest("leads?id=eq." + lead.id, { method: "PATCH", body: JSON.stringify(patch) }))[0];
  } else {
    lead = (await rest("leads", { method: "POST", body: JSON.stringify({ name, email, phone, company, source: "Website", status: "New", pipeline: "General", created_by: null,
      notes: "Booked a demo on the booking page." + (note ? "\n\n" + note : "") }) }))[0];
  }
  if (waOk && phone && !lead.whatsapp_consent_at) {
    try { await rest("leads?id=eq." + lead.id, { method: "PATCH", body: JSON.stringify({ whatsapp_consent_at: new Date().toISOString(), whatsapp_consent_source: "Booking page" }), headers: { Prefer: "return=minimal" } }); }
    catch (_) { /* the consent column isn't there yet (upgrade-2026-11dr.sql not run) */ }
  }
  const title = "Demo: " + (lead.name || name) + ((lead.company || company) ? " (" + (lead.company || company) + ")" : "");
  const meeting = (await rest("meetings", { method: "POST", body: JSON.stringify({ title, kind: "Sales demo", repeat: "Does not repeat", meeting_date: day, start_time: time, duration_min: C.len,
    attendees: [who], created_by: who, lead_id: lead.id, guest_emails: [...new Set([email, ...extra])],
    agenda: [note ? "From " + (lead.name || name) + ": " + note : "", "Booked by the lead on the booking page."].filter(Boolean).join("\n\n") }) }))[0];
  // the Google invite + Meet link, from the person's own calendar (google-sync holds the Google access)
  let invited = false, link = "";
  if (linked.has(who) && CRON) {
    try {
      const r = await fetch(BASE + "/functions/v1/google-sync", { method: "POST", headers: { "Content-Type": "application/json", "x-cron-secret": CRON }, body: JSON.stringify({ action: "invite_booking", meeting_id: meeting.id }) });
      const j = await r.json().catch(() => ({}));
      if (r.ok && j.ok) { invited = true; link = (j.meeting && j.meeting.link) || ""; }
    } catch (_) { /* the team is told below; they can send it from the meeting */ }
  }
  const when = new Date(day + "T12:00:00Z").toLocaleDateString("en-IN", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }) + ", " + t12(time);
  const whoName = String((C.people.find((p: Any) => p.id === who) || {}).full_name || "");
  const tell = [...new Set([who, lead.owner_id, lead.sales_owner_id].filter(Boolean))] as string[];
  await Promise.all([
    tell.length ? rest("notifications", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify(tell.map((u) => ({ user_id: u, title: "Demo booked by a lead", created_by: null,
      body: title + " · " + when + (u === who ? "" : " · with " + whoName) + (invited ? "" : " · no Google invite was sent: open the meeting to send it"), tbl: "meetings", entity_id: meeting.id }))) }) : null,
    rest("activities", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ kind: "Demo", direction: "Inbound", activity_date: today(), owner_id: who, lead_id: lead.id,
      subject: "Booked a demo for " + when + " on the booking page", outcome: note }) }),
    rest("booking_log", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ ip, email, ok: true }) }),
  ]);
  return { ok: true, day, time, minutes: C.len, with: whoName.split(" ")[0], invited, link, others: extra.filter((e) => e !== email).length };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const body = await req.json().catch(() => ({}));
  try {
    if (body.action === "slots") return json(await slots(body));
    if (body.action === "book") return json(await book(body, (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown"));
    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, (e as Any).status || 400);
  }
});
