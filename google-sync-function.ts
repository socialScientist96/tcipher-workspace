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
function publicKey(): string {
  try { const k = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}"); if (k && k.default) return k.default; } catch (_) { /* legacy */ }
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
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
// (2026-11ed) like WhatsApp: Google tells us when a calendar changes (push, see calWatch) and only what changed in the
// last few minutes is fetched (calChanges). Google says a few pushes can go missing, so the scheduled job also asks for
// the last 35 minutes of changes, and once a day reads the whole window again (calFull). Without push (setup not run,
// or Google refused), everything works as before: a full read each time.
async function syncUser(userId: string, mode: "full" | "auto" = "full") {
  try { return await syncUserInner(userId, mode); }
  catch (e) {
    const msg = String((e as Error)?.message || e);
    await db.from("google_links").update({ last_error: "Sync failed: " + msg.slice(0, 300) }).eq("user_id", userId);
    throw e;
  }
}
async function syncUserInner(userId: string, mode: "full" | "auto") {
  // someone who allowed only email (no calendar) has nothing to sync here: that isn't a problem
  const link = must(await db.from("google_links").select("scopes").eq("user_id", userId).maybeSingle());
  if (link && link.scopes && !String(link.scopes).includes("calendar")) {
    await db.from("google_links").update({ last_sync_at: new Date().toISOString(), last_error: "" }).eq("user_id", userId);
    try { await syncReplies(userId); } catch (e) { await db.from("google_links").update({ last_error: "Reply check failed: " + String((e as Error)?.message || e).slice(0, 200) }).eq("user_id", userId); }
    return 0;
  }
  const token = await accessFor(userId);
  const ch = await calChannel(userId);
  let n = 0;
  const live = ch && ch.cal_channel_expires && Date.parse(ch.cal_channel_expires) > Date.now();
  const fresh = ch && ch.cal_full_at && Date.now() - Date.parse(ch.cal_full_at) < 24 * 3600e3;
  if (mode === "auto" && live && fresh) { try { n = await calChanges(userId, token, 35); } catch (_) { n = await calFull(userId, token); } }
  else n = await calFull(userId, token);
  if (ch) { try { await calWatch(userId, token, ch); } catch (_) { /* push is a bonus: the scheduled job still syncs */ } }
  await db.from("google_links").update({ last_sync_at: new Date().toISOString(), last_error: "" }).eq("user_id", userId);
  try { await syncReplies(userId); } catch (e) { await db.from("google_links").update({ last_error: "Reply check failed: " + String((e as Error)?.message || e).slice(0, 200) }).eq("user_id", userId); }
  return n;
}
function calWindow() {
  const fromDay = addDays(today(), -7), toDay = addDays(today(), 45);
  return { fromDay, timeMin: new Date(fromDay + "T00:00:00+05:30").toISOString(), timeMax: new Date(toDay + "T23:59:59+05:30").toISOString() };
}
async function calList(token: string, extra: string) {
  const w = calWindow(), items: Any[] = [];
  let page = "";
  for (let i = 0; i < 8; i++) {
    const r = await g(token, CAL + "?singleEvents=true&maxResults=250&timeMin=" + encodeURIComponent(w.timeMin) + "&timeMax=" + encodeURIComponent(w.timeMax) + extra + (page ? "&pageToken=" + encodeURIComponent(page) : ""));
    items.push(...(r.items || []));
    page = r.nextPageToken; if (!page) break;
  }
  return items;
}
function calRow(userId: string, e: Any) {
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
}
const CAL_COLS = "google_event_id,ical_uid,title,starts_at,ends_at,all_day,start_date,end_date,meet_link,html_link,location,organizer_email,attendee_emails";
const calTime = (v: unknown) => v ? Date.parse(String(v)) : 0;
const calKey = (e: Any) => JSON.stringify([e.ical_uid || "", e.title || "", calTime(e.starts_at), calTime(e.ends_at), !!e.all_day, e.start_date, e.end_date, e.meet_link || "", e.html_link || "",
  e.location || "", e.organizer_email || "", [...(e.attendee_emails || [])].sort()]);
// (2026-11dz) write only what changed: new or changed events are upserted, removed ones deleted
async function calWrite(userId: string, rows: Any[], have: Any[], gone: string[]) {
  const old = new Map(have.map((e) => [e.google_event_id, calKey(e)]));
  const changed = rows.filter((r: Any) => old.get(r.google_event_id) !== calKey(r));
  gone = gone.filter((id) => old.has(id));
  for (let i = 0; i < gone.length; i += 200) must(await db.from("calendar_events").delete().eq("user_id", userId).in("google_event_id", gone.slice(i, i + 200)));
  for (let i = 0; i < changed.length; i += 200) must(await db.from("calendar_events").upsert(changed.slice(i, i + 200), { onConflict: "user_id,google_event_id" }));
  return changed.length + gone.length;
}
// the whole window (7 days back, 45 ahead)
async function calFull(userId: string, token: string) {
  const items = await calList(token, "");
  const rows = items.filter((e) => e.status !== "cancelled").map((e) => calRow(userId, e));
  const have = (must(await db.from("calendar_events").select(CAL_COLS).eq("user_id", userId).gte("start_date", calWindow().fromDay)) || []) as Any[];
  const keep = new Set(rows.map((r: Any) => r.google_event_id));
  await calWrite(userId, rows, have, have.map((e) => e.google_event_id).filter((id: string) => !keep.has(id)));
  await db.from("google_tokens").update({ cal_full_at: new Date().toISOString() }).eq("user_id", userId).then(() => {}, () => {});
  return rows.length;
}
// only events changed in the last few minutes (Google includes deleted ones)
async function calChanges(userId: string, token: string, minutes: number) {
  const since = new Date(Date.now() - minutes * 60000).toISOString();
  const items = await calList(token, "&showDeleted=true&updatedMin=" + encodeURIComponent(since));
  if (!items.length) return 0;
  const rows = items.filter((e) => e.status !== "cancelled").map((e) => calRow(userId, e));
  const gone = items.filter((e) => e.status === "cancelled").map((e) => e.id);
  const ids = items.map((e) => e.id), have: Any[] = [];
  for (let i = 0; i < ids.length; i += 200) have.push(...(must(await db.from("calendar_events").select(CAL_COLS).eq("user_id", userId).in("google_event_id", ids.slice(i, i + 200))) || []));
  return await calWrite(userId, rows, have, gone);
}
// push: Google calls this function when the calendar changes. A subscription lasts about a week; renewed a day early.
async function calChannel(userId: string) {
  const r = await db.from("google_tokens").select("cal_channel_id,cal_channel_resource,cal_channel_expires,cal_full_at").eq("user_id", userId).maybeSingle();
  return r.error ? null : (r.data || null);   // null: the 2026-11ed columns aren't there yet
}
async function calWatch(userId: string, token: string, ch: Any) {
  if (ch.cal_channel_id && ch.cal_channel_expires && Date.parse(ch.cal_channel_expires) > Date.now() + 24 * 3600e3) return;
  const id = crypto.randomUUID(), secret = randomToken();
  const r = await g(token, CAL + "/watch", { method: "POST", body: JSON.stringify({ id, type: "web_hook", token: secret,
    address: Deno.env.get("SUPABASE_URL") + "/functions/v1/google-sync", params: { ttl: String(7 * 86400) } }) });
  const until = r && r.expiration ? new Date(Number(r.expiration)).toISOString() : new Date(Date.now() + 6 * 86400e3).toISOString();
  must(await db.from("google_tokens").update({ cal_channel_id: id, cal_channel_resource: r.resourceId || "", cal_channel_token: secret, cal_channel_expires: until }).eq("user_id", userId));
  await db.from("google_links").update({ cal_live_until: until }).eq("user_id", userId);
  if (ch.cal_channel_id) await calUnwatch(token, ch.cal_channel_id, ch.cal_channel_resource);
}
async function calUnwatch(token: string, id: string, resource: string) {
  if (!id || !resource) return;
  try { await g(token, "https://www.googleapis.com/calendar/v3/channels/stop", { method: "POST", body: JSON.stringify({ id, resourceId: resource }) }); } catch (_) { /* it runs out by itself */ }
}
// a push from Google: no body, only headers. Answered at once; the fetch runs right after.
const pushBusy = new Map<string, number>();
async function calPush(req: Request) {
  const id = req.headers.get("x-goog-channel-id") || "", state = req.headers.get("x-goog-resource-state") || "";
  if (state !== "exists") return;   // "sync" just confirms a new subscription
  const r = await db.from("google_tokens").select("user_id,cal_channel_token").eq("cal_channel_id", id).maybeSingle();
  if (r.error || !r.data || !r.data.cal_channel_token || r.data.cal_channel_token !== (req.headers.get("x-goog-channel-token") || "")) return;
  const userId = r.data.user_id;
  if ((pushBusy.get(userId) || 0) > Date.now() - 3000) return;   // a burst of changes: the first fetch covers them
  pushBusy.set(userId, Date.now());
  await new Promise((ok) => setTimeout(ok, 1500));   // let a burst of edits land first
  try {
    const token = await accessFor(userId);
    await calChanges(userId, token, 10);
    await db.from("google_links").update({ last_sync_at: new Date().toISOString(), last_error: "" }).eq("user_id", userId);
  } catch (_) { /* the scheduled job catches up */ }
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
    // (2026-11do) people outside the company (a lead booked for a demo) are invited too
    attendees: [...new Set([...people.map((p: Any) => String(p.email || "").toLowerCase()), ...(m.guest_emails || []).map((e: string) => String(e || "").trim().toLowerCase())].filter(Boolean))].map((email) => ({ email })),
    recurrence: rrule,
  };
  if (withMeet) body.conferenceData = { createRequest: { requestId: crypto.randomUUID(), conferenceSolutionKey: { type: "hangoutsMeet" } } };
  else if (m.link && !meetCode(m.link)) body.location = m.link;
  return body;
}
const meetCode = (link: string) => { const x = String(link || "").match(/meet\.google\.com\/([a-z]{3}-[a-z]{4}-[a-z]{3})/i); return x ? x[1].toLowerCase() : null; };

