/* Tcipher Tracker: which website is in front, and for how long.
   - Counts only while this browser is the window in use and the person isn't idle (no keyboard or mouse for 2 minutes).
   - Keeps the website's name only (github.com), never the full address or the page; nothing from incognito.
   - Time is split into minutes (India time is worked out by the database) and sent every minute; if the network is down
     it's kept and sent later (up to 3 days).
   - Paused: the time is recorded as "(paused)", so the summary shows a pause rather than a gap. */
importScripts("config.js");

const IDLE_AFTER = 120;        // seconds without keyboard or mouse = idle
const MAX_GAP = 45000;         // never credit more than this between two checks (the computer may have slept)
const S = chrome.storage.local;
let busy = Promise.resolve();  // one check at a time

chrome.idle.setDetectionInterval(IDLE_AFTER);
chrome.runtime.onInstalled.addListener(() => setup());
chrome.runtime.onStartup.addListener(() => setup());
function setup(){ chrome.alarms.create("tick", { periodInMinutes: 0.5 }); step(); badge(); }

chrome.alarms.onAlarm.addListener(a => { if (a.name === "tick") step(true); });
chrome.tabs.onActivated.addListener(() => step());
chrome.tabs.onUpdated.addListener((id, info, tab) => { if (tab.active && info.url) step(); });
chrome.windows.onFocusChanged.addListener(() => step());
chrome.idle.onStateChanged.addListener(() => step());

// what's being worked on right now: a website name, "(paused)", or null (nothing to count)
async function current(){
  const st = await S.get(["pausedUntil"]);
  const idle = await chrome.idle.queryState(IDLE_AFTER);
  if (idle !== "active") return null;                      // idle or screen locked
  if (st.pausedUntil && st.pausedUntil > Date.now()) return "(paused)";
  let win;
  try { win = await chrome.windows.getLastFocused(); } catch (e) { return null; }
  if (!win || !win.focused || win.incognito) return null;  // another app is in front
  const [tab] = await chrome.tabs.query({ active: true, windowId: win.id });
  if (!tab || tab.incognito || !tab.url) return null;
  try {
    const u = new URL(tab.url);
    if (u.protocol === "http:" || u.protocol === "https:") return u.hostname.replace(/^www\./, "").toLowerCase().slice(0, 100);
    if (u.protocol === "file:") return "(a file)";
    return "(browser)";                                     // new tab, settings, extensions…
  } catch (e) { return null; }
}

function step(flushToo){ busy = busy.then(() => doStep(flushToo)).catch(() => {}); return busy; }
async function doStep(flushToo){
  const now = Date.now();
  const st = await S.get(["seg", "pending", "today"]);
  const pending = st.pending || {}, today = st.today && st.today.day === dayKey(now) ? st.today : { day: dayKey(now), sites: {} };
  // credit the time since the last check to what was in front then
  if (st.seg && st.seg.domain) {
    const from = Math.max(st.seg.since, now - MAX_GAP);
    addSpan(pending, today, from, now, st.seg.domain);
  }
  const domain = await current();
  await S.set({ seg: { domain, since: now }, pending, today });
  if (flushToo) await flush();
}
// split a stretch of time into whole minutes; a minute never holds more than 60 seconds in all
function addSpan(pending, today, from, to, domain){
  let t = from;
  while (t < to) {
    const m = Math.floor(t / 60000) * 60000, end = Math.min(to, m + 60000), sec = (end - t) / 1000;
    const slot = pending[m] || (pending[m] = {});
    const used = Object.values(slot).reduce((a, b) => a + b, 0);
    const add = Math.max(0, Math.min(sec, 60 - used));
    if (add > 0) { slot[domain] = (slot[domain] || 0) + add; if (domain !== "(paused)" && dayKey(m) === today.day) today.sites[domain] = (today.sites[domain] || 0) + add; }
    t = end;
  }
}
const dayKey = ms => new Date(ms + 5.5 * 3600000).toISOString().slice(0, 10);   // India date

