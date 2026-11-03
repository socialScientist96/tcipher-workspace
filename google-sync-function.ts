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
  try { await syncReplies(userId); } catch (e) { await db.from("google_links").update({ last_error: "Reply check failed: " + String((e as Error)?.message || e).slice(0, 200) }).eq("user_id", userId); }
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
async function sendEmail(me: Any, body: Any) {
  if (!(await hasGmail(me.id))) throw new Error("Email isn’t allowed yet. In My profile, click Reconnect Google and tick the Gmail boxes.");
  const to = String(body.to || "").split(/[,;]/).map((x: string) => x.trim()).filter(Boolean);
  const cc = String(body.cc || "").split(/[,;]/).map((x: string) => x.trim()).filter(Boolean);
  if (!to.length || to.some((x: string) => !/^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$/.test(x))) throw new Error("Check the email address.");
  const subject = String(body.subject || "").slice(0, 250), text = String(body.body || "").slice(0, 100000);
  if (!subject.trim()) throw new Error("Add a subject.");
  const tbl = String(body.tbl || ""), entity = body.entity_id || null;
  // attachments: files already uploaded to the record (max 20 MB together)
  const files: Any[] = [];
  let total = 0;
  for (const fid of (Array.isArray(body.file_ids) ? body.file_ids.slice(0, 10) : [])) {
    const f = must(await db.from("files").select("*").eq("id", fid).maybeSingle()); if (!f) continue;
    const dl = await db.storage.from("files").download(f.path); if (dl.error || !dl.data) throw new Error("Couldn’t attach " + f.name);
    const bytes = new Uint8Array(await dl.data.arrayBuffer()); total += bytes.length;
    if (total > 20 * 1024 * 1024) throw new Error("Attachments are over 20 MB. Remove some, or share a link instead.");
    files.push({ name: f.name, mime: f.mime || "application/octet-stream", data: bytes });
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
  for (const m of th.messages || []) {
    if (known.has(m.id) || (m.labelIds || []).includes("DRAFT")) continue;
    const hd = (n: string) => ((m.payload && m.payload.headers) || []).find((x: Any) => x.name.toLowerCase() === n)?.value || "";
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
      await db.from("notifications").insert({ user_id: userId, title: "Email reply from " + (row.from_email.replace(/<.*>/, "").trim() || row.from_email), body: (row.subject + " · " + String(m.snippet || "")).slice(0, 200), tbl: "emails", entity_id: ins.data.id });
    }
  }
  return { found, checked: true, problem: "", stop: false };
}
// Quick check (every minute): ask Gmail only for what's new since the last check, then open just the
// threads that were started from the workspace. Nothing else in the mailbox is read.
async function quickReplies(userId: string): Promise<number> {
  const sc = await gmailScopes(userId); if (!sc.read) return 0;
  const link = must(await db.from("google_links").select("history_id").eq("user_id", userId).maybeSingle());
  const token = await accessFor(userId);
  const resetBookmark = async () => { const prof = await g(token, GMAIL + "profile"); await db.from("google_links").update({ history_id: String(prof.historyId || "") }).eq("user_id", userId); };
  if (!link || !link.history_id) { await resetBookmark(); return 0; }
  let page = "", latest = String(link.history_id); const threadIds = new Set<string>();
  try {
    for (let i = 0; i < 5; i++) {
      const r = await g(token, GMAIL + "history?historyTypes=messageAdded&maxResults=500&startHistoryId=" + encodeURIComponent(link.history_id) + (page ? "&pageToken=" + encodeURIComponent(page) : ""));
      for (const hh of r.history || []) for (const ma of hh.messagesAdded || []) if (ma.message && ma.message.threadId) threadIds.add(ma.message.threadId);
      latest = String(r.historyId || latest); page = r.nextPageToken; if (!page) break;
    }
  } catch (_) {
    // Gmail no longer has that bookmark (e.g. after a long break): start again, the 10-minute check covers the gap
    await resetBookmark(); return 0;
  }
  await db.from("google_links").update({ history_id: latest }).eq("user_id", userId);
  if (!threadIds.size) return 0;
  const ours = must(await db.from("emails").select("gmail_thread_id,tbl,entity_id,subject").eq("user_id", userId).eq("direction", "out").in("gmail_thread_id", [...threadIds].slice(0, 300))) || [];
  const map = new Map<string, Any>(); for (const o of ours) if (!map.has(o.gmail_thread_id)) map.set(o.gmail_thread_id, o);
  let found = 0;
  for (const [tid, origin] of map) found += (await readThread(userId, token, tid, origin)).found;
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
  const outs = must(await db.from("emails").select("gmail_thread_id,tbl,entity_id,subject").eq("user_id", userId).eq("direction", "out").gte("sent_at", since).order("sent_at", { ascending: false }).limit(300)) || [];
  const threads = new Map<string, Any>(); for (const o of outs) if (o.gmail_thread_id && !threads.has(o.gmail_thread_id)) threads.set(o.gmail_thread_id, o);
  if (!threads.size) return { found: 0, checked: 0, problem: "" };
  const token = await accessFor(userId);
  let found = 0, checked = 0, problem = "";
  for (const [tid, origin] of [...threads.entries()].slice(0, 150)) {
    const r = await readThread(userId, token, tid, origin);
    if (r.checked) checked++;
    found += r.found;
    if (r.problem) { problem = r.problem; if (r.stop) break; }
  }
  await db.from("google_links").update({ last_error: problem }).eq("user_id", userId);
  return { found, checked, problem };
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
    if (action === "replies_all") {
      if (!CRON || req.headers.get("x-cron-secret") !== CRON) return json({ error: "Not allowed." }, 403);
      const links = must(await db.from("google_links").select("user_id,scopes")) || [];
      let replies = 0, failed = 0;
      for (const l of links.filter((x: Any) => String(x.scopes || "").includes("gmail.readonly"))) { try { replies += await quickReplies(l.user_id); } catch (_) { failed++; } }
      return json({ ok: true, replies, failed });
    }
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
      must(await db.from("google_links").upsert({ user_id: me.id, google_email: info.email || "", connected_at: new Date().toISOString(), last_error: "", scopes: granted }));
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
    if (action === "send_email") {
      const full = must(await db.from("profiles").select("id,email,full_name,is_admin").eq("id", me.id).single());
      return json({ ok: true, email: await sendEmail(full, body) });
    }
    if (action === "check_replies") { let q = 0; try { q = await quickReplies(me.id); } catch (_) { /* the full check below still runs */ } const r = await checkReplies(me.id); return json({ ok: true, replies: q + r.found, checked: r.checked, problem: r.problem }); }

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
