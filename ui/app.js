const fixtureSelect = document.getElementById("fixture");
const proposalEl = document.getElementById("proposal");
const runBtn = document.getElementById("run");
const statusEl = document.getElementById("status");
const memoEl = document.getElementById("memo");
const baselineEl = document.getElementById("baseline-out");
const toolsEl = document.getElementById("tools");
const baselineToggle = document.getElementById("baseline");
const svg = document.getElementById("graph");

let fixtures = [];

async function loadFixtures() {
  const res = await fetch("/api/fixtures");
  fixtures = await res.json();
  fixtureSelect.innerHTML = "";
  for (const f of fixtures) {
    const opt = document.createElement("option");
    opt.value = f.id;
    opt.textContent = f.name;
    fixtureSelect.appendChild(opt);
  }
  applyFixture();
}

function applyFixture() {
  const f = fixtures.find((x) => x.id === fixtureSelect.value);
  if (f) proposalEl.value = f.proposal;
}

fixtureSelect.addEventListener("change", applyFixture);

function layout(data) {
  const branches = data.branches || [];
  const edges = data.edges || [];
  const byId = Object.fromEntries(branches.map((b) => [b.id, b]));
  const children = {};
  for (const e of edges) {
    if (e.type !== "forked_from") continue;
    (children[e.to] ||= []).push(e.from);
  }
  const roots = branches.filter((b) => !b.parent_id);
  const positions = {};
  const levels = {};

  function depthOf(id, seen = new Set()) {
    if (levels[id] != null) return levels[id];
    const b = byId[id];
    if (!b || !b.parent_id || seen.has(id)) {
      levels[id] = 0;
      return 0;
    }
    seen.add(id);
    levels[id] = depthOf(b.parent_id, seen) + 1;
    return levels[id];
  }
  for (const b of branches) depthOf(b.id);

  const byLevel = {};
  for (const b of branches) {
    const d = levels[b.id] || 0;
    (byLevel[d] ||= []).push(b);
  }
  const maxLevel = Math.max(0, ...Object.keys(byLevel).map(Number));
  const width = 720;
  const height = 520;
  for (let d = 0; d <= maxLevel; d++) {
    const row = byLevel[d] || [];
    row.forEach((b, i) => {
      const x = ((i + 1) / (row.length + 1)) * width;
      const y = 40 + (d / Math.max(maxLevel, 1)) * (height - 80);
      positions[b.id] = { x, y };
    });
  }
  return { positions, width, height, byId };
}

function renderGraph(data) {
  const rec = data.memo?.recommended_branch_id;
  const { positions, byId } = layout(data);
  const edges = (data.edges || []).filter((e) => e.type === "forked_from");
  let html = "";
  for (const e of edges) {
    const a = positions[e.to];
    const b = positions[e.from];
    if (!a || !b) continue;
    const child = byId[e.from];
    const color = e.via === "red" ? "#b84a2e" : e.via === "blue" ? "#1f6b4a" : "#6b7280";
    const opacity = child && child.alive === false ? 0.35 : 0.9;
    html += `<path class="edge-draw" d="M${a.x},${a.y} C${a.x},${(a.y + b.y) / 2} ${b.x},${(a.y + b.y) / 2} ${b.x},${b.y}" fill="none" stroke="${color}" stroke-width="2.2" opacity="${opacity}" />`;
  }
  for (const [id, p] of Object.entries(positions)) {
    const b = byId[id];
    const dead = b && b.alive === false;
    const isPick = id === rec;
    const side = b?.side_created || "seed";
    const fill = dead ? "#9ca3af" : side === "red" ? "#b84a2e" : side === "blue" ? "#1f6b4a" : "#0f3d2c";
    const r = isPick ? 14 : 10;
    const cls = isPick ? "node-pulse" : "";
    html += `<g class="${cls}">`;
    if (isPick) {
      html += `<circle cx="${p.x}" cy="${p.y}" r="${r + 6}" fill="none" stroke="#d4a017" stroke-width="2" />`;
    }
    html += `<circle cx="${p.x}" cy="${p.y}" r="${r}" fill="${fill}" opacity="${dead ? 0.45 : 1}" />`;
    html += `<text x="${p.x}" y="${p.y - r - 8}" text-anchor="middle" font-size="11" fill="#152018">${id}${dead ? " ✕" : ""}</text>`;
    html += `</g>`;
  }
  svg.innerHTML = html;
}

function renderMemo(data) {
  const m = data.memo || {};
  memoEl.innerHTML = `
    <h3>${escapeHtml(m.title || "Memo")}</h3>
    <div class="pick-id">Recommended ${escapeHtml(m.recommended_branch_id || "?")}</div>
    <p>${escapeHtml(m.prose || "")}</p>
    <p class="kill"><strong>Kill shots:</strong> ${escapeHtml(m.kill_shots || "")}</p>
    <p><strong>Open risks:</strong> ${escapeHtml(m.open_risks || "")}</p>
    <p><strong>Dissent:</strong> ${escapeHtml(m.dissent || "")}</p>
  `;
  baselineEl.innerHTML = `<p>${escapeHtml(data.baseline || "No baseline")}</p>`;
  toolsEl.innerHTML = (data.tool_log || [])
    .map((t) => `<li><span class="${t.ok ? "ok" : "bad"}">${escapeHtml(t.tool)}</span> @ ${escapeHtml(t.branch_id)} — ${escapeHtml(t.detail)}</li>`)
    .join("");
}

function escapeHtml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

runBtn.addEventListener("click", async () => {
  runBtn.disabled = true;
  statusEl.textContent = "Walking Blue/Red branches…";
  try {
    const res = await fetch("/api/run", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        fixture_id: fixtureSelect.value,
        proposal: proposalEl.value,
        baseline: baselineToggle.checked,
        rounds: 3,
      }),
    });
    if (!res.ok) throw new Error(await res.text());
    const data = await res.json();
    renderGraph(data);
    renderMemo(data);
    statusEl.textContent = `Done — ${data.branches?.length || 0} branches, ${data.tool_log?.length || 0} tool visits.`;
  } catch (err) {
    statusEl.textContent = `Error: ${err.message}`;
  } finally {
    runBtn.disabled = false;
  }
});

loadFixtures().catch((e) => {
  statusEl.textContent = `Failed to load fixtures: ${e.message}`;
});
