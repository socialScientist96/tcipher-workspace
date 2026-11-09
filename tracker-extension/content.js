/* On internal.tcipher.com only: lets the workspace see that the tracker is installed, and hand it this browser's key. */
(() => {
  const say = connected => window.postMessage({ source: "tc-tracker", type: "here", connected, version: chrome.runtime.getManifest().version }, location.origin);
  const status = () => chrome.runtime.sendMessage({ type: "status" }, st => say(!!(st && st.connected)));
  window.addEventListener("message", e => {
    if (e.source !== window || e.origin !== location.origin || !e.data || e.data.source !== "tc-workspace") return;
    if (e.data.type === "hello") status();
    else if (e.data.type === "connect") chrome.runtime.sendMessage({ type: "connect", key: e.data.key, name: e.data.name }, r => {
      window.postMessage({ source: "tc-tracker", type: "connected", ok: !!(r && r.ok) }, location.origin);
    });
  });
  status();
})();
