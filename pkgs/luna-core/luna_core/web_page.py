"""The page, the script and the style of the LUNA web app."""

INDEX_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LUNA</title>
<link rel="stylesheet" href="/app.css">
<script src="/app.js" defer></script>
</head>
<body>
<header>
  <h1>LUNA</h1>
  <nav>
    <button data-panel="chat" class="active">Chat</button>
    <button data-panel="approvals">Approvals <span id="approval-count"></span></button>
    <button data-panel="money">Money</button>
    <button data-panel="system">System</button>
  </nav>
</header>
<main>
  <section id="chat" class="panel active">
    <div id="messages" aria-live="polite"></div>
    <div id="camera" hidden>
      <video id="video" autoplay playsinline muted></video>
      <div class="row">
        <select id="camera-list" aria-label="Camera"></select>
        <button id="snap">Show LUNA</button>
        <button id="camera-close">Close camera</button>
      </div>
    </div>
    <div id="attachment" hidden><img id="preview" alt="Image for LUNA"><button id="drop">Remove image</button></div>
    <form id="composer">
      <button type="button" id="camera-open" title="Camera">Camera</button>
      <textarea id="input" rows="2" placeholder="Message LUNA. Enter sends, Shift+Enter is a new line."></textarea>
      <button id="send" type="submit">Send</button>
    </form>
  </section>
  <section id="approvals" class="panel"><div id="approval-list"></div></section>
  <section id="money" class="panel"><pre id="money-text"></pre></section>
  <section id="system" class="panel"><div id="system-info"></div></section>
