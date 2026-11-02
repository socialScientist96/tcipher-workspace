// Supabase Edge Function: google-sync
// Connects each person's Google account once, then keeps Google Calendar in sync automatically,
// creates Google Meet events for workspace meetings, and imports every Google Meet join.
//
// Deploy: Supabase > Edge Functions > Deploy a new function > Via Editor, name it exactly: google-sync
// Secrets (Edge Functions > Secrets): GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, CRON_SECRET
// Turn off "Verify JWT" in the function's settings (the code checks callers itself).
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const TZ = "Asia/Kolkata";
const GID = Deno.env.get("GOOGLE_CLIENT_ID") ?? "";
const GSECRET = Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "";
const CRON = Deno.env.get("CRON_SECRET") ?? "";
const CAL = "https://www.googleapis.com/calendar/v3/calendars/primary/events";
const MEET = "https://meet.googleapis.com/v2/";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
function secretKey(): string {
  try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); if (k && k.default) return k.default; } catch (_) { /* legacy */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}
// deno-lint-ignore no-explicit-any
type Any = any;
const db = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), { auth: { persistSession: false, autoRefreshToken: false } });
const must = (r: Any) => { if (r.error) throw new Error(r.error.message); return r.data; };

/* ---------------- dates in India time ---------------- */
const dayIn = (d: Date) => new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
const today = () => dayIn(new Date());
const addDays = (s: string, n: number) => { const d = new Date(s + "T12:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const weekday = (s: string) => new Date(s + "T12:00:00Z").getUTCDay();
function localDateTime(date: string, time: string | null, plusMin = 0) {
  const [hh, mm] = String(time || "10:00").split(":").map(Number);
  const total = hh * 60 + mm + plusMin;
  const d = addDays(date, Math.floor(total / 1440));
  const m = ((total % 1440) + 1440) % 1440;
  return d + "T" + String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0") + ":00";
}

/* ---------------- Google auth ---------------- */
async function googleTokenRequest(params: Record<string, string>) {
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: GID, client_secret: GSECRET, ...params }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error_description || body.error || "Google sign-in failed.");
  return body;
}
async function accessFor(userId: string): Promise<string> {
  const row = must(await db.from("google_tokens").select("refresh_token").eq("user_id", userId).maybeSingle());
  if (!row) throw new Error("Google isn’t connected for this person.");
  try {
    return (await googleTokenRequest({ grant_type: "refresh_token", refresh_token: row.refresh_token })).access_token;
  } catch (e) {
    const msg = String((e as Error).message || e);
    await db.from("google_links").update({ last_error: /invalid_grant|expired|revoked/i.test(msg) ? "Google access expired or was removed. Connect Google again." : msg }).eq("user_id", userId);
    throw e;
  }
}
async function g(token: string, url: string, init: RequestInit = {}) {
  const res = await fetch(url, { ...init, headers: { Authorization: "Bearer " + token, "Content-Type": "application/json", ...(init.headers || {}) } });
  if (res.status === 204) return null;
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((body.error && body.error.message) || ("Google error " + res.status));
  return body;
}

/* ---------------- calendar sync ---------------- */
async function syncUser(userId: string) {
  try { return await syncUserInner(userId); }
  catch (e) {
    const msg = String((e as Error)?.message || e);
    await db.from("google_links").update({ last_error: "Sync failed: " + msg.slice(0, 300) }).eq("user_id", userId);
    throw e;
  }
}
async function syncUserInner(userId: string) {
  const token = await accessFor(userId);
  const fromDay = addDays(today(), -7), toDay = addDays(today(), 45);
  const timeMin = new Date(fromDay + "T00:00:00+05:30").toISOString();
  const timeMax = new Date(toDay + "T23:59:59+05:30").toISOString();
  const items: Any[] = [];
  let page = "";
  for (let i = 0; i < 8; i++) {
    const r = await g(token, CAL + "?singleEvents=true&orderBy=startTime&maxResults=250&timeMin=" + encodeURIComponent(timeMin) + "&timeMax=" + encodeURIComponent(timeMax) + (page ? "&pageToken=" + encodeURIComponent(page) : ""));
    items.push(...(r.items || []));
    page = r.nextPageToken; if (!page) break;
  }
  const rows = items.filter((e) => e.status !== "cancelled").map((e) => {
    const allDay = !!(e.start && e.start.date);
    const startDate = allDay ? e.start.date : dayIn(new Date(e.start.dateTime));
    const endDate = allDay ? addDays(e.end.date, -1) : dayIn(new Date(e.end.dateTime));
    const video = (e.conferenceData && (e.conferenceData.entryPoints || []).find((p: Any) => p.entryPointType === "video")) || null;
    const emails = new Set<string>([...(e.attendees || []).map((a: Any) => String(a.email || "").toLowerCase()), String((e.organizer && e.organizer.email) || "").toLowerCase()].filter(Boolean));
    return {
      user_id: userId, google_event_id: e.id, ical_uid: e.iCalUID || "", title: e.summary || "(no title)",
      starts_at: allDay ? null : e.start.dateTime, ends_at: allDay ? null : e.end.dateTime, all_day: allDay,
      start_date: startDate, end_date: endDate, meet_link: e.hangoutLink || (video && video.uri) || "",
      html_link: e.htmlLink || "", location: e.location || "", organizer_email: String((e.organizer && e.organizer.email) || "").toLowerCase(),
      attendee_emails: [...emails], updated_at: new Date().toISOString(),
    };
  });
  must(await db.from("calendar_events").delete().eq("user_id", userId).gte("start_date", fromDay));
  for (let i = 0; i < rows.length; i += 200) must(await db.from("calendar_events").upsert(rows.slice(i, i + 200), { onConflict: "user_id,google_event_id" }));
  await db.from("google_links").update({ last_sync_at: new Date().toISOString(), last_error: "" }).eq("user_id", userId);
  return rows.length;
}