async function saveEvent(callerId: string, meetingId: string) {
  const m = must(await db.from("meetings").select("*").eq("id", meetingId).single());
  const body = await eventBody(m, !meetCode(m.link));
  // an event that already exists is updated in its owner's calendar, whoever edits it here (an admin, the creator),
  // instead of a second copy being created in the editor's calendar
  const owner = m.google_event_id && m.google_owner ? m.google_owner : callerId;
  const token = await accessFor(owner);
  const ev = (m.google_event_id && m.google_owner)
    ? await g(token, CAL + "/" + encodeURIComponent(m.google_event_id) + "?conferenceDataVersion=1&sendUpdates=all", { method: "PATCH", body: JSON.stringify(body) })
    : await g(token, CAL + "?conferenceDataVersion=1&sendUpdates=all", { method: "POST", body: JSON.stringify(body) });
  const patch: Any = { google_event_id: ev.id, google_owner: owner, google_html_link: ev.htmlLink || "" };
  if (ev.hangoutLink) patch.link = ev.hangoutLink;
  return must(await db.from("meetings").update(patch).eq("id", meetingId).select().single());
}
async function deleteEvent(meetingId: string) {
  const m = must(await db.from("meetings").select("*").eq("id", meetingId).single());
  if (!m.google_event_id || !m.google_owner) return;
  const token = await accessFor(m.google_owner);
  try { await g(token, CAL + "/" + encodeURIComponent(m.google_event_id) + "?sendUpdates=all", { method: "DELETE" }); }
  catch (e) { if (!/not found|deleted|Google error (404|410)/i.test(String((e as Error)?.message || e))) throw e; }   // already gone in Google: fine
}

/* ---------------- Gemini notes, transcript and recording (2026-11do) ----------------
   Google saves them in the organiser's Drive after the call (it can take a while). Found through the Meet API
   (recordings, transcripts, smart notes) and the calendar event's attachments ("Notes by Gemini"). With the
   drive.meet.readonly permission the notes' text is copied into the meeting, and onto the lead as an activity. */
const docId = (u: string) => { const x = String(u || "").match(/\/d\/([a-zA-Z0-9_-]{20,})/); return x ? x[1] : ""; };
async function docText(token: string, id: string): Promise<{ text: string; needScope: boolean }> {
  const res = await fetch("https://www.googleapis.com/drive/v3/files/" + encodeURIComponent(id) + "/export?mimeType=text/plain", { headers: { Authorization: "Bearer " + token } });
  if (res.ok) return { text: (await res.text()).replace(/\r/g, "").replace(/\n{3,}/g, "\n\n").trim().slice(0, 20000), needScope: false };
  return { text: "", needScope: res.status === 401 || res.status === 403 };
}
async function fetchNotes(meetingId: string) {
  const m = must(await db.from("meetings").select("*").eq("id", meetingId).single());
  const owner = m.google_owner || m.created_by;
  const token = await accessFor(owner);
  const found: Any = { notes: m.notes_doc_url || "", transcript: m.transcript_url || "", recording: m.recording_url || "" };
  let notesId = docId(found.notes);
  const code = meetCode(m.link);
  if (code) {
    const since = new Date(new Date(m.meeting_date + "T00:00:00+05:30").getTime() - 864e5).toISOString();
    let records: Any[] = [];
    try { records = await listAll(token, "conferenceRecords?filter=" + encodeURIComponent('space.meeting_code = "' + code + '" AND start_time >= "' + since + '"'), "conferenceRecords"); } catch (_) { /* no access to this call */ }
    for (const rec of records.slice(-3)) {
      try { for (const r of await listAll(token, rec.name + "/recordings", "recordings")) if (r.driveDestination && r.driveDestination.exportUri) found.recording = r.driveDestination.exportUri; } catch (_) { /* none */ }
      try { for (const t of await listAll(token, rec.name + "/transcripts", "transcripts")) if (t.docsDestination && t.docsDestination.exportUri) found.transcript = t.docsDestination.exportUri; } catch (_) { /* none */ }
      try { for (const n of await listAll(token, rec.name + "/smartNotes", "smartNotes")) if (n.docsDestination) { found.notes = n.docsDestination.exportUri || found.notes; notesId = n.docsDestination.document || docId(found.notes) || notesId; } } catch (_) { /* not offered by Google for this account */ }
    }
  }
  if (m.google_event_id) {
    try {
      const ev = await g(token, CAL + "/" + encodeURIComponent(m.google_event_id));
      for (const a of (ev && ev.attachments) || []) {
        const title = String(a.title || "");
        if (/gemini|notes/i.test(title) && /document/.test(String(a.mimeType || "document"))) { found.notes = found.notes || a.fileUrl; notesId = notesId || a.fileId || docId(a.fileUrl); }
        else if (/transcript/i.test(title)) found.transcript = found.transcript || a.fileUrl;
        else if (/video|recording/i.test(String(a.mimeType || "") + " " + title)) found.recording = found.recording || a.fileUrl;
      }
    } catch (_) { /* event gone or no access */ }
  }
  let text = "", needScope = false;
  if (notesId && !String(m.notes || "").trim()) { const r = await docText(token, notesId); text = r.text; needScope = r.needScope; }
  const patch: Any = { notes_doc_url: found.notes || "", transcript_url: found.transcript || "", recording_url: found.recording || "", notes_checked_at: new Date().toISOString() };
  if (text) patch.notes = text;
  const meeting = must(await db.from("meetings").update(patch).eq("id", meetingId).select().single());
  let activity = null;
  if (text && m.lead_id) {
    const r = await db.from("activities").insert({ kind: "Demo", direction: "Outbound", activity_date: m.meeting_date, owner_id: owner, lead_id: m.lead_id,
      subject: "Demo notes: " + m.title, outcome: text.slice(0, 4000) + (found.recording ? "\n\nRecording: " + found.recording : "") }).select().single();
    if (!r.error) activity = r.data;
  }
  return { meeting, activity, found: { notes: !!found.notes, transcript: !!found.transcript, recording: !!found.recording }, copied: !!text, needScope };
}

/* ---------------- public demo booking page (2026-11dq) ----------------
   book.html asks for free times ("public_slots") and books one ("public_book") without signing in. Only times
   are shown, never names or events. The time is checked again when booking; the demo goes to whoever on the demo
   team is free (Google-connected first, then the lighter day), and the invite + Meet link go from their calendar. */
