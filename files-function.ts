// Supabase Edge Function: files
// Keeps the workspace's uploaded files (proposals, offer letters, screenshots, attachments) in Google Drive,
// in a "Tcipher Workspace files" folder, and the nightly database backups in "Tcipher Workspace backups".
// It uses one admin's Google connection with the narrowest Drive permission (drive.file): it can only
// see and change files it created, never anything else in Drive. Every upload, download and delete goes
// through the workspace's normal access rules; nobody's browser ever gets a Google token.
// (2026-11en) Videos added to a task are shared with the company's Google domain (anyone at tcipher.com with the link
// can view; not findable in Drive search), so the workspace plays them in Google Drive's own player and no workspace
// data is used. Everything else stays private. Needs upgrade-2026-11en.sql (files.drive_shared).
//
// Deploy: Supabase > Edge Functions > Deploy a new function > Via Editor, name it exactly: files
// Secrets: uses the ones already there (GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, CRON_SECRET).
// Optional secret: DRIVE_SHARE_DOMAIN (default tcipher.com).
// Turn off "Verify JWT" in the function's settings (the code checks callers itself).
import { createClient } from "npm:@supabase/supabase-js@2";

// deno-lint-ignore no-explicit-any
type Any = any;
const MAX_BYTES = 20 * 1024 * 1024;          // workspace uploads sent through this function
const MAX_DIRECT_BYTES = 100 * 1024 * 1024;  // attachments and chat files: the browser sends them straight to Google Drive
const DIRECT_LABEL: Record<string, string> = { chat: "chat", tasks: "task", test_cases: "test case", features: "feature", notes: "note", projects: "project", releases: "release", tickets: "ticket", meetings: "meeting", leads: "lead", deals: "deal", clients: "client", documents: "document", announcements: "announcement", proposals: "proposal", content: "content", campaigns: "campaign" };
const MAX_BACKUP_BYTES = 500 * 1024 * 1024;  // nightly database backup
const BUCKET = "files";
const DRIVE = "https://www.googleapis.com/drive/v3/";
const UPLOAD = "https://www.googleapis.com/upload/drive/v3/files";