/* ---------------- workspace meeting -> Google Calendar event ---------------- */
async function eventBody(m: Any, withMeet: boolean) {
  const ids: string[] = (m.attendees || []).length ? m.attendees : must(await db.from("profiles").select("id").eq("is_active", true)).map((p: Any) => p.id);
  const people = ids.length ? must(await db.from("profiles").select("email").in("id", ids)) : [];
  const settings = (must(await db.from("settings").select("data").eq("id", 1).maybeSingle()) || { data: {} }).data || {};
  const wd: number[] = settings.working_days || [1, 2, 3, 4, 5, 6];
  const byday = (days: number[]) => "RRULE:FREQ=WEEKLY;BYDAY=" + days.map((n) => ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][n]).join(",");
  const rrule = m.repeat === "Every weekday" ? [byday(wd)]
    : m.repeat === "Selected days" && (m.repeat_days || []).length ? [byday(m.repeat_days)]
    : m.repeat === "Every week" ? ["RRULE:FREQ=WEEKLY"] : [];
  const body: Any = {
    summary: m.title,
    description: [m.agenda, "Created from the Tcipher workspace."].filter(Boolean).join("\n\n"),
    start: { dateTime: localDateTime(m.meeting_date, m.start_time), timeZone: TZ },
    end: { dateTime: localDateTime(m.meeting_date, m.start_time, m.duration_min || 30), timeZone: TZ },
    attendees: [...new Set(people.map((p: Any) => p.email).filter(Boolean))].map((email) => ({ email })),
    recurrence: rrule,
  };
  if (withMeet) body.conferenceData = { createRequest: { requestId: crypto.randomUUID(), conferenceSolutionKey: { type: "hangoutsMeet" } } };
  else if (m.link && !meetCode(m.link)) body.location = m.link;
  return body;
}
const meetCode = (link: string) => { const x = String(link || "").match(/meet\.google\.com\/([a-z]{3}-[a-z]{4}-[a-z]{3})/i); return x ? x[1].toLowerCase() : null; };

async function saveEvent(callerId: string, meetingId: string) {
  const m = must(await db.from("meetings").select("*").eq("id", meetingId).single());
  const token = await accessFor(callerId);
  const body = await eventBody(m, !meetCode(m.link));
  const ev = (m.google_event_id && m.google_owner === callerId)
    ? await g(token, CAL + "/" + encodeURIComponent(m.google_event_id) + "?conferenceDataVersion=1&sendUpdates=all", { method: "PATCH", body: JSON.stringify(body) })
    : await g(token, CAL + "?conferenceDataVersion=1&sendUpdates=all", { method: "POST", body: JSON.stringify(body) });
  const patch: Any = { google_event_id: ev.id, google_owner: callerId, google_html_link: ev.htmlLink || "" };
  if (ev.hangoutLink) patch.link = ev.hangoutLink;
  return must(await db.from("meetings").update(patch).eq("id", meetingId).select().single());
}
async function deleteEvent(meetingId: string) {
  const m = must(await db.from("meetings").select("*").eq("id", meetingId).single());
  if (!m.google_event_id || !m.google_owner) return;
  const token = await accessFor(m.google_owner);
  await g(token, CAL + "/" + encodeURIComponent(m.google_event_id) + "?sendUpdates=all", { method: "DELETE" });
}