const hmMin = (t: string) => { const [a, b] = String(t || "0:0").split(":").map(Number); return (a || 0) * 60 + (b || 0); };
const minHM = (n: number) => String(Math.floor(n / 60)).padStart(2, "0") + ":" + String(n % 60).padStart(2, "0");
const minIn = (d: Date) => hmMin(new Intl.DateTimeFormat("en-GB", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(d));
const isUuid = (v: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(v || ""));
async function demoConfig() {
  const st = (must(await db.from("settings").select("data").eq("id", 1).maybeSingle()) || { data: {} }).data || {};
  const ids: string[] = (Array.isArray(st.demo_team) ? st.demo_team : []).filter(isUuid);
  const people = ids.length ? (must(await db.from("profiles").select("id,full_name,is_active").in("id", ids)) || []) : [];
  return {
    on: st.demo_public === true, team: people.filter((p: Any) => p.is_active).map((p: Any) => p.id) as string[], people,
    len: Math.max(15, +st.demo_minutes || 45), buffer: st.demo_buffer_min != null && st.demo_buffer_min !== "" ? Math.max(0, +st.demo_buffer_min) : 15,
    ahead: Math.min(30, Math.max(3, +st.demo_days_ahead || 10)), notice: Math.max(0, st.demo_notice_hours != null && st.demo_notice_hours !== "" ? +st.demo_notice_hours : 3),
    start: hmMin(st.work_start || "10:00"), end: hmMin(st.work_end || "18:00"), wd: (st.working_days || [1, 2, 3, 4, 5, 6]) as number[],
    hol: ((st.holidays || []) as Any[]).map((h) => h.date) as string[], company: String(st.company || "Tcipher Technologies"),
  };
}
async function demoFree(C: Any) {
  const t0 = today(), to = addDays(t0, C.ahead), team: string[] = C.team;
  const busy: Record<string, Record<string, number[][]>> = {};
  const add = (u: string, d: string, a: number, b: number) => { const x = busy[u] = busy[u] || {}; (x[d] = x[d] || []).push([a, b]); };
  if (team.length) {
    const ms = must(await db.from("meetings").select("meeting_date,start_time,duration_min,repeat,repeat_days,attendees").not("start_time", "is", null).lte("meeting_date", to)) || [];
    for (const m of ms) {
      const rep = m.repeat && m.repeat !== "Does not repeat";
      if (!rep && m.meeting_date < t0) continue;
      const who = (m.attendees || []).length ? (m.attendees as string[]).filter((a) => team.includes(a)) : team;
      if (!who.length) continue;
      for (let d = rep ? t0 : m.meeting_date; d <= to; d = addDays(d, 1)) {
        if (occursOn(m, d, C.wd, C.hol)) { const a = hmMin(m.start_time); for (const u of who) add(u, d, a, a + (+m.duration_min || 30)); }
        if (!rep) break;
      }
    }
    const evs = must(await db.from("calendar_events").select("user_id,starts_at,ends_at").in("user_id", team).eq("all_day", false).lte("start_date", to).gte("end_date", t0)) || [];
    for (const e of evs) {
      if (!e.starts_at) continue;
      const a = new Date(e.starts_at), b = new Date(e.ends_at || e.starts_at), first = dayIn(a), last = dayIn(b);
      for (let d = first, i = 0; d <= last && i < 40; d = addDays(d, 1), i++) add(e.user_id, d, d === first ? minIn(a) : 0, d === last ? minIn(b) : 1440);
    }
    const lv = must(await db.from("leave_requests").select("user_id,start_date,end_date,type").in("user_id", team).eq("status", "Approved").lte("start_date", to).gte("end_date", t0)) || [];
    for (const l of lv) if (l.type !== "Work from home") for (let d = l.start_date, i = 0; d <= l.end_date && i < 60; d = addDays(d, 1), i++) add(l.user_id, d, 0, 1440);
  }
  const nowAbs = minIn(new Date()) + C.notice * 60;   // minutes from the start of today
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
async function publicSlots(body: Any) {
  const C = await demoConfig();
  if (!C.on || !C.team.length) return { open: false, company: C.company };
  const { days } = await demoFree(C);
  let lead: Any = null;
  if (isUuid(body.lead)) {
    const l = must(await db.from("leads").select("name,email,phone,company").eq("id", body.lead).maybeSingle());
    if (l) lead = { name: l.name || "", email: l.email || "", phone: l.phone || "", company: l.company || "" };
  }
  return { open: true, company: C.company, minutes: C.len, timezone: "India (IST)", lead,
    days: days.map((x: Any) => ({ day: x.day, times: x.slots.map((s: Any) => minHM(s.start)) })) };
}
async function publicBook(body: Any, ip: string) {
  const clean = (v: unknown, n: number) => String(v ?? "").replace(/[\u0000-\u001f]+/g, " ").trim().slice(0, n);
  const name = clean(body.name, 80), email = clean(body.email, 120).toLowerCase(), phone = clean(body.phone, 24), company = clean(body.company, 100), note = clean(body.note, 600);
  const day = clean(body.day, 10), time = clean(body.time, 5);
  if (clean(body.website, 200)) return { ok: true, day, time };   // hidden field only robots fill in
  if (name.length < 2) throw new Error("Please enter your name.");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) throw new Error("Please enter a valid email address.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !/^\d{2}:\d{2}$/.test(time)) throw new Error("Please pick a time.");
  const hourAgo = new Date(Date.now() - 3600e3).toISOString(), weekAgo = new Date(Date.now() - 7 * 864e5).toISOString();
  const tries = (await db.from("booking_log").select("id", { count: "exact", head: true }).eq("ip", ip).gte("at", hourAgo)).count || 0;
  if (tries >= 5) throw new Error("Too many tries from this connection. Please try again in an hour, or reply to our email.");
  await db.from("booking_log").insert({ ip, email, ok: false });
  const booked = (await db.from("booking_log").select("id", { count: "exact", head: true }).eq("email", email).eq("ok", true).gte("at", weekAgo)).count || 0;
  if (booked >= 2) throw new Error("You already have a demo booked with us. Check your email for the invite, or reply to it to change the time.");
  const C = await demoConfig();
  if (!C.on || !C.team.length) throw new Error("Online booking is closed right now. Please reply to our email and we’ll find a time.");
  const { days, busy } = await demoFree(C);
  const slot = (days.find((x: Any) => x.day === day)?.slots || []).find((x: Any) => x.start === hmMin(time));
  if (!slot) { const e = new Error("That time was just taken. Please pick another one."); (e as Any).status = 409; throw e; }
  const linked = new Set(((must(await db.from("google_links").select("user_id").in("user_id", slot.free)) || []) as Any[]).map((l) => l.user_id));
  const who = (slot.free as string[]).slice().sort((a, b) => (+linked.has(b) - +linked.has(a)) || (((busy[a] || {})[day] || []).length - ((busy[b] || {})[day] || []).length))[0];
  // the lead: the one the personal link was for, else the newest lead with this email, else a new one
  let lead: Any = null;
  if (isUuid(body.lead)) lead = must(await db.from("leads").select("*").eq("id", body.lead).maybeSingle());
  if (!lead) lead = (must(await db.from("leads").select("*").ilike("email", email.replace(/[%_\\]/g, "\\$&")).order("created_at", { ascending: false }).limit(1)) || [])[0] || null;
  if (lead) {
    const patch: Any = {};
    if (!lead.email) patch.email = email;
    if (!lead.phone && phone) patch.phone = phone;
    if (!lead.company && company) patch.company = company;
    if (lead.pipeline === "Instagram" && ["Lead", "Called", "Picked up", "Qualified"].includes(lead.status)) patch.status = "Demo booked";
    if (Object.keys(patch).length) lead = must(await db.from("leads").update(patch).eq("id", lead.id).select().single());
  } else {
    lead = must(await db.from("leads").insert({ name, email, phone, company, source: "Website", status: "New", pipeline: "General", created_by: null,
      notes: "Booked a demo on the booking page." + (note ? "\n\n" + note : "") }).select().single());
  }
  const title = "Demo: " + (lead.name || name) + ((lead.company || company) ? " (" + (lead.company || company) + ")" : "");
  const meeting = must(await db.from("meetings").insert({ title, kind: "Sales demo", repeat: "Does not repeat", meeting_date: day, start_time: time, duration_min: C.len,
    attendees: [who], created_by: who, lead_id: lead.id, guest_emails: [email], agenda: [note ? "From " + (lead.name || name) + ": " + note : "", "Booked by the lead on the booking page."].filter(Boolean).join("\n\n") }).select().single());
  let invited = false, link = "";
  if (linked.has(who)) { try { const m2 = await saveEvent(who, meeting.id); invited = true; link = m2.link || ""; } catch (_) { /* the team is told below; they can send it from the meeting */ } }
  const t12 = (() => { const m = hmMin(time), h = Math.floor(m / 60); return ((h % 12) || 12) + ":" + String(m % 60).padStart(2, "0") + (h < 12 ? " am" : " pm"); })();
  const when = new Date(day + "T12:00:00Z").toLocaleDateString("en-IN", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }) + ", " + t12;
  const tell = [...new Set([who, lead.owner_id, lead.sales_owner_id].filter(Boolean))];
  if (tell.length) await db.from("notifications").insert(tell.map((u) => ({ user_id: u, title: "Demo booked by a lead", created_by: null,
    body: title + " · " + when + (u === who ? "" : " · with " + String((C.people.find((p: Any) => p.id === who) || {}).full_name || "")) + (invited ? "" : " · no Google invite was sent: open the meeting to send it"), tbl: "meetings", entity_id: meeting.id })));
  await db.from("activities").insert({ kind: "Demo", direction: "Inbound", activity_date: today(), owner_id: who, lead_id: lead.id, subject: "Booked a demo for " + when + " on the booking page", outcome: note });
  await db.from("booking_log").insert({ ip, email, ok: true });
  const first = String((C.people.find((p: Any) => p.id === who) || {}).full_name || "").split(" ")[0];
  return { ok: true, day, time, minutes: C.len, with: first, invited, link };
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

/* ---------------- email (Gmail) ---------------- */
const GMAIL = "https://gmail.googleapis.com/gmail/v1/users/me/";
function b64(bytes: Uint8Array): string { let s = ""; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(s); }
const b64url = (str: string) => b64(new TextEncoder().encode(str)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const encHeader = (v: string) => /^[\x20-\x7e]*$/.test(v) ? v : "=?UTF-8?B?" + b64(new TextEncoder().encode(v)) + "?=";
const wrap76 = (x: string) => x.replace(/.{1,76}/g, "$&\r\n");
function fromB64url(data: string): string {
  const bin = atob(String(data || "").replace(/-/g, "+").replace(/_/g, "/"));
  const bytes = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}
const escHtml = (t: string) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const toHtml = (t: string) => "<div style=\"font-family:Arial,sans-serif;font-size:14px;line-height:1.5\">" +
  escHtml(t).replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1">$1</a>').replace(/\n/g, "<br>") + "</div>";
async function gmailScopes(userId: string) {
  const l = must(await db.from("google_links").select("scopes").eq("user_id", userId).maybeSingle());
  const sc = String((l && l.scopes) || "");
  return { send: sc.includes("gmail.send"), read: sc.includes("gmail.readonly") };
}
async function hasGmail(userId: string) { return (await gmailScopes(userId)).send; }
async function sendEmail(me: Any, body: Any, jwt: string) {
  if (!(await hasGmail(me.id))) throw new Error("Email isn’t allowed yet. In My profile, click Reconnect Google and tick the Gmail boxes.");
  const to = String(body.to || "").split(/[,;]/).map((x: string) => x.trim()).filter(Boolean);
  const cc = String(body.cc || "").split(/[,;]/).map((x: string) => x.trim()).filter(Boolean);
  if (!to.length || to.some((x: string) => !/^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$/.test(x))) throw new Error("Check the email address.");
  if (cc.some((x: string) => !/^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$/.test(x))) throw new Error("Check the Cc address.");
  const subject = String(body.subject || "").slice(0, 250), text = String(body.body || "").slice(0, 100000);
  if (!subject.trim()) throw new Error("Add a subject.");
  const tbl = String(body.tbl || ""), entity = body.entity_id || null;
  // attachments: files already uploaded to the record (max 20 MB together)
  const files: Any[] = [];
  let total = 0;
  // attachments: only files the sender can see in the app (checked with their own sign-in, so the database's rules apply)
  const fileIds = Array.isArray(body.file_ids) ? body.file_ids.slice(0, 10) : [];
  const asUser = fileIds.length ? createClient(Deno.env.get("SUPABASE_URL")!, publicKey(), { global: { headers: { Authorization: "Bearer " + jwt } }, auth: { persistSession: false, autoRefreshToken: false } }) : null;
  if (asUser && !publicKey()) throw new Error("Attachments can’t be checked on the server (no public key). Send without attachments.");
  for (const fid of fileIds) {
    const visible = asUser ? (await asUser.from("files").select("id").eq("id", fid).maybeSingle()).data : null;
    if (!visible) throw new Error("One of the attachments isn’t available to you.");
    const f = must(await db.from("files").select("*").eq("id", fid).maybeSingle()); if (!f) continue;
    const dl = await db.storage.from("files").download(f.path); if (dl.error || !dl.data) throw new Error("Couldn’t attach " + f.name);
    const bytes = new Uint8Array(await dl.data.arrayBuffer()); total += bytes.length;
    if (total > 20 * 1024 * 1024) throw new Error("Attachments are over 20 MB. Remove some, or share a link instead.");
    files.push({ name: cleanHeader(f.name), mime: cleanHeader(f.mime || "application/octet-stream"), data: bytes });
  }
  // replying inside an existing conversation
  let threadId = "", inReplyTo = "";
  if (body.reply_to) {
    const prev = must(await db.from("emails").select("*").eq("id", body.reply_to).maybeSingle());
    if (prev && prev.user_id === me.id) { threadId = prev.gmail_thread_id || ""; inReplyTo = prev.rfc_message_id || ""; }
  }
  const token = await accessFor(me.id);
  const link = must(await db.from("google_links").select("google_email").eq("user_id", me.id).maybeSingle());
  const fromAddr = (link && link.google_email) || me.email;
  const boundary = "tc_" + crypto.randomUUID().replace(/-/g, ""), alt = "alt_" + crypto.randomUUID().replace(/-/g, "");
  const head = [
    "From: " + encHeader(me.full_name || "") + " <" + fromAddr + ">",
    "To: " + to.join(", "), ...(cc.length ? ["Cc: " + cc.join(", ")] : []),
    "Subject: " + encHeader(subject), "MIME-Version: 1.0",
    ...(inReplyTo ? ["In-Reply-To: " + inReplyTo, "References: " + inReplyTo] : []),
    "Content-Type: multipart/mixed; boundary=\"" + boundary + "\"", "", "--" + boundary,
    "Content-Type: multipart/alternative; boundary=\"" + alt + "\"", "",
    "--" + alt, "Content-Type: text/plain; charset=UTF-8", "Content-Transfer-Encoding: base64", "", wrap76(b64(new TextEncoder().encode(text))),
    "--" + alt, "Content-Type: text/html; charset=UTF-8", "Content-Transfer-Encoding: base64", "", wrap76(b64(new TextEncoder().encode(toHtml(text)))),
    "--" + alt + "--"];
  for (const f of files) head.push("--" + boundary, "Content-Type: " + f.mime + "; name=\"" + encHeader(f.name) + "\"", "Content-Disposition: attachment; filename=\"" + encHeader(f.name) + "\"", "Content-Transfer-Encoding: base64", "", wrap76(b64(f.data)));
  head.push("--" + boundary + "--", "");
  const raw = b64url(head.join("\r\n"));
  const sent = await g(token, GMAIL + "messages/send", { method: "POST", body: JSON.stringify(threadId ? { raw, threadId } : { raw }) });
  // the Message-ID header lets replies thread properly
  let rfc = "";
  try { const meta = await g(token, GMAIL + "messages/" + sent.id + "?format=metadata&metadataHeaders=Message-ID"); rfc = ((meta.payload && meta.payload.headers) || []).find((x: Any) => /^message-id$/i.test(x.name))?.value || ""; } catch (_) { /* fine */ }
  const row = must(await db.from("emails").insert({ user_id: me.id, direction: "out", tbl, entity_id: entity, from_email: fromAddr, to_email: to.join(", "), cc: cc.join(", "),
    subject, body: text, snippet: text.replace(/\s+/g, " ").slice(0, 160), attachments: files.map((f) => ({ name: f.name, size: f.data.length })),
    gmail_message_id: sent.id, gmail_thread_id: sent.threadId, rfc_message_id: rfc }).select().single());
  await logEmailActivity(me.id, tbl, entity, "Outbound", subject, text);
  return row;
}
async function logEmailActivity(userId: string, tbl: string, entity: string | null, direction: string, subject: string, text: string) {
  if (!entity || !["leads", "deals", "clients", "contacts", "proposals"].includes(tbl)) return;
  const a: Any = { kind: "Email", direction, subject: (direction === "Inbound" ? "Reply: " : "") + subject.slice(0, 180), activity_date: today(), owner_id: userId, created_by: userId, outcome: text.replace(/\s+/g, " ").slice(0, 400) };
  if (tbl === "leads") a.lead_id = entity;
  else if (tbl === "deals") a.deal_id = entity;
  else if (tbl === "clients") a.client_id = entity;
  else if (tbl === "contacts") { a.contact_id = entity; const c = must(await db.from("contacts").select("client_id").eq("id", entity).maybeSingle()); if (c && c.client_id) a.client_id = c.client_id; }
  else if (tbl === "proposals") { const p = must(await db.from("proposals").select("deal_id,client_id").eq("id", entity).maybeSingle()); if (p) { a.deal_id = p.deal_id || null; a.client_id = p.client_id || null; } }
  await db.from("activities").insert(a);
}
function plainBody(payload: Any): string {
  const parts: Any[] = []; const walk = (p: Any) => { if (!p) return; parts.push(p); (p.parts || []).forEach(walk); }; walk(payload);
  const plain = parts.find((p) => p.mimeType === "text/plain" && p.body && p.body.data);
  if (plain) return fromB64url(plain.body.data);
  const html = parts.find((p) => p.mimeType === "text/html" && p.body && p.body.data);
  if (html) return fromB64url(html.body.data).replace(/<br\s*\/?>/gi, "\n").replace(/<\/p>/gi, "\n\n").replace(/<[^>]+>/g, "").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
  return "";
}
// Only conversations started from the workspace are read; nothing else in the inbox is touched.
// read one workspace conversation and record anything new in it
async function readThread(userId: string, token: string, tid: string, origin: Any): Promise<{ found: number; checked: boolean; problem: string; stop: boolean }> {
  let th: Any;
  try { th = await g(token, GMAIL + "threads/" + tid + "?format=full"); }
  catch (e) {
    const msg = String((e as Error)?.message || e);
    if (/insufficient|scope|permission|forbidden|403/i.test(msg)) return { found: 0, checked: false, stop: true, problem: "Replies can’t be checked: Gmail reading isn’t allowed for this account. In My profile, click Reconnect Google and tick every box." };
    return { found: 0, checked: false, stop: false, problem: /not found|404/i.test(msg) ? "" : "Some conversations couldn’t be checked: " + msg.slice(0, 160) };
  }
  let found = 0;
  const ids = (th.messages || []).map((m: Any) => m.id);
  const known = new Set(((must(await db.from("emails").select("gmail_message_id").in("gmail_message_id", ids)) || []) as Any[]).map((r) => r.gmail_message_id));
  // (2026-11dp) the same email can reach two people's mailboxes (the lead wrote to both): keep one copy on the record
  const hdrOf = (m: Any, n: string) => ((m.payload && m.payload.headers) || []).find((x: Any) => x.name.toLowerCase() === n)?.value || "";
  const rfcs = (th.messages || []).map((m: Any) => hdrOf(m, "message-id")).filter(Boolean);
  const knownRfc = new Set(rfcs.length && origin.entity_id ? ((must(await db.from("emails").select("rfc_message_id").eq("tbl", origin.tbl).eq("entity_id", origin.entity_id).in("rfc_message_id", rfcs)) || []) as Any[]).map((r) => r.rfc_message_id) : []);
  for (const m of th.messages || []) {
    if (known.has(m.id) || (m.labelIds || []).includes("DRAFT")) continue;
    if (hdrOf(m, "message-id") && knownRfc.has(hdrOf(m, "message-id"))) continue;
    const hd = (n: string) => hdrOf(m, n);
    const mine = (m.labelIds || []).includes("SENT");
    const text = plainBody(m.payload).slice(0, 100000);
    const row = { user_id: userId, direction: mine ? "out" : "in", tbl: origin.tbl, entity_id: origin.entity_id, from_email: hd("from"), to_email: hd("to"), cc: hd("cc"),
      subject: hd("subject") || origin.subject, body: text, snippet: String(m.snippet || "").slice(0, 160), gmail_message_id: m.id, gmail_thread_id: tid, rfc_message_id: hd("message-id"),
      sent_at: new Date(+m.internalDate || Date.now()).toISOString() };
    const ins = await db.from("emails").insert(row).select("id").single();
    if (ins.error) continue;
    if (!mine) {
      found++;
      await logEmailActivity(userId, origin.tbl, origin.entity_id, "Inbound", row.subject, text);
      // the notification opens the conversation
      await db.from("notifications").insert({ user_id: userId, title: (origin.fresh ? "Email from " : "Email reply from ") + (row.from_email.replace(/<.*>/, "").trim() || row.from_email), body: (row.subject + " · " + String(m.snippet || "")).slice(0, 200), tbl: "emails", entity_id: ins.data.id });
    }
  }
  return { found, checked: true, problem: "", stop: false };
}
/* ---------------- emails a lead or client sends first (2026-11dp) ----------------
   A new email in someone's inbox is matched by its sender's address against the email saved on leads and deals.
   Only the "From" line of new inbox mail is read to do that; a conversation is imported onto the record only when
   the sender is a lead or deal contact, and from then on it is followed like one started from the workspace. */
let leadMailCache: { at: number; map: Map<string, Any>; recent: string[] } | null = null;
const addrOf = (v: string) => { const x = String(v || "").match(/<([^>]+)>/); return (x ? x[1] : String(v || "")).trim().toLowerCase(); };
async function leadMailMap() {
  if (leadMailCache && Date.now() - leadMailCache.at < 60000) return leadMailCache;
  const map = new Map<string, Any>(), seen: Record<string, string> = {};
  const staff = new Set(((must(await db.from("profiles").select("email")) || []) as Any[]).map((p) => String(p.email || "").toLowerCase()));
  const put = (email: string, tbl: string, id: string, at: string) => {
    const e = String(email || "").trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e) || staff.has(e)) return;
    map.set(e, { tbl, entity_id: id, subject: "", fresh: true }); seen[e] = at > (seen[e] || "") ? at : seen[e];
  };
  // later rows win: the most recently updated lead, and an open deal over its lead
  for (const l of (must(await db.from("leads").select("id,email,updated_at").not("email", "is", null).neq("email", "").order("updated_at", { ascending: true }).limit(10000)) || []) as Any[]) put(l.email, "leads", l.id, l.updated_at || "");
  for (const d of (must(await db.from("deals").select("id,email,stage,updated_at").not("email", "is", null).neq("email", "").neq("stage", "Lost").order("updated_at", { ascending: true }).limit(10000)) || []) as Any[]) put(d.email, "deals", d.id, d.updated_at || "");
  const cutoff = new Date(Date.now() - 90 * 864e5).toISOString();
  const recent = Object.keys(seen).filter((e) => seen[e] >= cutoff).sort((a, b) => seen[b].localeCompare(seen[a])).slice(0, 250);
  leadMailCache = { at: Date.now(), map, recent };
  return leadMailCache;
}
async function importLeadMail(userId: string, token: string, msgs: { id: string; threadId: string }[]): Promise<number> {
  if (!msgs.length) return 0;
  const { map } = await leadMailMap(); if (!map.size) return 0;
  const done = new Set<string>(); let found = 0;
  for (const m of msgs.slice(0, 40)) {
    if (done.has(m.threadId)) continue;
    let meta: Any;
    try { meta = await g(token, GMAIL + "messages/" + m.id + "?format=metadata&metadataHeaders=From"); } catch (_) { continue; }
    const from = addrOf(((meta.payload && meta.payload.headers) || []).find((x: Any) => x.name.toLowerCase() === "from")?.value || "");
    const origin = map.get(from); if (!origin) continue;
    done.add(m.threadId);
    found += (await readThread(userId, token, m.threadId, { ...origin })).found;
  }
  return found;
}
async function searchLeadMail(userId: string, token: string, known: Map<string, Any>): Promise<number> {
  const { recent } = await leadMailMap(); if (!recent.length) return 0;
  const stored = new Set(((must(await db.from("emails").select("gmail_thread_id").eq("user_id", userId).gte("sent_at", new Date(Date.now() - 5 * 864e5).toISOString())) || []) as Any[]).map((r) => r.gmail_thread_id));
  let found = 0;
  for (let i = 0; i < recent.length; i += 25) {
    const q = "in:inbox newer_than:3d from:(" + recent.slice(i, i + 25).join(" OR ") + ")";
    const r = await g(token, GMAIL + "messages?maxResults=50&q=" + encodeURIComponent(q));
    const fresh = ((r && r.messages) || []).filter((m: Any) => !known.has(m.threadId) && !stored.has(m.threadId));
    for (const m of fresh) stored.add(m.threadId);
    if (fresh.length) found += await importLeadMail(userId, token, fresh.map((m: Any) => ({ id: m.id, threadId: m.threadId })));
  }
  return found;
}

// Quick check (every minute): ask Gmail only for what's new since the last check, then open just the
// threads that are already on a record, and look at the sender of new inbox mail to spot leads (2026-11dp).
// Other emails are not stored.
async function quickReplies(userId: string): Promise<number> {
  const sc = await gmailScopes(userId); if (!sc.read) return 0;
  const link = must(await db.from("google_links").select("history_id").eq("user_id", userId).maybeSingle());
  const token = await accessFor(userId);
  const resetBookmark = async () => { const prof = await g(token, GMAIL + "profile"); await db.from("google_links").update({ history_id: String(prof.historyId || "") }).eq("user_id", userId); };
  if (!link || !link.history_id) { await resetBookmark(); return 0; }
  let page = "", latest = String(link.history_id); const threadIds = new Set<string>();
  const inbound: { id: string; threadId: string }[] = [];   // (2026-11dp) new mail that may be from a lead
  try {
    for (let i = 0; i < 5; i++) {
      const r = await g(token, GMAIL + "history?historyTypes=messageAdded&maxResults=500&startHistoryId=" + encodeURIComponent(link.history_id) + (page ? "&pageToken=" + encodeURIComponent(page) : ""));
      for (const hh of r.history || []) for (const ma of hh.messagesAdded || []) if (ma.message && ma.message.threadId) {
        threadIds.add(ma.message.threadId);
        const lab: string[] = ma.message.labelIds || [];
        if (lab.includes("INBOX") && !lab.includes("SENT") && !lab.includes("DRAFT") && !lab.includes("SPAM")) inbound.push({ id: ma.message.id, threadId: ma.message.threadId });
      }
      latest = String(r.historyId || latest); page = r.nextPageToken; if (!page) break;
    }
  } catch (_) {
    // Gmail no longer has that bookmark (e.g. after a long break): start again, the 10-minute check covers the gap
    await resetBookmark(); return 0;
  }
  if (latest !== String(link.history_id)) await db.from("google_links").update({ history_id: latest }).eq("user_id", userId);   // (2026-11dz) only when Gmail's bookmark moved
  if (!threadIds.size) return 0;
  // conversations already on a record: started from the workspace, or (2026-11dp) started by a lead
  const ours = must(await db.from("emails").select("gmail_thread_id,tbl,entity_id,subject").eq("user_id", userId).in("gmail_thread_id", [...threadIds].slice(0, 300))) || [];
  const map = new Map<string, Any>(); for (const o of ours) if (!map.has(o.gmail_thread_id)) map.set(o.gmail_thread_id, o);
  let found = 0;
  for (const [tid, origin] of map) found += (await readThread(userId, token, tid, origin)).found;
  found += await importLeadMail(userId, token, inbound.filter((m) => !map.has(m.threadId)));
  return found;
}
async function syncReplies(userId: string) {
  const r = await checkReplies(userId);
  return r.found;
}
async function checkReplies(userId: string): Promise<{ found: number; checked: number; problem: string }> {
  const sc = await gmailScopes(userId);
  if (!sc.send && !sc.read) return { found: 0, checked: 0, problem: "" };
  if (!sc.read) {
    const problem = "Replies can’t be checked: Google’s “View your email messages” box wasn’t ticked. In My profile, click Reconnect Google and tick every box.";
    await db.from("google_links").update({ last_error: problem }).eq("user_id", userId);
    return { found: 0, checked: 0, problem };
  }
  const since = new Date(Date.now() - 60 * 864e5).toISOString();
  const outs = must(await db.from("emails").select("gmail_thread_id,tbl,entity_id,subject").eq("user_id", userId).gte("sent_at", since).order("sent_at", { ascending: false }).limit(300)) || [];
  const threads = new Map<string, Any>(); for (const o of outs) if (o.gmail_thread_id && !threads.has(o.gmail_thread_id)) threads.set(o.gmail_thread_id, o);
  const token = await accessFor(userId);
  let found = 0, checked = 0, problem = "";
  // (2026-11dp) emails leads sent first in the last 3 days that the 1-minute check missed
  try { found += await searchLeadMail(userId, token, threads); } catch (e) { problem = "Couldn’t look for new emails from leads: " + String((e as Error)?.message || e).slice(0, 140); }
  for (const [tid, origin] of [...threads.entries()].slice(0, 150)) {
    const r = await readThread(userId, token, tid, origin);
    if (r.checked) checked++;
    found += r.found;
    if (r.problem) { problem = r.problem; if (r.stop) break; }
  }
  await db.from("google_links").update({ last_error: problem }).eq("user_id", userId);
  return { found, checked, problem };
}


/* ---------------- notification emails (the company sending mailbox) ----------------
   An admin connects one mailbox (notifications@tcipher.com) once. Every 2 minutes (the "replies_all" job):
   - unread notifications (chat messages create them too) that are over 2 minutes old are emailed to people
     who haven't been active in the app for 2 minutes, as each person chose in My profile
     ("all", "direct" = direct/group messages and @tags only, "off"); to their work email and personal email;
   - replies to those emails are posted back as a chat message or a comment, but only when they come from
     that person's own address. The reply address carries a one-off token: notifications+<token>@tcipher.com. */
const APP_URL = "https://internal.tcipher.com/";
const MAIL_BATCH = 40, MAIL_DAILY_CAP = 1500;
const randomToken = () => { const a = new Uint8Array(24); crypto.getRandomValues(a); return b64(a).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); };
const cleanHeader = (v: string) => String(v || "").replace(/[\r\n"]+/g, " ").trim();
async function senderRow() { return must(await db.from("mail_sender").select("*").eq("id", 1).maybeSingle()); }
async function senderToken(row: Any): Promise<string> {
  try { return (await googleTokenRequest({ grant_type: "refresh_token", refresh_token: row.refresh_token })).access_token; }
  catch (e) {
    const msg = String((e as Error).message || e);
    await db.from("mail_sender").update({ last_error: /invalid_grant|expired|revoked/i.test(msg) ? "The sending mailbox's Google access expired or was removed. An admin needs to click Reconnect." : "Google sign-in failed: " + msg.slice(0, 200) }).eq("id", 1);
    throw e;
  }
}
function mimeText(from: string, to: string[], subject: string, text: string, replyTo = "") {
  const alt = "alt_" + crypto.randomUUID().replace(/-/g, "");
  return b64url([
    "From: " + from, "To: " + to.join(", "), ...(replyTo ? ["Reply-To: " + replyTo] : []),
    "Subject: " + encHeader(cleanHeader(subject).slice(0, 200)), "MIME-Version: 1.0",
    "Content-Type: multipart/alternative; boundary=\"" + alt + "\"", "",
    "--" + alt, "Content-Type: text/plain; charset=UTF-8", "Content-Transfer-Encoding: base64", "", wrap76(b64(new TextEncoder().encode(text))),
    "--" + alt, "Content-Type: text/html; charset=UTF-8", "Content-Transfer-Encoding: base64", "", wrap76(b64(new TextEncoder().encode(toHtml(text)))),
    "--" + alt + "--", ""].join("\r\n"));
}
async function connectSender(me: Any, code: string) {
  const tok = await googleTokenRequest({ grant_type: "authorization_code", code, redirect_uri: "postmessage" });
  const granted = String(tok.scope || "");
  if (!granted.includes("gmail.send")) throw new Error("Sending email wasn’t allowed. Click Connect again and tick every box on Google’s screen.");
  const info = await g(tok.access_token, "https://openidconnect.googleapis.com/v1/userinfo");
  const old = await senderRow();
  const refresh = tok.refresh_token || (old && old.google_email === info.email ? old.refresh_token : "");
  if (!refresh) throw new Error("Google didn’t give permanent access. Remove “Tcipher Workspace” at myaccount.google.com/permissions for that mailbox, then connect again.");
  let history = "";
  if (granted.includes("gmail.readonly")) { try { history = String((await g(tok.access_token, GMAIL + "profile")).historyId || ""); } catch (_) { /* replies start being read on the next run */ } }
  must(await db.from("mail_sender").upsert({ id: 1, google_email: info.email || "", refresh_token: refresh, scopes: granted, connected_by: me.id, connected_at: new Date().toISOString(), last_error: "", history_id: history, running_until: null }));
  return info.email || "";
}
async function testSender(me: Any) {
  const row = await senderRow();
  if (!row || !row.refresh_token) throw new Error("No sending mailbox is connected.");
  const token = await senderToken(row);
  const text = "This is a test from the Tcipher workspace. Notification emails will come from this address.\n\nOpen the workspace: " + APP_URL;
  await g(token, GMAIL + "messages/send", { method: "POST", body: JSON.stringify({ raw: mimeText("Tcipher Workspace <" + row.google_email + ">", [me.email], "Test email from the Tcipher workspace", text) }) });
  await db.from("mail_sender").update({ last_error: "" }).eq("id", 1);
  return me.email;
}
async function disconnectSender() {
  const row = await senderRow();
  if (row && row.refresh_token) await fetch("https://oauth2.googleapis.com/revoke?token=" + encodeURIComponent(row.refresh_token), { method: "POST" }).catch(() => {});
  must(await db.from("mail_sender").update({ refresh_token: "", google_email: "", scopes: "", history_id: "", last_error: "", running_until: null }).eq("id", 1));
}
// the reply address for one email: notifications+<token>@tcipher.com
const replyAddress = (sender: string, token: string) => { const [local, domain] = sender.split("@"); return local + "+" + token + "@" + domain; };
const isDirect = (n: Any) => n.tbl === "chat" || /tagged you|mentioned you/i.test(String(n.title || ""));
async function sendPendingEmails(row: Any, token: string) {
  const now = Date.now(), cutoff = new Date(now - 2 * 60000).toISOString(), oldest = new Date(now - 3 * 3600e3).toISOString();   // older unread items aren't emailed late
  const day = today();
  let count = row.sent_day === day ? row.sent_count || 0 : 0;
  if (count >= MAIL_DAILY_CAP) return 0;
  const list = must(await db.from("notifications").select("*").eq("is_read", false).is("emailed_at", null).eq("email_status", "")
    .lt("created_at", cutoff).gt("created_at", oldest).order("created_at", { ascending: true }).limit(MAIL_BATCH * 3)) || [];
  if (!list.length) return 0;
  const ids = [...new Set(list.map((n: Any) => n.user_id))];
  const people = new Map<string, Any>((must(await db.from("profiles").select("id,email,full_name,is_active,email_notifications,client_id,portal_active").in("id", ids)) || []).map((p: Any) => [p.id, p]));
  const personal = new Map<string, string>((must(await db.from("profile_private").select("user_id,personal_email").in("user_id", ids)) || []).map((p: Any) => [p.user_id, p.personal_email]));
  const seen = new Map<string, string>((must(await db.from("presence").select("user_id,last_seen_at").in("user_id", ids)) || []).map((p: Any) => [p.user_id, p.last_seen_at]));
  // muted conversations: no emails either (same rule as push — only @mentions still come through) (2026-11dh)
  const chatIds = [...new Set(list.filter((n: Any) => n.tbl === "chat" && n.entity_id).map((n: Any) => n.entity_id))];
  const muted = new Set<string>(chatIds.length ? (must(await db.from("chat_mutes").select("user_id,channel_id").in("user_id", ids).in("channel_id", chatIds)) || []).map((m: Any) => m.user_id + "|" + m.channel_id) : []);
  const canReply = String(row.scopes || "").includes("gmail.readonly");
  let sent = 0;
  for (const n of list) {
    if (sent >= MAIL_BATCH || count >= MAIL_DAILY_CAP) break;
    const p = people.get(n.user_id);
    const skip = async (why: string) => { await db.from("notifications").update({ email_status: why }).eq("id", n.id); };
    const portal = !!(p && p.client_id && p.portal_active);   // a client with portal access (2026-11bt)
    if (!p || (!p.is_active && !portal)) { await skip("skipped: inactive"); continue; }
    const pref = p.email_notifications || "all";
    if (pref === "off") { await skip("skipped: off"); continue; }
    if (pref === "direct" && !isDirect(n)) { await skip("skipped: not direct"); continue; }
    if (n.tbl === "chat" && muted.has(n.user_id + "|" + n.entity_id) && !/mentioned you|tagged you/i.test(String(n.title || ""))) { await skip("skipped: muted"); continue; }
    const last = seen.get(n.user_id);
    // they're in the app: they'll see it there. (2026-11ec) "last seen" is saved on opening, leaving and every 5 minutes, so
    // anything in the last 6 minutes means they're there (or only just left: the email follows on a later run if it's still unread)
    if (last && last > new Date(now - 6 * 60000).toISOString()) continue;
    const to = [...new Set([p.email, personal.get(n.user_id)].map((x) => String(x || "").trim().toLowerCase()).filter((x) => /^[^@\s<>"]+@[^@\s<>"]+\.[^@\s<>"]+$/.test(x)))];
    if (!to.length) { await skip("skipped: no address"); continue; }
    // still unread right now?
    const fresh = must(await db.from("notifications").select("is_read,emailed_at").eq("id", n.id).maybeSingle());
    if (!fresh || fresh.is_read || fresh.emailed_at) continue;
    let replyTo = "", tokenRow: Any = null;
    const replyable = !portal && canReply && n.entity_id && n.tbl && (n.tbl === "chat" || !["leave_requests", "connect-google", "team-day", "emails"].includes(n.tbl));
    if (replyable) {
      tokenRow = { token: randomToken(), user_id: n.user_id, channel_id: n.tbl === "chat" ? n.entity_id : null, tbl: n.tbl === "chat" ? null : n.tbl, entity_id: n.tbl === "chat" ? null : n.entity_id };
      const ins = await db.from("email_reply_tokens").insert(tokenRow);
      if (!ins.error) replyTo = replyAddress(row.google_email, tokenRow.token); else tokenRow = null;
    }
    const link = APP_URL + (n.tbl && n.entity_id ? "#open/" + encodeURIComponent(n.tbl) + "/" + encodeURIComponent(n.entity_id) : "");
    const text = [String(n.title || "Notification"), n.body ? "\n" + String(n.body) : "", portal ? (n.tbl ? "\n\nOpen it in your client portal: " + link : "") : "\n\nOpen it in the workspace: " + link,
      replyTo ? "\n\nReply to this email to answer" + (n.tbl === "chat" ? " in the chat." : " with a comment.") : "",
      portal ? "\n\n—\nYou get these emails from the Tcipher client portal. Change them in the portal under Profile › Email updates."
        : "\n\n—\nYou get these emails because you weren’t in the workspace. Change what you get in My profile › Notification emails."].join("");
    try {
      await g(token, GMAIL + "messages/send", { method: "POST", body: JSON.stringify({ raw: mimeText((portal ? "Tcipher" : "Tcipher Workspace") + " <" + row.google_email + ">", to, String(n.title || "New notification"), text, replyTo) }) });
      await db.from("notifications").update({ emailed_at: new Date().toISOString(), email_status: "sent" }).eq("id", n.id);
      if (n.tbl === "chat") await db.from("chat_email_log").upsert({ user_id: n.user_id, channel_id: n.entity_id, last_emailed_at: new Date().toISOString() }, { onConflict: "user_id,channel_id" });
      sent++; count++;
    } catch (e) {
      await db.from("notifications").update({ email_status: "failed: " + String((e as Error)?.message || e).slice(0, 120) }).eq("id", n.id);
      if (tokenRow) await db.from("email_reply_tokens").delete().eq("token", tokenRow.token);
      await db.from("mail_sender").update({ last_error: "Sending failed: " + String((e as Error)?.message || e).slice(0, 200) }).eq("id", 1);
    }
  }
  if (sent) await db.from("mail_sender").update({ sent_day: day, sent_count: count, last_sent_at: new Date().toISOString(), last_error: "" }).eq("id", 1);
  return sent;
}
// the reply itself, without the quoted email below it
function replyText(raw: string) {
  const lines = String(raw || "").replace(/\r/g, "").split("\n"), out: string[] = [];
  for (const l of lines) {
    if (/^\s*>/.test(l) || /^On .{4,200}wrote:\s*$/.test(l.trim()) || /^-{2,}\s*Original Message/i.test(l.trim()) || /^_{5,}/.test(l.trim()) || /^From:\s/.test(l.trim()) || /^—\s*$/.test(l.trim())) break;
    out.push(l);
  }
  return out.join("\n").trim().slice(0, 4000);
}
async function readSenderReplies(row: Any, token: string) {
  if (!String(row.scopes || "").includes("gmail.readonly")) return 0;
  if (!row.history_id) { const prof = await g(token, GMAIL + "profile"); await db.from("mail_sender").update({ history_id: String(prof.historyId || "") }).eq("id", 1); return 0; }
  const ids = new Set<string>(); let page = "", latest = String(row.history_id);
  try {
    for (let i = 0; i < 5; i++) {
      const r = await g(token, GMAIL + "history?historyTypes=messageAdded&labelId=INBOX&maxResults=500&startHistoryId=" + encodeURIComponent(row.history_id) + (page ? "&pageToken=" + encodeURIComponent(page) : ""));
      for (const hh of r.history || []) for (const ma of hh.messagesAdded || []) if (ma.message && ma.message.id) ids.add(ma.message.id);
      latest = String(r.historyId || latest); page = r.nextPageToken; if (!page) break;
    }
  } catch (_) { const prof = await g(token, GMAIL + "profile"); await db.from("mail_sender").update({ history_id: String(prof.historyId || "") }).eq("id", 1); return 0; }
  await db.from("mail_sender").update({ history_id: latest }).eq("id", 1);
  if (!ids.size) return 0;
  const done = new Set(((must(await db.from("email_reply_log").select("gmail_message_id").in("gmail_message_id", [...ids])) || []) as Any[]).map((x) => x.gmail_message_id));
  let posted = 0;
  for (const id of ids) {
    if (done.has(id)) continue;
    const m = await g(token, GMAIL + "messages/" + id + "?format=full");
    const hd = (n: string) => ((m.payload && m.payload.headers) || []).filter((x: Any) => x.name.toLowerCase() === n).map((x: Any) => x.value).join(", ");
    const from = (hd("from").match(/<([^>]+)>/) || [null, hd("from")])[1].trim().toLowerCase();
    const text = plainBody(m.payload);
    const tok = ((hd("to") + " " + hd("cc") + " " + hd("delivered-to")).match(/\+([A-Za-z0-9_-]{20,})@/) || [])[1] || "";
    const log = async (status: string, uid: string | null = null) => { await db.from("email_reply_log").insert({ gmail_message_id: id, token: tok, user_id: uid, from_email: from.slice(0, 200), status }); };
    if (!tok) { await log("no token"); continue; }
    const t = must(await db.from("email_reply_tokens").select("user_id").eq("token", tok).maybeSingle());
    if (!t) { await log("unknown token"); continue; }
    // only the person the email went to can answer through it (anyone could write to the reply address)
    const p = must(await db.from("profiles").select("email").eq("id", t.user_id).maybeSingle());
    const pp = must(await db.from("profile_private").select("personal_email").eq("user_id", t.user_id).maybeSingle());
    const allowed = [p && p.email, pp && pp.personal_email].map((x) => String(x || "").trim().toLowerCase()).filter(Boolean);
    if (!allowed.includes(from)) { await log("sender not allowed", t.user_id); continue; }
    const body = replyText(text);
    if (!body) { await log("empty", t.user_id); continue; }
    const r = await db.rpc("post_email_reply", { p_token: tok, p_body: body });
    const res = r.data || {};
    await log(r.error ? "error: " + r.error.message.slice(0, 100) : res.ok ? "posted" : "refused: " + (res.error || "?"), t.user_id);
    if (res.ok) posted++;
  }
  return posted;
}
// one run every 2 minutes; a lock stops two runs overlapping
async function mailRun() {
  const until = new Date(Date.now() + 100000).toISOString(), nowIso = new Date().toISOString();
  const lock = must(await db.from("mail_sender").update({ running_until: until }).eq("id", 1).neq("refresh_token", "")
    .or('running_until.is.null,running_until.lt."' + nowIso + '"').select("*"));
  const row = lock && lock[0]; if (!row) return { emailed: 0, posted: 0 };
  try {
    const token = await senderToken(row);
    let posted = 0;
    try { posted = await readSenderReplies(row, token); } catch (e) { await db.from("mail_sender").update({ last_error: "Reading replies failed: " + String((e as Error)?.message || e).slice(0, 200) }).eq("id", 1); }
    const emailed = await sendPendingEmails(row, token);
    return { emailed, posted };
  } finally { await db.from("mail_sender").update({ running_until: null }).eq("id", 1); }
}

/* ---------------- handler ---------------- */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  // (2026-11ed) Google Calendar push: answered straight away, the changes are fetched just after
  if (req.headers.get("x-goog-channel-id")) {
    const work = calPush(req).catch(() => {});
    const rt = (globalThis as Any).EdgeRuntime;
    if (rt && typeof rt.waitUntil === "function") rt.waitUntil(work); else await work;
    return new Response(null, { status: 200 });
  }
  try {
    if (!GID || !GSECRET) return json({ error: "Google isn’t set up on the server yet (missing GOOGLE_CLIENT_ID or GOOGLE_CLIENT_SECRET secret)." }, 500);
    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "");

    // Scheduled job: sync everyone + import today's and yesterday's Meet joins
    if (action === "replies_all") {
      if (!CRON || req.headers.get("x-cron-secret") !== CRON) return json({ error: "Not allowed." }, 403);
      const links = must(await db.from("google_links").select("user_id,scopes")) || [];
      let replies = 0, failed = 0;
      for (const l of links.filter((x: Any) => String(x.scopes || "").includes("gmail.readonly"))) { try { replies += await quickReplies(l.user_id); } catch (_) { failed++; } }
      let mail: Any = { emailed: 0, posted: 0 };
      try { mail = await mailRun(); } catch (e) { mail = { error: String((e as Error)?.message || e).slice(0, 200) }; }
      return json({ ok: true, replies, failed, ...mail });
    }
    // (2026-11dr) the demo-booking function asks for the Google invite of a demo a lead just booked
    if (action === "invite_booking") {
      if (!CRON || req.headers.get("x-cron-secret") !== CRON) return json({ error: "Not allowed." }, 403);
      const m = must(await db.from("meetings").select("id,created_by,kind,google_event_id").eq("id", String(body.meeting_id || "")).single());
      if (m.kind !== "Sales demo" || m.google_event_id) return json({ error: "Nothing to send." }, 400);
      return json({ ok: true, meeting: await saveEvent(m.created_by, m.id) });
    }
    if (action === "sync_all") {
      if (!CRON || req.headers.get("x-cron-secret") !== CRON) return json({ error: "Not allowed." }, 403);
      const links = must(await db.from("google_links").select("user_id"));
      const result: Any = { synced: 0, failed: 0, joins: 0, checkedIn: 0 };
      for (const l of links) { try { await syncUser(l.user_id, "auto"); result.synced++; } catch (_) { result.failed++; } }
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
      // (2026-11do) Gemini notes and recordings of demos and other one-off calls from the last two days
      result.notes = 0;
      const fifteenAgo = new Date(Date.now() - 15 * 60000).toISOString();
      for (const m of meetings) {
        if (m.repeat && m.repeat !== "Does not repeat") continue;
        if (m.meeting_date < addDays(today(), -2) || m.meeting_date > today()) continue;
        if (!connected.has(m.google_owner || m.created_by) || !("notes_checked_at" in m)) continue;
        if (m.notes_doc_url && m.recording_url) continue;
        if (!m.start_time || new Date(localDateTime(m.meeting_date, m.start_time, m.duration_min || 30) + "+05:30") > new Date()) continue;   // not over yet
        if (m.notes_checked_at && m.notes_checked_at > fifteenAgo) continue;
        try { const r = await fetchNotes(m.id); if (r.found.notes || r.found.recording) result.notes++; } catch (_) { /* keep going */ }
        if (result.notes >= 20) break;
      }
      return json(result);
    }

    // (2026-11dq) the public booking page: no sign-in
    if (action === "public_slots") return json(await publicSlots(body));
    if (action === "public_book") {
      const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
      try { return json(await publicBook(body, ip)); }
      catch (e) { return json({ error: String((e as Error)?.message || e) }, (e as Any).status || 400); }
    }

    // Everything else: a signed-in, active workspace user
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: who } = await db.auth.getUser(jwt);
    if (!who || !who.user) return json({ error: "Sign in again." }, 401);
    const me = must(await db.from("profiles").select("id,email,is_admin,is_active").eq("id", who.user.id).single());
    if (!me.is_active) return json({ error: "Your account is turned off." }, 403);
    // an admin who has two-step sign-in counts as an admin only in a session where the code was entered
    if (me.is_admin) {
      let aal = "aal1";
      try { const p = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"); aal = String(JSON.parse(atob(p + "===".slice((p.length + 3) % 4))).aal || "aal1"); } catch (_) { /* aal1 */ }
      const { data: fac } = await db.auth.admin.mfa.listFactors({ userId: me.id });
      if (aal !== "aal2" && (fac?.factors ?? []).some((f: Any) => f.status === "verified")) me.is_admin = false;
    }

    if (action === "connect") {
      const tok = await googleTokenRequest({ grant_type: "authorization_code", code: String(body.code || ""), redirect_uri: "postmessage" });
      const info = await g(tok.access_token, "https://openidconnect.googleapis.com/v1/userinfo");
      const existing = must(await db.from("google_tokens").select("refresh_token").eq("user_id", me.id).maybeSingle());
      const refresh = tok.refresh_token || (existing && existing.refresh_token);
      const granted = String(tok.scope || "");
      if (!granted.includes("calendar.events")) return json({ error: "Calendar access wasn’t allowed. Click Connect Google again and tick the box for Google Calendar on Google’s permissions screen." }, 400);
      if (!refresh) return json({ error: "Google didn’t give permanent access. Remove “Tcipher Workspace” at myaccount.google.com/permissions, then click Connect Google again." }, 400);
      must(await db.from("google_tokens").upsert({ user_id: me.id, refresh_token: refresh, scopes: tok.scope || "", updated_at: new Date().toISOString() }));
      must(await db.from("google_links").upsert({ user_id: me.id, google_email: info.email || "", connected_at: new Date().toISOString(), last_error: "", scopes: granted }));
      let n = 0, warning = "";
      try { n = await syncUser(me.id); } catch (e) { warning = String((e as Error)?.message || e); }
      return json({ ok: true, email: info.email || "", events: n, warning, scopes: tok.scope || "" });
    }
    if (action === "disconnect") {
      const row = must(await db.from("google_tokens").select("refresh_token").eq("user_id", me.id).maybeSingle());
      const ch = await calChannel(me.id);   // stop Google's change notices before the access goes
      if (row && ch && ch.cal_channel_id) { try { await calUnwatch(await accessFor(me.id), ch.cal_channel_id, ch.cal_channel_resource); } catch (_) { /* runs out by itself */ } }
      if (row) await fetch("https://oauth2.googleapis.com/revoke?token=" + encodeURIComponent(row.refresh_token), { method: "POST" }).catch(() => {});
      await db.from("calendar_events").delete().eq("user_id", me.id);
      await db.from("google_tokens").delete().eq("user_id", me.id);
      await db.from("google_links").delete().eq("user_id", me.id);
      return json({ ok: true });
    }
    if (action === "sync") return json({ ok: true, events: await syncUser(me.id) });
    if (action === "send_email") {
      const full = must(await db.from("profiles").select("id,email,full_name,is_admin").eq("id", me.id).single());
      return json({ ok: true, email: await sendEmail(full, body, jwt) });
    }
    if (action === "check_replies") { let q = 0; try { q = await quickReplies(me.id); } catch (_) { /* the full check below still runs */ } const r = await checkReplies(me.id); return json({ ok: true, replies: q + r.found, checked: r.checked, problem: r.problem }); }

    if (["connect_sender", "test_sender", "disconnect_sender"].includes(action)) {
      if (!me.is_admin) return json({ error: "Only an admin can manage the sending mailbox." }, 403);
      if (action === "connect_sender") return json({ ok: true, email: await connectSender(me, String(body.code || "")) });
      if (action === "test_sender") return json({ ok: true, to: await testSender(me) });
      await disconnectSender(); return json({ ok: true });
    }

    const meetingId = String(body.meeting_id || "");
    if (!meetingId) return json({ error: "Missing meeting." }, 400);
    const m = must(await db.from("meetings").select("created_by,google_owner").eq("id", meetingId).single());
    // another person's Google account is only used by that person or an admin (the creator alone isn't enough:
    // anyone could create a meeting row naming a colleague as the Google organiser)
    const allowed = me.is_admin || m.google_owner === me.id || (!m.google_owner && m.created_by === me.id);
    if (!allowed) return json({ error: "Only the organiser or an admin can do this." }, 403);

    if (action === "save_event") return json({ ok: true, meeting: await saveEvent(me.id, meetingId) });
    if (action === "delete_event") { await deleteEvent(meetingId); return json({ ok: true }); }
    if (action === "import_joins") return json({ ok: true, ...(await importJoins(meetingId, 30)) });
    if (action === "fetch_notes") return json({ ok: true, ...(await fetchNotes(meetingId)) });
    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500);
  }
});