export function makeHandler(deps: {
  url: string; anonKey: string; serviceKey: string;
  googleId: string; googleSecret: string; cronSecret: string;
  shareDomain?: string;
  fetchFn?: typeof fetch;
  makeClient?: (key: string, token?: string) => Any;
}) {
  const f = deps.fetchFn || fetch;
  const client = deps.makeClient || ((key: string, token?: string) => createClient(deps.url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: token ? { headers: { Authorization: "Bearer " + token } } : {},
  }));
  const admin = client(deps.serviceKey);
  const must = (r: Any) => { if (r.error) throw new Error(r.error.message); return r.data; };
  const safeName = (n: string) => (String(n || "file").normalize("NFKD").replace(/[^\w.\-]+/g, "_").replace(/_+/g, "_").slice(-100)) || "file";

  const cors = (req: Request) => ({
    "Access-Control-Allow-Origin": req.headers.get("origin") || "*", "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-file-name, x-file-size, x-cron-secret, x-backup-name, range",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Access-Control-Expose-Headers": "content-disposition, content-range, content-length, accept-ranges",
  });
  const json = (req: Request, body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors(req), "Content-Type": "application/json" } });

  /* ---------- settings: which admin's Drive, and the two folders ---------- */
  async function settings() {
    const row = must(await admin.from("settings").select("data").eq("id", 1).maybeSingle());
    return (row && row.data) || {};
  }
  async function saveSettings(patch: Any) {
    const cur = await settings();
    must(await admin.from("settings").upsert({ id: 1, data: { ...cur, ...patch }, updated_at: new Date().toISOString() }));
  }

  /* ---------- Google: a fresh access token for the storage admin ---------- */
  let cached: { owner: string; token: string; until: number } | null = null;
  async function driveToken(owner: string) {
    if (cached && cached.owner === owner && cached.until > Date.now() + 60000) return cached.token;
    const row = must(await admin.from("google_tokens").select("refresh_token,scopes").eq("user_id", owner).maybeSingle());
    if (!row) throw new Error("The admin who set up Google Drive storage has disconnected Google. Open Admin panel › Storage and connect Google Drive again.");
    if (!String(row.scopes || "").includes("drive.file")) throw new Error("Google Drive permission is missing. Open Admin panel › Storage and click Connect Google Drive.");
    const res = await f("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ client_id: deps.googleId, client_secret: deps.googleSecret, refresh_token: row.refresh_token, grant_type: "refresh_token" }) });
    const t = await res.json().catch(() => ({}));
    if (!res.ok || !t.access_token) throw new Error("Google refused the Drive connection (" + (t.error_description || t.error || res.status) + "). Connect Google Drive again in Admin panel › Storage.");
    cached = { owner, token: t.access_token, until: Date.now() + (t.expires_in || 3000) * 1000 };
    return cached.token;
  }
  async function drive(owner: string, url: string, init: RequestInit = {}) {
    const token = await driveToken(owner);
    return f(url, { ...init, headers: { Authorization: "Bearer " + token, ...(init.headers || {}) } });
  }
  async function driveJson(owner: string, url: string, init: RequestInit = {}) {
    const r = await drive(owner, url, init);
    const b = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error("Google Drive: " + ((b.error && b.error.message) || r.status));
    return b;
  }
  // upload in two steps (start, then send the bytes) so large files stream straight through
  async function driveUpload(owner: string, folder: string, name: string, mime: string, body: BodyInit, size?: number) {
    const start = await drive(owner, UPLOAD + "?uploadType=resumable&supportsAllDrives=true&fields=id,size,name", {
      method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8", "X-Upload-Content-Type": mime || "application/octet-stream", ...(size ? { "X-Upload-Content-Length": String(size) } : {}) },
      body: JSON.stringify({ name, parents: [folder] }) });
    if (!start.ok) { const b = await start.json().catch(() => ({})); throw new Error("Google Drive refused the upload: " + ((b.error && b.error.message) || start.status)); }
    const loc = start.headers.get("location");
    if (!loc) throw new Error("Google Drive didn’t start the upload.");
    const put = await f(loc, { method: "PUT", body, headers: { "Content-Type": mime || "application/octet-stream" }, ...({ duplex: "half" } as Any) });
    const b = await put.json().catch(() => ({}));
    if (!put.ok || !b.id) throw new Error("Google Drive upload failed: " + ((b.error && b.error.message) || put.status));
    return b as { id: string; size?: string; name: string };
  }
  const driveTrash = (owner: string, id: string) =>
    drive(owner, DRIVE + "files/" + encodeURIComponent(id) + "?supportsAllDrives=true", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ trashed: true }) });

  // (2026-11en) a video added to a task: anyone at the company (signed in to Google) can play it from its link, in
  // Google Drive's own player, so the workspace streams none of it. Not findable in Drive search; nothing else is shared.
  // If Google refuses (a company sharing policy, a missing column), the video just plays through the workspace as before.
  async function shareTaskVideo(owner: string, row: Any) {
    if (!row || row.tbl !== "tasks" || row.storage !== "drive" || !/^video\//.test(String(row.mime || "")) || !deps.shareDomain) return row;
    if (!row.path || String(row.path).startsWith("pending-") || row.path === "missing") return row;
    try {
      await driveJson(owner, DRIVE + "files/" + encodeURIComponent(row.path) + "/permissions?supportsAllDrives=true&fields=id", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type: "domain", role: "reader", domain: deps.shareDomain, allowFileDiscovery: false }) });
      const r = await admin.from("files").update({ drive_shared: true }).eq("id", row.id).select().single();
      return r.error ? row : r.data;
    } catch (_) { return row; }
  }

  /* ---------- short-lived links, so a file opens in a new tab or on a phone ---------- */
  const enc = new TextEncoder();
  async function sign(id: string, exp: number) {
    const k = await crypto.subtle.importKey("raw", enc.encode("tc-files:" + deps.serviceKey), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const s = new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(id + "." + exp)));
    return btoa(String.fromCharCode(...s)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  async function verify(id: string, exp: number, sig: string) {
    if (!id || !exp || !sig || exp < Math.floor(Date.now() / 1000)) return false;
    const good = await sign(id, exp);
    if (good.length !== sig.length) return false;
    let d = 0; for (let i = 0; i < good.length; i++) d |= good.charCodeAt(i) ^ sig.charCodeAt(i);
    return d === 0;
  }
  async function caller(req: Request) {
    const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return null;
    const u = await admin.auth.getUser(token);
    if (u.error || !u.data || !u.data.user) return null;
    const prof = must(await admin.from("profiles").select("id,is_admin,is_active").eq("id", u.data.user.id).maybeSingle());
    if (!prof || prof.is_active === false) return null;
    return { id: prof.id, isAdmin: !!prof.is_admin, token };
  }
  async function stream(req: Request, row: Any, download: boolean) {
    let body: BodyInit | null = null, type = row.mime || "application/octet-stream";
    const range = req.headers.get("range");
    if (row.storage === "drive") {
      const s = await settings();
      const r = await drive(s.drive_owner, DRIVE + "files/" + encodeURIComponent(row.path) + "?alt=media&supportsAllDrives=true", range ? { headers: { Range: range } } : {});
      if (!r.ok) return json(req, { error: r.status === 404 ? "This file is no longer in Google Drive (it may have been deleted there)." : "The file couldn’t be fetched from Google Drive (" + r.status + ")." }, 502);
      body = r.body; type = row.mime || r.headers.get("content-type") || type;
      if (r.status === 206) {
        return new Response(body, { status: 206, headers: { ...cors(req), "Content-Type": type, "Content-Range": r.headers.get("content-range") || "", "Content-Length": r.headers.get("content-length") || "",
          "Accept-Ranges": "bytes", "Cache-Control": "private, max-age=300", "X-Content-Type-Options": "nosniff" } });
      }
    } else {
      const d = await admin.storage.from(BUCKET).download(row.path);
      if (d.error || !d.data) return json(req, { error: "The file couldn’t be fetched from storage." }, 502);
      body = d.data;
    }
    const name = String(row.name || "file");
    return new Response(body, { status: 200, headers: { ...cors(req), "Content-Type": type,
      "Content-Disposition": (download ? "attachment" : "inline") + "; filename=\"" + safeName(name) + "\"; filename*=UTF-8''" + encodeURIComponent(name),
      "Cache-Control": "private, max-age=300", "X-Content-Type-Options": "nosniff", "Accept-Ranges": row.storage === "drive" ? "bytes" : "none" } });
  }
  async function ready() {
    const s = await settings();
    if (!s.drive_owner || !s.drive_folder) throw new Error("Google Drive storage isn’t set up yet. An admin can do it in Admin panel › Storage.");
    return s;
  }

  return async function handler(req: Request): Promise<Response> {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
    const url = new URL(req.url);
    const action = url.searchParams.get("action") || "";
    try {
      // ---------- open a file from a short-lived link ----------
      if (action === "get") {
        const id = url.searchParams.get("id") || "", exp = +(url.searchParams.get("exp") || 0), sig = url.searchParams.get("sig") || "";
        if (!(await verify(id, exp, sig))) return json(req, { error: "This link has expired. Open the file again from the workspace." }, 403);
        const row = must(await admin.from("files").select("*").eq("id", id).maybeSingle());
        if (!row) return json(req, { error: "File not found." }, 404);
        return stream(req, row, url.searchParams.get("dl") === "1");
      }

      // ---------- the nightly backup (sent by the backup job with the cron secret) ----------
      if (action === "backup") {
        if (!deps.cronSecret || req.headers.get("x-cron-secret") !== deps.cronSecret) return json(req, { error: "Not allowed." }, 403);
        const s = await settings();
        if (!s.drive_owner || !s.drive_backup_folder) return json(req, { error: "Google Drive storage isn’t set up yet (Admin panel › Storage)." }, 503);
        const name = String(req.headers.get("x-backup-name") || "").replace(/[^\w.\-]+/g, "_");
        if (!/^tcipher-db-\d{4}-\d{2}-\d{2}\.dump\.enc$/.test(name)) return json(req, { error: "Unexpected backup name." }, 400);
        const size = +(req.headers.get("x-file-size") || req.headers.get("content-length") || 0);
        if (size > MAX_BACKUP_BYTES) return json(req, { error: "Backup is larger than expected." }, 413);
        if (!req.body) return json(req, { error: "No backup was sent." }, 400);
        const up = await driveUpload(s.drive_owner, s.drive_backup_folder, name, "application/octet-stream", req.body, size || undefined);
        // keep 30 days of daily backups, plus the first backup of every month for good
        const list = await driveJson(s.drive_owner, DRIVE + "files?supportsAllDrives=true&includeItemsFromAllDrives=true&pageSize=1000&fields=files(id,name)&q=" +
          encodeURIComponent("'" + s.drive_backup_folder + "' in parents and trashed = false"));
        const cutoff = new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10);
        const byMonth: Record<string, string> = {};
        for (const x of list.files || []) { const m = /tcipher-db-(\d{4}-\d{2})-(\d{2})/.exec(x.name); if (m && (!byMonth[m[1]] || x.name < byMonth[m[1]])) byMonth[m[1]] = x.name; }
        const keepMonthly = new Set(Object.values(byMonth));
        let removed = 0;
        for (const x of list.files || []) {
          const m = /tcipher-db-(\d{4}-\d{2}-\d{2})/.exec(x.name);
          if (m && m[1] < cutoff && !keepMonthly.has(x.name)) { await driveTrash(s.drive_owner, x.id); removed++; }
        }
        await saveSettings({ last_backup_at: new Date().toISOString(), last_backup_name: name, last_backup_bytes: +(up.size || size || 0) });
        return json(req, { ok: true, saved: name, removed });
      }

      const me = await caller(req);
      if (!me) return json(req, { error: "Please sign in again." }, 401);
      const asMe = client(deps.anonKey, me.token);   // the person's own access rules apply

      if (action === "upload") {
        const s = await ready();
        const tbl = url.searchParams.get("tbl") || "", entity = url.searchParams.get("entity_id") || "";
        const name = decodeURIComponent(req.headers.get("x-file-name") || url.searchParams.get("name") || "file").slice(0, 200);
        const size = +(req.headers.get("x-file-size") || req.headers.get("content-length") || 0);
        const mime = req.headers.get("content-type") || "application/octet-stream";
        if (!tbl || !entity) return json(req, { error: "Missing where the file belongs." }, 400);
        if (size > MAX_BYTES) return json(req, { error: "That file is over 20 MB." }, 413);
        if (!req.body) return json(req, { error: "No file was sent." }, 400);
        // record it first, as the person: if they're not allowed to attach files here, this is refused
        const ins = await asMe.from("files").insert({ tbl, entity_id: entity, name, path: "pending-" + crypto.randomUUID(), size, mime, uploaded_by: me.id, storage: "drive" }).select().single();
        if (ins.error) return json(req, { error: /row-level security|permission/i.test(ins.error.message) ? "You can’t attach files here." : ins.error.message }, 403);
        try {
          const up = await driveUpload(s.drive_owner, s.drive_folder, tbl + " – " + safeName(name), mime, req.body, size || undefined);
          const row = must(await admin.from("files").update({ path: up.id, size: +(up.size || size || 0) }).eq("id", ins.data.id).select().single());
          return json(req, { ok: true, file: await shareTaskVideo(s.drive_owner, row) });
        } catch (e) {
          await admin.from("files").delete().eq("id", ins.data.id);
          return json(req, { error: String((e as Error).message || e) }, 502);
        }
      }

      // ---------- large files (chat, up to 100 MB): the browser uploads straight to Google Drive ----------
      if (action === "start_upload") {
        const s = await ready();
        const b = await req.json().catch(() => ({}));
        const tbl = String(b.tbl || ""), entity = String(b.entity_id || ""), name = String(b.name || "file").slice(0, 200), size = +b.size || 0, mime = String(b.mime || "application/octet-stream").slice(0, 120);
        if (!DIRECT_LABEL[tbl] || !entity) return json(req, { error: "Files can’t be attached here." }, 400);
        if (!size || size > MAX_DIRECT_BYTES) return json(req, { error: "Files can be up to 100 MB." }, 413);
        // tidy away this person's uploads that never finished
        await admin.from("files").delete().eq("uploaded_by", me.id).like("path", "pending-%").lt("created_at", new Date(Date.now() - 3 * 3600e3).toISOString());
        // record it first, as the person: if they're not in this conversation, this is refused
        const ins = await asMe.from("files").insert({ tbl, entity_id: entity, name, path: "pending-" + crypto.randomUUID(), size, mime, uploaded_by: me.id, storage: "drive" }).select().single();
        if (ins.error) return json(req, { error: /row-level security|permission/i.test(ins.error.message) ? (tbl === "chat" ? "You can’t send files in this conversation." : "You can’t attach files to this.") : ins.error.message }, 403);
        const origin = req.headers.get("origin") || "";
        const startRes = await drive(s.drive_owner, UPLOAD + "?uploadType=resumable&supportsAllDrives=true&fields=id,size,name,parents", {
          method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8", "X-Upload-Content-Type": mime, "X-Upload-Content-Length": String(size), ...(origin ? { Origin: origin } : {}) },
          body: JSON.stringify({ name: DIRECT_LABEL[tbl] + " – " + safeName(name), parents: [s.drive_folder] }) });
        const loc = startRes.headers.get("location");
        if (!startRes.ok || !loc) { await admin.from("files").delete().eq("id", ins.data.id); const e = await startRes.json().catch(() => ({})); return json(req, { error: "Google Drive didn’t start the upload: " + ((e.error && e.error.message) || startRes.status) }, 502); }
        return json(req, { ok: true, file_id: ins.data.id, upload_url: loc });
      }
      if (action === "finish_upload") {
        const s = await ready();
        const b = await req.json().catch(() => ({}));
        const row = must(await admin.from("files").select("*").eq("id", String(b.file_id || "")).maybeSingle());
        if (!row || row.uploaded_by !== me.id || !String(row.path).startsWith("pending-")) return json(req, { error: "Upload not found." }, 404);
        // check with Google that the file really is there, in the workspace folder, at the right size
        let meta: Any = null;
        try { meta = await driveJson(s.drive_owner, DRIVE + "files/" + encodeURIComponent(String(b.drive_id || "")) + "?supportsAllDrives=true&fields=id,size,parents,trashed"); } catch (_) { meta = null; }
        if (!meta || meta.trashed || !(meta.parents || []).includes(s.drive_folder) || +(meta.size || 0) !== +row.size) {
          await admin.from("files").delete().eq("id", row.id);
          if (meta && meta.id) { try { await driveTrash(s.drive_owner, meta.id); } catch (_) { /* gone */ } }
          return json(req, { error: "The upload didn’t arrive complete. Please send the file again." }, 409);
        }
        const done = must(await admin.from("files").update({ path: meta.id }).eq("id", row.id).select().single());
        return json(req, { ok: true, file: await shareTaskVideo(s.drive_owner, done) });
      }

      if (action === "link") {
        const id = url.searchParams.get("id") || "";
        const row = must(await asMe.from("files").select("id").eq("id", id).maybeSingle());   // can this person see it?
        if (!row) return json(req, { error: "File not found, or you can’t open it." }, 404);
        const exp = Math.floor(Date.now() / 1000) + (url.searchParams.get("long") === "1" ? 3600 : 300);
        const base = deps.url.replace(/\/+$/, "") + "/functions/v1/files";
        return json(req, { ok: true, url: base + "?action=get&id=" + encodeURIComponent(id) + "&exp=" + exp + "&sig=" + (await sign(id, exp)), expires: exp });
      }

      if (action === "delete") {
        const id = url.searchParams.get("id") || "";
        const gone = await asMe.from("files").delete().eq("id", id).select();
        if (gone.error) return json(req, { error: gone.error.message }, 403);
        const row = (gone.data || [])[0];
        if (!row) return json(req, { error: "File not found, or you can’t delete it." }, 404);
        if (row.storage === "drive") { const s = await settings(); try { await driveTrash(s.drive_owner, row.path); } catch (_) { /* already gone in Drive */ } }   // to Drive's Bin for 30 days
        else await admin.storage.from(BUCKET).remove([row.path]);
        return json(req, { ok: true });
      }

      // ---------- admins: set up, check, and move existing files across ----------
      if (!me.isAdmin) return json(req, { error: "Only admins can do this." }, 403);

      // (2026-11en) share task videos uploaded before this change (once; safe to repeat)
      if (action === "share_videos") {
        const s = await ready();
        if (!deps.shareDomain) return json(req, { error: "Sharing with the company is turned off (DRIVE_SHARE_DOMAIN is empty)." }, 400);
        const rows = must(await admin.from("files").select("*").eq("tbl", "tasks").eq("storage", "drive").like("mime", "video/%").eq("drive_shared", false).limit(200)) || [];
        let shared = 0, failed = 0;
        for (const r of rows) { const x = await shareTaskVideo(s.drive_owner, r); if (x && x.drive_shared) shared++; else failed++; }
        return json(req, { ok: true, shared, failed, domain: deps.shareDomain });
      }

      if (action === "setup") {
        // the admin calling this becomes the Drive account the workspace uses; the two folders are created once
        const tok = must(await admin.from("google_tokens").select("scopes").eq("user_id", me.id).maybeSingle());
        if (!tok || !String(tok.scopes || "").includes("drive.file")) return json(req, { error: "Connect Google Drive first, and tick the Google Drive box on Google’s screen." }, 400);
        const s = await settings();
        const sameOwner = s.drive_owner === me.id;
        if (s.drive_owner && !sameOwner && s.drive_folder) {
          const n = (await admin.from("files").select("id", { count: "exact", head: true }).eq("storage", "drive")).count ?? 0;
          if (n > 0) return json(req, { error: "Google Drive storage is already set up by another admin, with " + n + " file" + (n === 1 ? "" : "s") + ". Ask them to reconnect it, so those files stay reachable." }, 409);
        }
        cached = null;
        const exists = async (id: string) => { if (!id || !sameOwner) return false; try { const x = await driveJson(me.id, DRIVE + "files/" + encodeURIComponent(id) + "?supportsAllDrives=true&fields=id,trashed"); return !x.trashed; } catch (_) { return false; } };
        const mkFolder = async (name: string) => (await driveJson(me.id, DRIVE + "files?supportsAllDrives=true&fields=id", { method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name, mimeType: "application/vnd.google-apps.folder", description: "Created by Tcipher Workspace. Keep this folder private: share it only with admins." }) })).id;
        const folder = (await exists(s.drive_folder)) ? s.drive_folder : await mkFolder("Tcipher Workspace files");
        const backup = (await exists(s.drive_backup_folder)) ? s.drive_backup_folder : await mkFolder("Tcipher Workspace backups");
        await saveSettings({ drive_owner: me.id, drive_folder: folder, drive_backup_folder: backup });
        return json(req, { ok: true, folder, backup_folder: backup });
      }

      if (action === "status") {
        const s = await settings();
        const usage = must(await asMe.rpc("storage_usage"));
        if (!s.drive_owner || !s.drive_folder) return json(req, { ok: false, setup: false, usage, message: "Not set up yet." });
        try {
          const about = await driveJson(s.drive_owner, DRIVE + "about?fields=user(emailAddress,displayName),storageQuota");
          const folder = await driveJson(s.drive_owner, DRIVE + "files/" + encodeURIComponent(s.drive_folder) + "?supportsAllDrives=true&fields=id,name,trashed,driveId,webViewLink");
          const bfolder = await driveJson(s.drive_owner, DRIVE + "files/" + encodeURIComponent(s.drive_backup_folder) + "?supportsAllDrives=true&fields=id,name,webViewLink,driveId").catch(() => null);
          return json(req, { ok: !folder.trashed, setup: true, usage, account: about.user && about.user.emailAddress, quota: about.storageQuota,
            folder: { name: folder.name, link: folder.webViewLink, shared_drive: !!folder.driveId, trashed: !!folder.trashed },
            backup_folder: bfolder && { name: bfolder.name, link: bfolder.webViewLink, shared_drive: !!bfolder.driveId },
            last_backup_at: s.last_backup_at || null, last_backup_name: s.last_backup_name || null, last_backup_bytes: s.last_backup_bytes || 0,
            message: folder.trashed ? "The “" + folder.name + "” folder is in Drive’s Bin. Restore it in Google Drive." : "Connected to Google Drive." });
        } catch (e) { return json(req, { ok: false, setup: true, usage, message: String((e as Error).message || e) }); }
      }

      if (action === "migrate") {
        const s = await ready();
        const started = Date.now();
        const rows = must(await admin.from("files").select("*").eq("storage", "supabase").order("created_at").limit(25)) || [];
        let moved = 0; const failed: Any[] = [];
        for (const row of rows) {
          if (Date.now() - started > 100000) break;    // stay inside the time limit; the page calls again
          const oldPath = String(row.path);   // remember where it was before the record changes
          try {
            const d = await admin.storage.from(BUCKET).download(oldPath);
            if (d.error || !d.data) throw new Error("not found in Supabase storage");
            const bytes = new Uint8Array(await d.data.arrayBuffer());
            const up = await driveUpload(s.drive_owner, s.drive_folder, row.tbl + " – " + safeName(row.name), row.mime || "application/octet-stream", bytes, bytes.length);
            if (+(up.size || 0) !== bytes.length) { await driveTrash(s.drive_owner, up.id); throw new Error("the copy in Drive didn’t match"); }   // checked before the old copy goes
            must(await admin.from("files").update({ storage: "drive", path: up.id, size: bytes.length }).eq("id", row.id));
            await admin.storage.from(BUCKET).remove([oldPath]);
            moved++;
          } catch (e) {
            failed.push({ id: row.id, name: row.name, error: String((e as Error).message || e) });
            if (/not found in Supabase/.test(String((e as Error).message))) await admin.from("files").update({ storage: "drive", path: "missing" }).eq("id", row.id);   // don't block the rest
          }
        }
        const remaining = (await admin.from("files").select("id", { count: "exact", head: true }).eq("storage", "supabase")).count ?? 0;
        return json(req, { ok: true, moved, failed, remaining });
      }

      return json(req, { error: "Unknown action." }, 400);
    } catch (e) {
      return json(req, { error: String((e as Error).message || e) }, 500);
    }
  };
}

if (import.meta.main) {
  const pick = (v: string, legacy: string) => { try { const k = JSON.parse(Deno.env.get(v) ?? "{}"); if (k && k.default) return k.default; } catch (_) { /* legacy */ } return Deno.env.get(legacy) ?? ""; };
  Deno.serve(makeHandler({
    url: Deno.env.get("SUPABASE_URL")!, anonKey: pick("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY"), serviceKey: pick("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY"),
    googleId: Deno.env.get("GOOGLE_CLIENT_ID") ?? "", googleSecret: Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "", cronSecret: Deno.env.get("CRON_SECRET") ?? "",
    shareDomain: (Deno.env.get("DRIVE_SHARE_DOMAIN") ?? "tcipher.com").trim(),
  }));
}