/* ---------------- Google Meet joins ---------------- */
async function listAll(token: string, path: string, key: string) {
  let out: Any[] = [], page = "";
  for (let i = 0; i < 10; i++) {
    const r = await g(token, MEET + path + (path.includes("?") ? "&" : "?") + "pageSize=100" + (page ? "&pageToken=" + encodeURIComponent(page) : ""));
    out = out.concat(r[key] || []); page = r.nextPageToken; if (!page) break;
  }
  return out;
}
function matcher(people: Any[]) {
  return (name: string) => {
    const n = String(name || "").trim().toLowerCase(); if (!n) return null;
    const exact = people.find((p) => p.full_name.toLowerCase() === n); if (exact) return exact.id;
    const first = n.split(/\s+/)[0]; const hits = people.filter((p) => p.full_name.toLowerCase().split(/\s+/)[0] === first);
    return hits.length === 1 ? hits[0].id : null;
  };
}
async function importJoins(meetingId: string, days = 30) {
  const m = must(await db.from("meetings").select("*").eq("id", meetingId).single());
  const code = meetCode(m.link);
  if (!code) throw new Error("This meeting doesn’t have a Google Meet link.");
  const owner = m.google_owner || m.created_by;
  const token = await accessFor(owner);
  const people = must(await db.from("profiles").select("id,full_name").eq("is_active", true));
  const match = matcher(people);
  const since = new Date(Date.now() - days * 864e5).toISOString();
  const records = await listAll(token, "conferenceRecords?filter=" + encodeURIComponent('space.meeting_code = "' + code + '" AND start_time >= "' + since + '"'), "conferenceRecords");
  const rows: Any[] = [];
  for (const rec of records) {
    for (const p of await listAll(token, rec.name + "/participants", "participants")) {
      const name = (p.signedinUser && p.signedinUser.displayName) || (p.anonymousUser && p.anonymousUser.displayName) || (p.phoneUser && p.phoneUser.displayName) || "Guest";
      const uid = match(name);
      const sessions = await listAll(token, p.name + "/participantSessions", "participantSessions");
      for (const s of (sessions.length ? sessions : [{ name: p.name, startTime: p.earliestStartTime, endTime: p.latestEndTime }])) {
        if (!s.startTime) continue;
        rows.push({ meeting_id: m.id, user_id: uid, display_name: name, title: m.title, joined_on: dayIn(new Date(s.startTime)), joined_at: s.startTime, left_at: s.endTime || null, source: "Google Meet", external_id: s.name });
      }
    }
  }
  if (rows.length) must(await db.from("meeting_joins").upsert(rows, { onConflict: "external_id", ignoreDuplicates: true }));
  let checkedIn = 0;
  if (m.kind === "Morning scrum") {
    const first: Record<string, Any> = {};
    for (const r of rows) if (r.user_id) { const k = r.user_id + "|" + r.joined_on; if (!first[k] || r.joined_at < first[k].joined_at) first[k] = r; }
    for (const r of Object.values(first)) {
      const exists = must(await db.from("attendance").select("id").eq("user_id", r.user_id).eq("day", r.joined_on).maybeSingle());
      if (exists) continue;
      const ins = await db.from("attendance").insert({ user_id: r.user_id, day: r.joined_on, check_in: r.joined_at, mode: "Remote", note: "Joined morning scrum (Google Meet)" });
      if (!ins.error) checkedIn++;
    }
  }
  return { joins: rows.length, unmatched: [...new Set(rows.filter((r) => !r.user_id).map((r) => r.display_name))], checkedIn };
}
function occursOn(m: Any, d: string, workingDays: number[], holidays: string[]) {
  if (!m.meeting_date || d < m.meeting_date) return false;
  if (!m.repeat || m.repeat === "Does not repeat") return d === m.meeting_date;
  if (m.repeat === "Every week") return weekday(d) === weekday(m.meeting_date);
  if (m.repeat === "Selected days") return (m.repeat_days || []).includes(weekday(d)) && !holidays.includes(d);
  return workingDays.includes(weekday(d)) && !holidays.includes(d);
}