// send finished minutes
async function flush(){
  const st = await S.get(["key", "pending"]);
  const pending = st.pending || {};
  const nowMin = Math.floor(Date.now() / 60000) * 60000;
  for (const m of Object.keys(pending)) if (+m < Date.now() - 3 * 86400000) delete pending[m];   // too old to send
  const ready = Object.keys(pending).filter(m => +m < nowMin).sort();
  if (!st.key || !ready.length) { await S.set({ pending }); return; }
  const batch = [];
  for (const m of ready.slice(0, 200)) for (const [d, s] of Object.entries(pending[m])) { const sec = Math.round(s); if (sec > 0) batch.push({ t: +m, d, s: Math.min(sec, 60) }); }
  try {
    const r = await fetch(TC.url + "/rest/v1/rpc/tracker_ping", { method: "POST",
      headers: { "Content-Type": "application/json", apikey: TC.key, Authorization: "Bearer " + TC.key },
      body: JSON.stringify({ p_key: st.key, p_minutes: batch }) });
    if (!r.ok) { await S.set({ pending, lastError: "The workspace didn’t answer (" + r.status + ")." }); return; }
    const res = await r.json();
    if (res === "disconnected") { await S.remove(["key", "name"]); await S.set({ pending, lastError: "This browser was disconnected. Open the workspace to connect it again." }); badge(); return; }
    for (const m of ready.slice(0, 200)) delete pending[m];
    await S.set({ pending, lastSent: Date.now(), lastError: "" });
  } catch (e) { await S.set({ pending, lastError: "No connection. Your time is kept and sent later." }); }
}

async function badge(){
  const st = await S.get(["key", "pausedUntil"]);
  const paused = st.pausedUntil && st.pausedUntil > Date.now();
  chrome.action.setBadgeBackgroundColor({ color: paused ? "#B45309" : "#DC2626" });
  chrome.action.setBadgeText({ text: !st.key ? "!" : paused ? "II" : "" });
  chrome.action.setIcon({ path: !st.key || paused ? { 16: "icons/off16.png", 32: "icons/off32.png" } : { 16: "icons/icon16.png", 32: "icons/icon32.png" } });
  chrome.action.setTitle({ title: !st.key ? "Tcipher Tracker: not connected" : paused ? "Tcipher Tracker: paused" : "Tcipher Tracker: on" });
}

// from the popup and from the workspace page (via content.js)
chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  (async () => {
    if (msg.type === "connect" && typeof msg.key === "string" && /^tct_[0-9a-f]{64}$/.test(msg.key)) {
      if (!sender.url || !sender.url.startsWith(TC.site + "/")) return reply({ ok: false });
      await S.set({ key: msg.key, name: String(msg.name || "").slice(0, 80), lastError: "" }); await badge(); await step(true); return reply({ ok: true });
    }
    if (msg.type === "status") { const st = await S.get(["key", "name", "pausedUntil", "today", "lastSent", "lastError", "seg"]); return reply(Object.assign(st, { key: undefined, connected: !!st.key })); }
    if (msg.type === "pause") { await step(); await S.set({ pausedUntil: msg.minutes ? Date.now() + msg.minutes * 60000 : Date.now() + 12 * 3600000 }); await step(); await badge(); return reply({ ok: true }); }
    if (msg.type === "resume") { await step(); await S.set({ pausedUntil: 0 }); await step(); await badge(); return reply({ ok: true }); }
    if (msg.type === "disconnect") { await step(true); await S.remove(["key", "name"]); await badge(); return reply({ ok: true }); }
    reply({ ok: false });
  })();
  return true;
});
// a pause that has run out
chrome.alarms.onAlarm.addListener(async () => { const st = await S.get(["pausedUntil"]); if (st.pausedUntil && st.pausedUntil <= Date.now()) { await S.set({ pausedUntil: 0 }); badge(); } });

setup();   // last, once everything above is defined
