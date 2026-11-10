// Tcipher workspace: offline cache for the app's own files.
// Keeps the page, the Supabase library and the fonts on this device so the workspace opens quickly on
// slow connections and on repeat visits. Your data (database, chat, files, sign-in) is NEVER cached here:
// those requests go straight to the network, untouched.
//
// The page is always fetched fresh first; the saved copy is used only if the network takes longer than
// 4 seconds or fails (the fresh copy still replaces it in the background, and the app shows its
// "new version available" bar when that happens).
// To switch this off for everyone: delete this file from the site. Browsers drop the cache on their next visit.
const CACHE = "tc-shell-v63";
const PAGE_WAIT_MS = 4000;

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  // pages of this site (the workspace, privacy, terms)
  if (req.mode === "navigate" && url.origin === self.location.origin) { e.respondWith(page(e, url)); return; }
  // libraries at a fixed version, and font files: they never change, so the saved copy is used
  if ((url.hostname === "cdn.jsdelivr.net" || url.hostname === "unpkg.com") && /@\d+\.\d+\.\d+\//.test(url.pathname)) { e.respondWith(cacheFirst(req)); return; }
  if (url.hostname === "fonts.gstatic.com") { e.respondWith(cacheFirst(req)); return; }
  // the font list: the saved copy at once, refreshed in the background
  if (url.hostname === "fonts.googleapis.com") { e.respondWith(staleWhileRevalidate(e, req)); return; }
  // everything else (Supabase, Google, files): not handled here
});

async function page(e, url) {
  const cache = await caches.open(CACHE);
  const key = url.origin + url.pathname;
  const net = fetch(e.request).then((res) => {
    if (res.ok && res.type === "basic") cache.put(key, res.clone());
    return res;
  });
  e.waitUntil(net.catch(() => {}));
  const saved = await cache.match(key);
  if (!saved) return net;
  const late = new Promise((r) => setTimeout(() => r(null), PAGE_WAIT_MS));
  try { return (await Promise.race([net, late])) || saved; }
  catch (_) { return saved; }
}
async function cacheFirst(req) {
  const cache = await caches.open(CACHE);
  const saved = await cache.match(req);
  if (saved) return saved;
  const res = await fetch(req);
  if (res.ok) cache.put(req, res.clone());
  return res;
}
async function staleWhileRevalidate(e, req) {
  const cache = await caches.open(CACHE);
  const saved = await cache.match(req);
  const net = fetch(req).then((res) => { if (res.ok) cache.put(req, res.clone()); return res; });
  e.waitUntil(net.catch(() => {}));
  return saved || net;
}
