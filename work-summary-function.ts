// Supabase Edge Function: work-summary
// For admins: everything one person worked on in a day, a week or a month, as a timeline of every detail,
// plus a short "at a glance" summary written by Claude from that timeline.
//
// Deploy: Supabase > Edge Functions > Deploy a new function > Via Editor, name it exactly: work-summary
// Needs the secret ANTHROPIC_API_KEY (Edge Functions > Secrets). Without it the timeline still works and
// the summary says the key is missing.
// Needs the table from upgrade-2026-11ba.sql (summaries are saved there, so opening one again is instant).
//
// What it reads, for the person and the period (India time): their actions log, task changes, comments,
// time logged, attendance and status (away, lunch, out of office), leave, meetings joined, test runs,
// changes to sales and marketing records, emails they sent from the workspace, and messages they wrote in
// channels and groups. Private direct messages are never read.
import { createClient } from "npm:@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
function secretKey(): string {
  try { const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); if (keys && keys.default) return keys.default; } catch (_) { /* legacy key */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}
function aalOf(jwt: string): string {
  try { const p = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"); return String(JSON.parse(atob(p + "===".slice((p.length + 3) % 4))).aal || "aal1"); }
  catch (_) { return "aal1"; }
}

// ---- dates, in India time ----
const DAY = 86400000;
const ymd = (d: Date) => d.toISOString().slice(0, 10);
function todayIST(): string { return ymd(new Date(Date.now() + 5.5 * 3600000)); }
function addDays(s: string, n: number): string { return ymd(new Date(Date.parse(s + "T00:00:00Z") + n * DAY)); }
function rangeOf(period: string, anchor: string): { start: string; end: string } {
  if (period === "week") {
    const dow = (new Date(anchor + "T00:00:00Z").getUTCDay() + 6) % 7;      // Monday = 0
    const start = addDays(anchor, -dow);
    return { start, end: addDays(start, 6) };
  }
  if (period === "month") {
    const start = anchor.slice(0, 8) + "01";
    const next = new Date(Date.parse(start + "T00:00:00Z")); next.setUTCMonth(next.getUTCMonth() + 1);
    return { start, end: addDays(ymd(next), -1) };
  }
  return { start: anchor, end: anchor };
}
const ist = (ts: string | null) => ts ? new Date(Date.parse(ts) + 5.5 * 3600000).toISOString().replace("T", " ").slice(0, 16) : "";
const clip = (s: unknown, n = 600) => { const t = String(s ?? "").replace(/\s+/g, " ").trim(); return t.length > n ? t.slice(0, n) + "…" : t; };

type Line = { at: string; area: string; text: string; device?: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    const db = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), { auth: { persistSession: false, autoRefreshToken: false } });

    // only an active admin (who entered their two-step code, if they use it)
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Sign in again." }, 401);
    const { data: who, error: whoErr } = await db.auth.getUser(token);
    if (whoErr || !who?.user) return json({ error: "Your session has expired. Sign in again." }, 401);
    const { data: me } = await db.from("profiles").select("is_admin,is_active").eq("id", who.user.id).single();
    if (!me?.is_admin || !me?.is_active) return json({ error: "Only admins can see work summaries." }, 403);
    const { data: mine } = await db.auth.admin.mfa.listFactors({ userId: who.user.id });
    if ((mine?.factors ?? []).some((f: { status: string }) => f.status === "verified") && aalOf(token) !== "aal2")
      return json({ error: "Enter your two-step sign-in code first: sign out, then sign in again." }, 403);

    const body = await req.json().catch(() => ({}));
    const uid = String(body.user_id ?? "");
    const period = ["day", "week", "month"].includes(body.period) ? body.period : "day";
    const anchor = /^\d{4}-\d{2}-\d{2}$/.test(String(body.date ?? "")) ? String(body.date) : todayIST();
    const refresh = !!body.refresh;
    if (!uid) return json({ error: "Choose a person." }, 400);
    const { data: person } = await db.from("profiles").select("id,full_name,title,vertical").eq("id", uid).single();
    if (!person) return json({ error: "That person wasn't found." }, 404);

    const { start, end } = rangeOf(period, anchor);
    const from = start + "T00:00:00+05:30", to = addDays(end, 1) + "T00:00:00+05:30";
    const lines: Line[] = [];
    // device: phone or tablet marks it as done away from a laptop (the company expects laptops); laptop and unknown aren't marked
    const mob = (d: unknown) => d === "phone" || d === "tablet" ? String(d) : "";
    const add = (at: string | null, area: string, text: string, device?: unknown) => { if (at && text) { const m = mob(device); lines.push(m ? { at: ist(at), area, text, device: m } : { at: ist(at), area, text }); } };
    const stats = { onPhone: 0, hours: 0, tasksDone: 0, tasksTouched: 0, comments: 0, messages: 0, emails: 0, meetings: 0, daysPresent: 0, recordsChanged: 0, tests: 0 };

    // names for records mentioned in the timeline
    const NAME: Record<string, string> = { tasks: "title", leads: "name", deals: "title", clients: "name", contacts: "name", proposals: "title", content: "title", campaigns: "name", activities: "subject", meetings: "title", notes: "title", documents: "title", announcements: "title", leave_requests: "type" };
    const LABEL: Record<string, string> = { tasks: "Task", leads: "Lead", deals: "Deal", clients: "Client", contacts: "Contact", proposals: "Proposal", content: "Content", campaigns: "Campaign", activities: "Activity", meetings: "Meeting", notes: "Note", documents: "Document", announcements: "Announcement", leave_requests: "Leave" };
    const nameCache = new Map<string, string>();
    async function names(tbl: string, ids: string[]) {
      const col = NAME[tbl]; const want = [...new Set(ids.filter(Boolean))].filter(id => !nameCache.has(tbl + id));
      if (!col || !want.length) return;
      for (let i = 0; i < want.length; i += 200) {
        const { data } = await db.from(tbl).select(tbl === "tasks" ? "id,title,number" : "id," + col).in("id", want.slice(i, i + 200));
        for (const r of (data ?? []) as unknown as Record<string, unknown>[]) nameCache.set(tbl + r.id, tbl === "tasks" ? ("TC-" + r.number + " " + r.title) : String(r[col] ?? ""));
      }
    }
    const nm = (tbl: string, id: string) => nameCache.get(tbl + id) || (LABEL[tbl] ? "a " + LABEL[tbl].toLowerCase() : tbl);

    const q = async (p: PromiseLike<{ data: unknown; error: unknown }>) => { const r = await p; return ((r as { data: unknown }).data ?? []) as Record<string, any>[]; };
    // which device each thing was done on (upgrade-2026-11ce; check-ins: upgrade-2026-11cc). Before those are run, leave it out.
    const hasDev = !(await db.from("comments").select("device").limit(1)).error;
    const D = hasDev ? ",device" : "";
    const [acts, tev, rev, cmts, logs, att, sts, leave, joins, runs, msgs, mails] = await Promise.all([
      q(db.from("activity_log").select("tbl,action,entity_id,summary,at" + D).eq("actor_id", uid).gte("at", from).lt("at", to).order("at").limit(3000)),
      q(db.from("task_events").select("task_id,field,old_value,new_value,at" + D).eq("actor_id", uid).gte("at", from).lt("at", to).order("at").limit(3000)),
      q(db.from("record_events").select("tbl,entity_id,field,old_value,new_value,at" + D).eq("actor_id", uid).gte("at", from).lt("at", to).order("at").limit(3000)),
      q(db.from("comments").select("tbl,entity_id,body,created_at,kind" + D).eq("author_id", uid).gte("created_at", from).lt("created_at", to).order("created_at").limit(2000)),
      q(db.from("work_logs").select("task_id,minutes,note,work_date,created_at" + D).eq("user_id", uid).gte("work_date", start).lte("work_date", end).order("work_date").limit(2000)),
      q(db.from("attendance").select("*").eq("user_id", uid).gte("day", start).lte("day", end).order("day")),
      q(db.from("status_events").select("kind,at,until,note" + D).eq("user_id", uid).gte("at", from).lt("at", to).order("at").limit(1000)),
      q(db.from("leave_requests").select("type,start_date,end_date,half_day,status,reason,created_at" + D).eq("user_id", uid).lte("start_date", end).gte("end_date", start)),
      q(db.from("meeting_joins").select("title,joined_at,left_at,source" + D).eq("user_id", uid).gte("joined_on", start).lte("joined_on", end).order("joined_at")),
      q(db.from("test_runs").select("test_case_id,status,actual,at" + D).eq("tester_id", uid).gte("at", from).lt("at", to).order("at").limit(2000)),
      q(db.from("chat_messages").select("channel_id,body,created_at,attachments" + D).eq("author_id", uid).is("unsent_at", null).gte("created_at", from).lt("created_at", to).order("created_at").limit(3000)),
      q(db.from("emails").select("to_email,subject,snippet,tbl,entity_id,sent_at").eq("user_id", uid).eq("direction", "out").gte("sent_at", from).lt("sent_at", to).order("sent_at").limit(1000)),
    ]);

    // people appear in task and record changes as ids (reviewer, owner, tester…): show their names instead
    const { data: everyone } = await db.from("profiles").select("id,full_name");
    const pn = new Map(((everyone ?? []) as { id: string; full_name: string }[]).map(p => [p.id, p.full_name]));
    const names2 = (v: unknown) => String(v ?? "").replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, id => pn.get(id.toLowerCase()) || "someone");
    for (const r of tev) { r.old_value = names2(r.old_value); r.new_value = names2(r.new_value); }
    for (const r of rev) { r.old_value = names2(r.old_value); r.new_value = names2(r.new_value); }
    // look up the names of everything mentioned
    const byTbl: Record<string, string[]> = {};
    const want = (tbl: string, id: string) => { if (tbl && id) (byTbl[tbl] ||= []).push(id); };
    acts.forEach(r => want(r.tbl, r.entity_id)); rev.forEach(r => want(r.tbl, r.entity_id)); cmts.forEach(r => want(r.tbl, r.entity_id));
    tev.forEach(r => want("tasks", r.task_id)); logs.forEach(r => want("tasks", r.task_id)); mails.forEach(r => want(r.tbl, r.entity_id));
    await Promise.all(Object.entries(byTbl).map(([t, ids]) => names(t, ids)));

    // the timeline
    for (const r of acts) add(r.at, "Activity", (r.summary || (r.action + " " + (LABEL[r.tbl] || r.tbl))) + (r.entity_id && !String(r.summary || "").includes(nm(r.tbl, r.entity_id)) ? " · " + nm(r.tbl, r.entity_id) : ""), r.device);
    const touched = new Set<string>();
    for (const r of tev) {
      touched.add(r.task_id);
      if (r.field === "status" && /^done$/i.test(r.new_value)) stats.tasksDone++;
      add(r.at, "Tasks", nm("tasks", r.task_id) + ": " + r.field + (r.old_value ? " " + clip(r.old_value, 120) + " →" : " →") + " " + clip(r.new_value, 200), r.device);
    }
    stats.tasksTouched = touched.size;
    for (const r of rev) { stats.recordsChanged++; add(r.at, ["leads", "deals", "clients", "contacts", "proposals", "activities", "targets"].includes(r.tbl) ? "Sales" : ["campaigns", "content", "seo_keywords", "social_stats"].includes(r.tbl) ? "Marketing" : "Records", (LABEL[r.tbl] || r.tbl) + " " + nm(r.tbl, r.entity_id) + ": " + r.field + " " + clip(r.old_value, 100) + " → " + clip(r.new_value, 200), r.device); }
    for (const r of cmts) { stats.comments++; add(r.created_at, "Comments", "On " + (LABEL[r.tbl] || r.tbl).toLowerCase() + " " + nm(r.tbl, r.entity_id) + ": “" + clip(r.body) + "”", r.device); }
    for (const r of logs) { stats.hours += (r.minutes || 0) / 60; add(r.created_at || (r.work_date + "T12:00:00+05:30"), "Time", "Logged " + (Math.round((r.minutes || 0) / 6) / 10) + " h on " + nm("tasks", r.task_id) + (r.note ? " — " + clip(r.note, 200) : ""), r.device); }
    for (const r of att) {
      if (r.check_in) stats.daysPresent++;
      const hrs = r.check_in && r.check_out ? " (" + (Math.round((Date.parse(r.check_out) - Date.parse(r.check_in)) / 360000) / 10) + " h)" : "";
      add(r.check_in || (r.day + "T09:00:00+05:30"), "Attendance", r.day + ": " + (r.status || "Present") + (r.check_in ? ", in " + ist(r.check_in).slice(11) : "") + (r.check_out ? ", out " + ist(r.check_out).slice(11) + (ist(r.check_out).slice(0, 10) > r.day ? " (next day)" : "") + (r.check_out_late ? " (forgot to check out; entered later)" : "") : ", no check-out") + hrs + " · " + r.mode + (r.note ? " · " + clip(r.note, 120) : "") + (mob(r.check_in_device) ? " · checked in on " + r.check_in_device : "") + (mob(r.check_out_device) ? " · checked out on " + r.check_out_device : ""), mob(r.check_in_device) || mob(r.check_out_device));
    }
    for (const r of sts) add(r.at, "Attendance", "Status: " + r.kind + (r.until ? " until " + ist(r.until).slice(11) : "") + (r.note ? " · " + clip(r.note, 120) : ""), r.device);
    for (const r of leave) add(r.created_at, "Leave", r.type + " " + r.start_date + (r.end_date !== r.start_date ? " to " + r.end_date : "") + (r.half_day ? " (half day)" : "") + " · " + r.status + (r.reason ? " · " + clip(r.reason, 160) : ""), r.device);
    for (const r of joins) { stats.meetings++; add(r.joined_at, "Meetings", "Joined " + (r.title || "a meeting") + (r.left_at ? " until " + ist(r.left_at).slice(11) : ""), r.device); }
    for (const r of runs) { stats.tests++; add(r.at, "QA", "Test run: " + r.status + (r.actual ? " — " + clip(r.actual, 200) : ""), r.device); }
    // messages in channels and groups only; direct messages stay private
    const chIds = [...new Set(msgs.map(m => m.channel_id))];
    const chans = chIds.length ? await q(db.from("chat_channels").select("id,kind,name").in("id", chIds)) : [];
    const chan = new Map(chans.map(c => [c.id, c]));
    for (const m of msgs) {
      const c = chan.get(m.channel_id); if (!c) continue;
      // direct messages stay private: only that one was sent from a phone, never what it said
      if (c.kind === "dm") { if (mob(m.device)) add(m.created_at, "Chat", "Direct message (private)", m.device); continue; }
      stats.messages++;
      const files = Array.isArray(m.attachments) && m.attachments.length ? " [" + m.attachments.length + " file" + (m.attachments.length > 1 ? "s" : "") + "]" : "";
      add(m.created_at, "Chat", (c.kind === "group" ? "Group " : "#") + (c.name || "chat") + ": “" + clip(m.body, 400) + "”" + files, m.device);
    }
    for (const e of mails) { stats.emails++; add(e.sent_at, "Email", "To " + clip(e.to_email, 80) + ": " + clip(e.subject, 160) + (e.entity_id ? " (re " + nm(e.tbl, e.entity_id) + ")" : "") + (e.snippet ? " — " + clip(e.snippet, 200) : "")); }
    lines.sort((a, b) => a.at.localeCompare(b.at));
    stats.onPhone = lines.filter(l => l.device).length;
    // websites from Tcipher Tracker (upgrade-2026-11cg): the top sites by time
    let sitesLine = "";
    const web = await db.from("web_minutes").select("domain,seconds").eq("user_id", uid).gte("day", start).lte("day", end).limit(100000);
    if (!web.error && web.data?.length) {
      const by = new Map<string, number>(); let paused = 0;
      for (const w of web.data as { domain: string; seconds: number }[]) { if (w.domain === "(paused)") paused += w.seconds; else by.set(w.domain, (by.get(w.domain) || 0) + w.seconds); }
      const top = [...by.entries()].sort((x, y) => y[1] - x[1]).slice(0, 15);
      const hmS = (sec: number) => { const m = Math.round(sec / 60); return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m"; };
      Object.assign(stats, { browserMinutes: Math.round([...by.values()].reduce((x, y) => x + y, 0) / 60), trackerPausedMinutes: Math.round(paused / 60) });
      sitesLine = "Website time from the browser tracker (website names only): " + top.map(([d, sec]) => d + " " + hmS(sec)).join(", ") + (paused ? "; paused " + hmS(paused) : "") + ".";
    }
    // time with the workspace on screen, each minute once across all browsers and devices (upgrade-2026-11cf)
    const mins = await db.from("activity_minutes").select("devices,active,sessions").eq("user_id", uid).gte("day", start).lte("day", end).limit(50000);
    if (!mins.error && mins.data?.length) {
      const m = mins.data as { devices: number; active: number; sessions: string[] }[];
      Object.assign(stats, { workspaceMinutes: m.length, activeMinutes: m.filter(x => x.active).length,
        phoneMinutes: m.filter(x => x.devices & 6).length, parallelMinutes: m.filter(x => (x.sessions || []).length > 1).length });
    }
    stats.hours = Math.round(stats.hours * 10) / 10;

    // the summary: saved, so reopening is instant; today / this week / this month are refreshed after 30 minutes
    const periodDone = end < todayIST();
    let summary = "", cached = false, generatedAt = "", note = "";
    const { data: saved } = await db.from("work_summaries").select("summary,generated_at,activity_count").eq("user_id", uid).eq("period", period).eq("start_day", start).maybeSingle();
    if (saved && !refresh && saved.activity_count === lines.length && (!stats.onPhone || /Done on phone/i.test(saved.summary || "")) && (periodDone || Date.now() - Date.parse(saved.generated_at) < 30 * 60000)) {
      summary = saved.summary; generatedAt = saved.generated_at; cached = true;
    } else if (!lines.length) {
      summary = ""; note = "Nothing was recorded for " + person.full_name + " in this period.";
    } else if (!Deno.env.get("ANTHROPIC_API_KEY")) {
      note = "The summary needs the ANTHROPIC_API_KEY secret (Supabase › Edge Functions › Secrets). The full timeline is below.";
    } else {
      const label = period === "day" ? start : start + " to " + end;
      const log = lines.map(l => l.at + " · " + l.area + " · " + l.text + (l.device ? " · ON " + l.device.toUpperCase() : "")).join("\n");
      const client = new Anthropic();
      try {
        // fallbacks: if Claude declines the request, the API re-runs it on a fallback model in the same call
        const stream = client.beta.messages.stream({
          model: "claude-opus-5-5",
          max_tokens: 16000,
          betas: ["server-side-fallback-2026-07-01"],
          fallbacks: "default",
          output_config: { effort: "medium" },
          system: "You write work summaries for the admins of Tcipher Technologies, a software company with Development, Sales and Marketing teams. " +
            "You get one person's complete activity log for a period. Write a summary an admin can read at a glance: what the person worked on, what they finished, what is still open, and anything that needs attention. " +
            "Website time, when given, shows where the person spent time in the browser outside the workspace: mention the main sites under Time and attendance, and say if the tracker was paused for long. " +
            "Use only the facts in the log; never guess. Name tasks and records the way the log does (for example TC-2230 and its title). Times are India time. " +
            "The company expects work to be done on a laptop. Log lines ending in 'ON PHONE' or 'ON TABLET' were done from a phone or tablet: list every one of them, with its time, under 'Done on phone', and mention the count in At a glance. " +
            "Format: plain text with these sections, each a line starting with '## ': At a glance (two or three sentences), Done on phone, Done, In progress, Communication, Time and attendance, Needs attention. " +
            "Under each section use short bullet lines starting with '- '. Skip a section that has nothing. Use **bold** only for task keys or names. Keep it under 350 words, not counting the Done on phone list.",
          messages: [{ role: "user", content: "Person: " + person.full_name + (person.title ? ", " + person.title : "") + (person.vertical ? " (" + person.vertical + ")" : "") +
            "\nPeriod: " + period + ", " + label + "\nTotals: " + JSON.stringify(stats) + (sitesLine ? "\n" + sitesLine : "") + "\n\nActivity log:\n" + log }],
        });
        const msg = await stream.finalMessage();
        if (msg.stop_reason === "refusal") note = "Claude couldn't write a summary for this period. The full timeline is below.";
        else summary = msg.content.filter((b: { type: string }) => b.type === "text").map((b: { type: string; text?: string }) => b.text ?? "").join("\n").trim();
      } catch (e) {
        if (e instanceof Anthropic.AuthenticationError) note = "The ANTHROPIC_API_KEY secret isn't valid. Check it in Supabase › Edge Functions › Secrets.";
        else if (e instanceof Anthropic.RateLimitError) note = "Claude is busy right now. Try again in a minute.";
        else if (e instanceof Anthropic.APIError) note = "Claude couldn't be reached (" + e.status + "). Try again in a minute.";
        else note = "Claude couldn't be reached. Try again in a minute.";
      }
      if (summary) {
        generatedAt = new Date().toISOString();
        await db.from("work_summaries").upsert({ user_id: uid, period, start_day: start, end_day: end, summary, model: "claude-opus-5-5", activity_count: lines.length, generated_at: generatedAt, generated_by: who.user.id }, { onConflict: "user_id,period,start_day" });
      } else if (saved?.summary) { summary = saved.summary; generatedAt = saved.generated_at; cached = true; }
    }

    return json({ person: { id: person.id, name: person.full_name }, period, start, end, summary, cached, generated_at: generatedAt, note, stats, timeline: lines });
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500);
  }
});