</main>
</body>
</html>
"""

APP_CSS = """
:root { --bg: #0e1116; --panel: #161b22; --text: #e6edf3; --muted: #8b949e; --accent: #b392f0; --mine: #1f2937; }
@media (prefers-color-scheme: light) {
  :root { --bg: #f6f8fa; --panel: #ffffff; --text: #1f2328; --muted: #57606a; --accent: #6f42c1; --mine: #eef1f5; }
}
* { box-sizing: border-box; }
body { margin: 0; font: 16px/1.5 system-ui, sans-serif; background: var(--bg); color: var(--text); }
header { display: flex; align-items: center; justify-content: space-between; padding: 8px 16px;
         background: var(--panel); border-bottom: 1px solid #30363d; flex-wrap: wrap; gap: 8px; }
h1 { margin: 0; font-size: 20px; letter-spacing: 4px; color: var(--accent); }
nav button, button { background: none; border: 1px solid #30363d; color: var(--text); padding: 6px 12px;
                     border-radius: 6px; cursor: pointer; font: inherit; }
nav button.active { border-color: var(--accent); color: var(--accent); }
main { max-width: 900px; margin: 0 auto; padding: 16px; }
.panel { display: none; } .panel.active { display: block; }
#messages { display: flex; flex-direction: column; gap: 10px; min-height: 50vh; margin-bottom: 12px; }
.msg { padding: 10px 14px; border-radius: 10px; white-space: pre-wrap; word-wrap: break-word; max-width: 90%; }
.msg.user { align-self: flex-end; background: var(--mine); }
.msg.assistant { align-self: flex-start; background: var(--panel); border: 1px solid #30363d; }
.msg.wait { color: var(--muted); font-style: italic; }
#composer { display: flex; gap: 8px; align-items: flex-end; }
textarea { flex: 1; resize: vertical; background: var(--panel); color: var(--text); border: 1px solid #30363d;
           border-radius: 6px; padding: 8px; font: inherit; }
#camera video { width: 100%; max-height: 50vh; background: #000; border-radius: 8px; }
.row { display: flex; gap: 8px; margin: 8px 0; flex-wrap: wrap; }
#attachment img { max-height: 120px; border-radius: 6px; display: block; margin-bottom: 6px; }
.card { background: var(--panel); border: 1px solid #30363d; border-radius: 8px; padding: 12px; margin-bottom: 10px;
        white-space: pre-wrap; }
pre { background: var(--panel); padding: 12px; border-radius: 8px; white-space: pre-wrap; }
table { border-collapse: collapse; width: 100%; } td { padding: 4px 8px; border-bottom: 1px solid #30363d; }
.muted { color: var(--muted); }
"""

APP_JS = r"""
"use strict";
const $ = (id) => document.getElementById(id);
let image = null;
let stream = null;

async function api(path, options = {}) {
  const init = { ...options, headers: { "Content-Type": "application/json", "X-Luna": "1", ...(options.headers || {}) } };
  const response = await fetch(path, init);
  const data = await response.json().catch(() => ({ error: response.statusText }));
  if (!response.ok) throw new Error(data.error || response.statusText);
  return data;
}

function element(tag, cls, text) {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  return node;
}

function addMessage(role, text) {
  const node = element("div", "msg " + role, text);
  $("messages").appendChild(node);
  node.scrollIntoView({ behavior: "smooth", block: "end" });
  return node;
}

async function loadHistory() {
  const data = await api("/api/history");
  $("messages").replaceChildren();
  for (const m of data.messages) addMessage(m.role, m.text);
}

async function send(event) {
  event.preventDefault();
  const text = $("input").value.trim();
  if (!text && !image) return;
  addMessage("user", text + (image ? "\n[image]" : ""));
  const body = { text };
  if (image) body.image = image;
  $("input").value = "";
  clearImage();
  const waiting = addMessage("assistant wait", "LUNA is thinking...");
  $("send").disabled = true;
  try {
    const data = await api("/api/chat", { method: "POST", body: JSON.stringify(body) });
    waiting.className = "msg assistant";
    waiting.textContent = data.reply;
  } catch (error) {
    waiting.textContent = "Error: " + error.message;
  } finally {
    $("send").disabled = false;
    refreshApprovals();
  }
}

async function openCamera() {
  $("camera").hidden = false;
  const devices = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === "videoinput");
  const list = $("camera-list");
  list.replaceChildren();
  devices.forEach((d, i) => list.appendChild(new Option(d.label || "Camera " + (i + 1), d.deviceId)));
  await startCamera(list.value);
}

async function startCamera(deviceId) {
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = await navigator.mediaDevices.getUserMedia({ video: deviceId ? { deviceId: { exact: deviceId } } : true });
  $("video").srcObject = stream;
  // After the first permission, the browser shows the camera names.
  const list = $("camera-list");
  if ([...list.options].some((o) => !o.text || o.text.startsWith("Camera "))) {
    const devices = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === "videoinput");
    const current = list.value;
    list.replaceChildren();
    devices.forEach((d, i) => list.appendChild(new Option(d.label || "Camera " + (i + 1), d.deviceId)));
    list.value = current;
  }
}

function closeCamera() {
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = null;
  $("camera").hidden = true;
}

function snap() {
  const video = $("video");
  const scale = Math.min(1, 1280 / video.videoWidth);
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(video.videoWidth * scale);
  canvas.height = Math.round(video.videoHeight * scale);
  canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height);
  const url = canvas.toDataURL("image/jpeg", 0.85);
  image = { media_type: "image/jpeg", data: url.split(",")[1] };
  $("preview").src = url;
  $("attachment").hidden = false;
  closeCamera();
  $("input").focus();
}

function clearImage() {
  image = null;
  $("attachment").hidden = true;
  $("preview").removeAttribute("src");
}

async function refreshApprovals() {
  const data = await api("/api/approvals");
  $("approval-count").textContent = data.approvals.length ? "(" + data.approvals.length + ")" : "";
  const list = $("approval-list");
  list.replaceChildren();
  if (!data.approvals.length) list.appendChild(element("p", "muted", "No requests wait for you."));
  for (const item of data.approvals) {
    const card = element("div", "card", item.summary + "\n");
    card.appendChild(element("div", "muted", item.id + " - " + item.created));
    const row = element("div", "row");
    for (const action of ["approve", "deny"]) {
      const button = element("button", "", action === "approve" ? "Approve" : "Deny");
      button.addEventListener("click", async () => {
        button.disabled = true;
        const result = await api("/api/approvals/" + item.id + "/" + action, { method: "POST", body: "{}" });
        card.replaceChildren(element("div", "", result.result));
        refreshApprovals();
      });
      row.appendChild(button);
    }
    card.appendChild(row);
    list.appendChild(card);
  }
}

async function loadMoney() {
  $("money-text").textContent = "Loading...";
  $("money-text").textContent = (await api("/api/money")).text;
}

async function loadSystem() {
  const data = await api("/api/system");
  const box = $("system-info");
  box.replaceChildren();
  const table = element("table");
  const rows = [
    ["Started", data.started], ["Updates", data.update], ["Memory", data.memory],
    ["Waiting approvals", String(data.pending_approvals)],
    ...Object.entries(data.settings).map(([k, v]) => [k, typeof v === "object" ? JSON.stringify(v) : String(v)]),
  ];
  for (const [k, v] of rows) {
    const tr = element("tr");
    tr.appendChild(element("td", "muted", k));
    tr.appendChild(element("td", "", v));
    table.appendChild(tr);
  }
  box.appendChild(table);
  box.appendChild(element("h3", "", "Recent events"));
  const log = element("pre");
  log.textContent = data.events.map((e) => e.time.slice(0, 19).replace("T", " ") + "  " + e.event).join("\n");
  box.appendChild(log);
}

function show(panel) {
  document.querySelectorAll("nav button").forEach((b) => b.classList.toggle("active", b.dataset.panel === panel));
  document.querySelectorAll(".panel").forEach((p) => p.classList.toggle("active", p.id === panel));
  if (panel === "approvals") refreshApprovals();
  if (panel === "money") loadMoney().catch((e) => ($("money-text").textContent = "Error: " + e.message));
  if (panel === "system") loadSystem();
}

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("nav button").forEach((b) => b.addEventListener("click", () => show(b.dataset.panel)));
  $("composer").addEventListener("submit", send);
  $("input").addEventListener("keydown", (e) => { if (e.key === "Enter" && !e.shiftKey) send(e); });
  $("camera-open").addEventListener("click", () => openCamera().catch((e) => alertInChat(e)));
  $("camera-list").addEventListener("change", (e) => startCamera(e.target.value));
  $("camera-close").addEventListener("click", closeCamera);
  $("snap").addEventListener("click", snap);
  $("drop").addEventListener("click", clearImage);
  loadHistory().catch((e) => addMessage("assistant wait", "Error: " + e.message));
  refreshApprovals().catch(() => {});
  setInterval(() => refreshApprovals().catch(() => {}), 30000);
});

function alertInChat(error) { addMessage("assistant wait", "Camera error: " + error.message); }
"""