/* ---------------- handler ---------------- */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    if (!GID || !GSECRET) return json({ error: "Google isn’t set up on the server yet (missing GOOGLE_CLIENT_ID or GOOGLE_CLIENT_SECRET secret)." }, 500);
    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "");

    // Scheduled job: sync everyone + import today's and yesterday's Meet joins
    if (action === "sync_all") {
      if (!CRON || req.headers.get("x-cron-secret") !== CRON) return json({ error: "Not allowed." }, 403);
      const links = must(await db.from("google_links").select("user_id"));
      const result: Any = { synced: 0, failed: 0, joins: 0, checkedIn: 0 };
      for (const l of links) { try { await syncUser(l.user_id); result.synced++; } catch (_) { result.failed++; } }
      const settings = (must(await db.from("settings").select("data").eq("id", 1).maybeSingle()) || { data: {} }).data || {};
      const wd = settings.working_days || [1, 2, 3, 4, 5, 6], hol = (settings.holidays || []).map((h: Any) => h.date);
      const connected = new Set(links.map((l: Any) => l.user_id));
      const meetings = must(await db.from("meetings").select("*").ilike("link", "%meet.google.com%"));
      for (const m of meetings) {
        const owner = m.google_owner || m.created_by;
        if (!connected.has(owner)) continue;
        if (!occursOn(m, today(), wd, hol) && !occursOn(m, addDays(today(), -1), wd, hol)) continue;
        try { const r = await importJoins(m.id, 2); result.joins += r.joins; result.checkedIn += r.checkedIn; } catch (_) { /* keep going */ }
      }
      return json(result);
    }

    // Everything else: a signed-in, active workspace user
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: who } = await db.auth.getUser(jwt);
    if (!who || !who.user) return json({ error: "Sign in again." }, 401);
    const me = must(await db.from("profiles").select("id,email,is_admin,is_active").eq("id", who.user.id).single());
    if (!me.is_active) return json({ error: "Your account is turned off." }, 403);

    if (action === "connect") {
      const tok = await googleTokenRequest({ grant_type: "authorization_code", code: String(body.code || ""), redirect_uri: "postmessage" });
      const info = await g(tok.access_token, "https://openidconnect.googleapis.com/v1/userinfo");
      const existing = must(await db.from("google_tokens").select("refresh_token").eq("user_id", me.id).maybeSingle());
      const refresh = tok.refresh_token || (existing && existing.refresh_token);
      const granted = String(tok.scope || "");
      if (!granted.includes("calendar.events")) return json({ error: "Calendar access wasn’t allowed. Click Connect Google again and tick the box for Google Calendar on Google’s permissions screen." }, 400);
      if (!refresh) return json({ error: "Google didn’t give permanent access. Remove “Tcipher Workspace” at myaccount.google.com/permissions, then click Connect Google again." }, 400);
      must(await db.from("google_tokens").upsert({ user_id: me.id, refresh_token: refresh, scopes: tok.scope || "", updated_at: new Date().toISOString() }));
      must(await db.from("google_links").upsert({ user_id: me.id, google_email: info.email || "", connected_at: new Date().toISOString(), last_error: "" }));
      let n = 0, warning = "";
      try { n = await syncUser(me.id); } catch (e) { warning = String((e as Error)?.message || e); }
      return json({ ok: true, email: info.email || "", events: n, warning, scopes: tok.scope || "" });
    }
    if (action === "disconnect") {
      const row = must(await db.from("google_tokens").select("refresh_token").eq("user_id", me.id).maybeSingle());
      if (row) await fetch("https://oauth2.googleapis.com/revoke?token=" + encodeURIComponent(row.refresh_token), { method: "POST" }).catch(() => {});
      await db.from("calendar_events").delete().eq("user_id", me.id);
      await db.from("google_tokens").delete().eq("user_id", me.id);
      await db.from("google_links").delete().eq("user_id", me.id);
      return json({ ok: true });
    }
    if (action === "sync") return json({ ok: true, events: await syncUser(me.id) });

    const meetingId = String(body.meeting_id || "");
    if (!meetingId) return json({ error: "Missing meeting." }, 400);
    const m = must(await db.from("meetings").select("created_by,google_owner").eq("id", meetingId).single());
    const allowed = me.is_admin || m.created_by === me.id || m.google_owner === me.id;
    if (!allowed) return json({ error: "Only the organiser or an admin can do this." }, 403);

    if (action === "save_event") return json({ ok: true, meeting: await saveEvent(me.id, meetingId) });
    if (action === "delete_event") { await deleteEvent(meetingId); return json({ ok: true }); }
    if (action === "import_joins") return json({ ok: true, ...(await importJoins(meetingId, 30)) });
    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500);
  }
});
