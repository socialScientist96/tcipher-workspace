const main = document.getElementById("main"), dot = document.getElementById("dot");
const el = (tag, attrs, ...kids) => { const e = document.createElement(tag); Object.assign(e, attrs || {}); for (const k of kids) if (k != null) e.append(k); return e; };
const hm = s => { const m = Math.round(s / 60); return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m"; };
const send = msg => new Promise(r => chrome.runtime.sendMessage(msg, r));

async function draw(){
  const st = await send({ type: "status" }) || {};
  const paused = st.pausedUntil && st.pausedUntil > Date.now();
  dot.className = "dot" + (!st.connected ? " off" : paused ? " pause" : "");
  main.replaceChildren();
  if (!st.connected) {
    main.append(el("p", {}, el("b", {}, "Not connected yet.")),
      el("p", { className: "muted" }, "Open the workspace, go to ", el("b", {}, "Attendance"), " and press ", el("b", {}, "Connect this browser"), "."),
      el("div", { className: "btns" }, el("a", { className: "btn pri", href: TC.site + "/#attendance", target: "_blank" }, "Open the workspace")));
    if (st.lastError) main.append(el("p", { className: "note err" }, st.lastError));
    return;
  }
  const sites = Object.entries((st.today && st.today.sites) || {}).sort((a, b) => b[1] - a[1]);
  const total = sites.reduce((a, [, s]) => a + s, 0);
  main.append(el("div", { className: "muted" }, "Today" + (st.name ? " · " + st.name : "")), el("div", { className: "total" }, hm(total)));
  for (const [d, s] of sites.slice(0, 8)) main.append(el("div", { className: "row" }, el("span", {}, d), el("span", { className: "muted" }, hm(s))));
  if (!sites.length) main.append(el("p", { className: "muted" }, "Nothing yet today."));
  if (paused) {
    const until = new Date(st.pausedUntil);
    main.append(el("p", { className: "note", style: "color:var(--warn)" }, "Paused until " + until.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) + ". The pause shows in your work summary."),
      el("div", { className: "btns" }, el("button", { className: "pri", onclick: async () => { await send({ type: "resume" }); draw(); } }, "Resume")));
  } else {
    main.append(el("div", { className: "btns" },
      el("button", { onclick: async () => { await send({ type: "pause", minutes: 15 }); draw(); } }, "Pause 15 min"),
      el("button", { onclick: async () => { await send({ type: "pause", minutes: 60 }); draw(); } }, "Pause 1 hour")));
  }
  if (st.lastError) main.append(el("p", { className: "note err" }, st.lastError));
  else if (st.lastSent) main.append(el("p", { className: "note muted" }, "Last sent " + new Date(st.lastSent).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) + "."));
  main.append(el("div", { className: "btns" }, el("button", { onclick: async () => { if (confirm("Disconnect this browser? It stops recording until you connect it again.")) { await send({ type: "disconnect" }); draw(); } } }, "Disconnect")));
}
draw();
