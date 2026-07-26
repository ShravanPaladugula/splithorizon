(() => {
  const $ = (id) => document.getElementById(id);

  const SCHEMA_COPY = {
    idea: "You state one business decision. Everything else hangs off that single question.",
    seed: "SeedWorldWalker turns your answers into Jac nodes: entities, constraints, goals — the world graph.",
    blue: "BlueWalker argues for the growth move (hire, spend, expand). It forks a Branch and visits BudgetCalc.",
    red: "RedWalker attacks that plan with stressors. If a hard constraint breaks, the branch is killed.",
    tools: "Tools are places on the graph. Walkers visit BudgetCalc, ConstraintCheck, ScenarioInject for facts — not vibes.",
    score: "ScoreWalker ranks alive branches by goal coverage, residual risk, cost, and uncertainty.",
    arbiter: "ArbiterWalker picks the surviving leaf and writes the memo you’d show your co-founder.",
  };

  const WIZARD = [
    {
      label: "Step 1 of 4",
      title: "What kind of business is this?",
      help: "One line — industry and rough size.",
      render: (state) => `
        <label for="w-biz">Business</label>
        <input id="w-biz" type="text" maxlength="120" value="${escapeAttr(state.business)}"
          placeholder="e.g. Bootstrapped B2B SaaS, 4 people, ~$40k MRR" />
      `,
      read: () => ({ business: $("w-biz").value.trim() || "Bootstrapped SaaS, small team" }),
    },
    {
      label: "Step 2 of 4",
      title: "How aggressive is the hire?",
      help: "Pick the move you’re tempted to make. Blue will defend it; Red will try to break it.",
      render: (state) => `
        <div class="choice-grid" id="w-hire-choices">
          ${[
            ["blast", "Hire 3 now", "2 engineers + 1 AE immediately"],
            ["staged", "Hire 1, then decide", "One senior hire; gate the rest"],
            ["freeze", "Stay lean", "No new FTEs this quarter"],
          ]
            .map(
              ([id, title, sub]) => `
            <button type="button" class="choice ${state.hireMode === id ? "on" : ""}" data-hire="${id}">
              <strong>${title}</strong><span>${sub}</span>
            </button>`
            )
            .join("")}
        </div>
      `,
      bind: (state) => {
        $("w-hire-choices").querySelectorAll(".choice").forEach((btn) => {
          btn.addEventListener("click", () => {
            state.hireMode = btn.dataset.hire;
            $("w-hire-choices").querySelectorAll(".choice").forEach((b) => b.classList.toggle("on", b === btn));
          });
        });
      },
      read: (state) => ({ hireMode: state.hireMode || "blast" }),
    },
    {
      label: "Step 3 of 4",
      title: "What’s the hard floor?",
      help: "Cash runway and hire budget — Red will attack these.",
      render: (state) => `
        <label for="w-runway">Cash runway (months)</label>
        <input id="w-runway" type="number" min="3" max="36" value="${state.runway}" />
        <label for="w-budget">Quarterly hiring budget ($)</label>
        <input id="w-budget" type="number" min="1000" step="1000" value="${state.budget}" />
        <label for="w-floor">Minimum runway you refuse to breach</label>
        <input id="w-floor" type="number" min="3" max="18" value="${state.floor}" />
      `,
      read: () => ({
        runway: Number($("w-runway").value) || 11,
        budget: Number($("w-budget").value) || 96000,
        floor: Number($("w-floor").value) || 6,
      }),
    },
    {
      label: "Step 4 of 4",
      title: "What does success look like?",
      help: "One concrete goal. Keep it measurable.",
      render: (state) => `
        <label for="w-goal">Success goal</label>
        <textarea id="w-goal" maxlength="280">${escapeAttr(state.goal)}</textarea>
      `,
      read: () => ({
        goal: $("w-goal").value.trim() || "Raise MRR ≥ 30% in 2 quarters without a bridge round",
      }),
    },
  ];

  const state = {
    business: "Bootstrapped SaaS, 4 people, ~$42k MRR",
    hireMode: "blast",
    runway: 11,
    budget: 96000,
    floor: 6,
    goal: "Raise MRR ≥ 30% within 2 quarters without a bridge round",
    step: 0,
    proposal: "",
    fixtureId: "hire",
  };

  let runData = null;
  let eventIndex = -1;
  let playing = false;
  let playTimer = null;
  let selectedId = null;
  let zoomBehavior = null;
  let svgReady = false;

  function escapeHtml(s) {
    return String(s ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }
  function escapeAttr(s) {
    return escapeHtml(s).replaceAll("'", "&#39;");
  }
  function pct(n) {
    return n == null || Number.isNaN(n) ? "—" : `${Math.round(Number(n) * 100)}%`;
  }
  function money(n) {
    return n == null ? "—" : `$${Number(n).toLocaleString()}`;
  }

  function showView(name) {
    ["landing", "wizard", "app"].forEach((v) => {
      const el = $(`view-${v}`);
      if (el) el.hidden = v !== name;
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  /* ---------- Landing / wizard ---------- */
  $("cta-start").addEventListener("click", () => {
    state.step = 0;
    renderWizard();
    showView("wizard");
  });
  $("wiz-back-landing").addEventListener("click", () => showView("landing"));
  $("btn-new").addEventListener("click", () => {
    stopPlay();
    showView("landing");
  });

  function hireLabel(mode) {
    if (mode === "staged") return "Hire 1 senior person first, then gate further hires";
    if (mode === "freeze") return "Stay lean — no new FTEs this quarter";
    return "Hire 3 full-time people immediately (2 eng + 1 AE)";
  }

  function buildProposal() {
    const mode = state.hireMode || "blast";
    return `DECISION: ${hireLabel(mode)}.

Business: ${state.business}. Current cash runway: ~${state.runway} months.
Tempted move: ${hireLabel(mode)}.
Hiring budget this quarter: $${Number(state.budget).toLocaleString()}.
HARD CONSTRAINTS: (1) Do not drop cash runway below ${state.floor} months. (2) Quarterly spend on new hires ≤ $${Number(state.budget).toLocaleString()}. (3) Must not freeze product delivery for > 6 weeks during onboarding.
GOAL: ${state.goal}`;
  }

  function renderWizard() {
    const step = WIZARD[state.step];
    $("wiz-step-label").textContent = step.label;
    $("wiz-title").textContent = step.title;
    $("wiz-help").textContent = step.help;
    $("wiz-body").innerHTML = step.render(state);
    if (step.bind) step.bind(state);
    $("wiz-prev").hidden = state.step === 0;
    $("wiz-next").textContent = state.step === WIZARD.length - 1 ? "Open the war room" : "Continue";
    document.querySelectorAll(".wiz-progress i").forEach((dot) => {
      dot.classList.toggle("on", Number(dot.dataset.step) <= state.step);
    });
  }

  $("wiz-prev").addEventListener("click", () => {
    Object.assign(state, WIZARD[state.step].read(state));
    state.step = Math.max(0, state.step - 1);
    renderWizard();
  });

  $("wiz-next").addEventListener("click", () => {
    Object.assign(state, WIZARD[state.step].read(state));
    if (state.step < WIZARD.length - 1) {
      state.step += 1;
      renderWizard();
      return;
    }
    state.proposal = buildProposal();
    state.fixtureId = "hire";
    $("decision-summary").textContent = state.proposal;
    showView("app");
    initSchemaRail();
    renderTypeChips();
  });

  /* ---------- Schema rail (fixed, L→R) ---------- */
  function initSchemaRail() {
    const explain = $("schema-explain");
    document.querySelectorAll(".schema-node").forEach((btn) => {
      btn.addEventListener("click", () => {
        document.querySelectorAll(".schema-node").forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
        explain.textContent = SCHEMA_COPY[btn.dataset.schema] || "";
      });
    });
    explain.textContent = SCHEMA_COPY.idea;
  }

  function lightSchemaFromEvent(kind) {
    const map = {
      seed: "seed",
      blue: "blue",
      red: "red",
      tool: "tools",
      arbiter: "arbiter",
    };
    const key = map[kind];
    document.querySelectorAll(".schema-node").forEach((b) => {
      b.classList.toggle("lit", key && b.dataset.schema === key);
    });
    if (key && SCHEMA_COPY[key]) {
      $("schema-explain").textContent = SCHEMA_COPY[key];
    }
  }

  function renderTypeChips() {
    const root = $("schema-graph");
    const detail = $("schema-detail");
    const schema = window.SPLIT_SCHEMA;
    if (!schema || !root) return;
    root.innerHTML = "";
    const add = (item, kind) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = `schema-chip ${kind}`;
      btn.textContent = item.id;
      btn.addEventListener("click", () => {
        root.querySelectorAll(".schema-chip").forEach((c) => c.classList.remove("active"));
        btn.classList.add("active");
        if (kind === "edge") {
          detail.innerHTML = `<strong>${escapeHtml(item.id)}</strong><p>${escapeHtml(item.blurb)}</p>
            <p><code>${escapeHtml(item.from)}</code> → <code>${escapeHtml(item.to)}</code></p>`;
        } else if (kind === "walker") {
          detail.innerHTML = `<strong>${escapeHtml(item.id)}</strong><p>${escapeHtml(item.blurb)}</p>`;
        } else {
          detail.innerHTML = `<strong>${escapeHtml(item.id)}</strong><p>${escapeHtml(item.blurb)}</p>
            <div class="field-row">${(item.fields || []).map((f) => `<code>${escapeHtml(f)}</code>`).join("")}</div>`;
        }
      });
      root.appendChild(btn);
    };
    schema.nodes.forEach((n) => add(n, "node"));
    schema.edges.forEach((e) => add(e, "edge"));
    schema.walkers.forEach((w) => add(w, "walker"));
  }

  /* ---------- Stable horizontal tree (no page jank) ---------- */
  function colorFor(side, alive) {
    if (alive === false) return "#7a8490";
    if (side === "red") return "#e85d04";
    if (side === "blue") return "#0d6e6e";
    return "#1b3a4b";
  }

  function buildHierarchy(data, allowedIds) {
    const branches = (data.branches || []).filter((b) => allowedIds.has(b.id));
    const byId = Object.fromEntries(branches.map((b) => [b.id, { ...b, children: [] }]));
    let root = null;
    for (const b of branches) {
      if (b.parent_id && byId[b.parent_id]) byId[b.parent_id].children.push(byId[b.id]);
      else if (!b.parent_id || !allowedIds.has(b.parent_id)) root = byId[b.id];
    }
    if (!root) {
      const seeds = branches.filter((b) => !b.parent_id);
      root = seeds[0] ? byId[seeds[0].id] : null;
    }
    return root;
  }

  function ensureSvg() {
    const svg = d3.select("#graph");
    const stage = $("viz-stage");
    const width = stage.clientWidth || 700;
    const height = stage.clientHeight || 480;
    svg.attr("viewBox", `0 0 ${width} ${height}`).attr("width", "100%").attr("height", "100%");
    if (!svgReady) {
      svg.selectAll("*").remove();
      const g = svg.append("g").attr("class", "viewport");
      zoomBehavior = d3
        .zoom()
        .scaleExtent([0.5, 2.2])
        .on("zoom", (event) => g.attr("transform", event.transform));
      svg.call(zoomBehavior);
      g.append("g").attr("class", "links");
      g.append("g").attr("class", "nodes");
      svgReady = true;
      svg.on("click", () => {
        selectedId = null;
        $("inspector").hidden = true;
        g.selectAll(".branch-node").classed("selected", false);
      });
    }
    return { svg, width, height, g: svg.select("g.viewport") };
  }

  function truncate(s, n = 22) {
    const t = String(s || "");
    return t.length > n ? `${t.slice(0, n - 1)}…` : t;
  }

  function renderGraph(data, allowedIds) {
    if (typeof d3 === "undefined") return;
    const { width, height, g } = ensureSvg();
    const rootData = buildHierarchy(data, allowedIds);
    const linksG = g.select("g.links");
    const nodesG = g.select("g.nodes");

    if (!rootData) {
      linksG.selectAll("*").remove();
      nodesG.selectAll("*").remove();
      return;
    }

    const root = d3.hierarchy(rootData);
    // Left → right layout (depth on X)
    d3.tree().size([height - 70, width - 140])(root);
    root.each((d) => {
      const x = d.y + 70; // depth → horizontal
      const y = d.x + 35;
      d.x = x;
      d.y = y;
    });

    const recommended = data.memo?.recommended_branch_id;
    const linkPath = (d) => {
      const s = d.source;
      const t = d.target;
      const mid = (s.x + t.x) / 2;
      return `M${s.x},${s.y}C${mid},${s.y} ${mid},${t.y} ${t.x},${t.y}`;
    };

    const links = linksG
      .selectAll("path.branch-link")
      .data(root.links(), (d) => d.target.data.id);

    links.join(
      (enter) =>
        enter
          .append("path")
          .attr("class", (d) => {
            const side = d.target.data.side_created || "seed";
            const dead = d.target.data.alive === false;
            return `branch-link ${dead ? "dead" : side}`;
          })
          .attr("d", linkPath)
          .attr("stroke-opacity", 0)
          .call((s) => s.transition().duration(450).attr("stroke-opacity", null)),
      (update) =>
        update
          .attr("class", (d) => {
            const side = d.target.data.side_created || "seed";
            const dead = d.target.data.alive === false;
            return `branch-link ${dead ? "dead" : side}`;
          })
          .transition()
          .duration(350)
          .attr("d", linkPath),
      (exit) => exit.transition().duration(200).attr("stroke-opacity", 0).remove()
    );

    const nodes = nodesG.selectAll("g.branch-node").data(root.descendants(), (d) => d.data.id);

    const nodesEnter = nodes
      .enter()
      .append("g")
      .attr("class", "branch-node")
      .attr("transform", (d) => `translate(${d.x},${d.y})`)
      .style("opacity", 0)
      .on("click", (event, d) => {
        event.stopPropagation();
        selectBranch(d.data.id);
      });

    nodesEnter.append("circle").attr("class", "walker-pulse").attr("r", 10);
    nodesEnter
      .append("circle")
      .attr("class", "node-core")
      .attr("r", 10)
      .attr("fill", (d) => colorFor(d.data.side_created, d.data.alive))
      .attr("stroke", "#fff")
      .attr("stroke-width", 1.5);
    nodesEnter
      .append("text")
      .attr("class", "node-label")
      .attr("text-anchor", "middle")
      .attr("y", -14);
    nodesEnter
      .append("text")
      .attr("class", "node-sub")
      .attr("text-anchor", "middle")
      .attr("y", 24);

    nodesEnter.transition().duration(400).style("opacity", 1);

    const merged = nodesEnter.merge(nodes);
    merged
      .transition()
      .duration(350)
      .attr("transform", (d) => `translate(${d.x},${d.y})`);
    merged.select(".node-core")
      .attr("r", (d) => (d.data.id === recommended ? 13 : 10))
      .attr("fill", (d) => colorFor(d.data.side_created, d.data.alive))
      .attr("stroke", (d) => (d.data.id === recommended ? "#c9a227" : "#fff"))
      .attr("stroke-width", (d) => (d.data.id === recommended ? 3 : 1.5));
    merged.select(".node-label").text((d) => `${d.data.id}${d.data.alive === false ? " ✕" : ""}`);
    merged
      .select(".node-sub")
      .text((d) => truncate(d.data.last_action || d.data.last_stressor || d.data.label, 24));
    merged.classed("selected", (d) => d.data.id === selectedId);

    nodes.exit().transition().duration(200).style("opacity", 0).remove();
  }

  function pulseBranch(id) {
    const sel = d3.select("#graph").selectAll(".branch-node").filter((d) => d.data.id === id).select(".walker-pulse");
    sel.classed("on", false);
    requestAnimationFrame(() => sel.classed("on", true));
  }

  /* ---------- Playback ---------- */
  function idsThroughEvent(index) {
    const ids = new Set();
    const events = runData?.events || [];
    for (let i = 0; i <= index; i++) {
      const ev = events[i];
      if (!ev?.branch_id) continue;
      ids.add(ev.branch_id);
      let cur = runData.branches.find((b) => b.id === ev.branch_id);
      while (cur?.parent_id) {
        ids.add(cur.parent_id);
        cur = runData.branches.find((b) => b.id === cur.parent_id);
      }
    }
    const seed = (runData?.branches || []).find((b) => !b.parent_id);
    if (seed && index >= 0) ids.add(seed.id);
    return ids;
  }

  function setEventIndex(i, { pulse = true } = {}) {
    if (!runData) return;
    const events = runData.events || [];
    eventIndex = Math.max(-1, Math.min(i, events.length - 1));
    $("scrub").value = String(Math.max(0, eventIndex));
    $("scrub-label").textContent = `${Math.max(0, eventIndex + 1)} / ${events.length}`;
    const visible = eventIndex < 0 ? new Set() : idsThroughEvent(eventIndex);
    renderGraph(runData, visible.size ? visible : new Set(["__none__"]));
    $("timeline").querySelectorAll("li").forEach((li, idx) => li.classList.toggle("active", idx === eventIndex));
    const active = $("timeline").querySelector("li.active");
    if (active) active.scrollIntoView({ block: "nearest" });
    if (eventIndex >= 0) {
      const ev = events[eventIndex];
      lightSchemaFromEvent(ev.kind);
      if (pulse && ev.branch_id) pulseBranch(ev.branch_id);
    }
  }

  function stopPlay() {
    playing = false;
    $("btn-play").textContent = "▶";
    if (playTimer) clearInterval(playTimer);
    playTimer = null;
  }

  function startPlay() {
    if (!runData) return;
    playing = true;
    $("btn-play").textContent = "❚❚";
    // Longer beats between rounds/events — feels substantial, less jerky
    playTimer = setInterval(() => {
      const max = (runData.events || []).length - 1;
      if (eventIndex >= max) {
        stopPlay();
        return;
      }
      setEventIndex(eventIndex + 1);
    }, 1100);
  }

  $("btn-play").addEventListener("click", () => (playing ? stopPlay() : startPlay()));
  $("btn-reset").addEventListener("click", () => {
    stopPlay();
    setEventIndex(0);
  });
  $("scrub").addEventListener("input", () => {
    stopPlay();
    setEventIndex(Number($("scrub").value));
  });

  /* ---------- Inspector / memo ---------- */
  function selectBranch(id) {
    if (!runData) return;
    selectedId = id;
    const b = runData.branches.find((x) => x.id === id);
    if (!b) return;
    $("inspector").hidden = false;
    $("insp-kicker").textContent = `${b.side_created || "branch"} · round ${b.round ?? "—"}`;
    $("insp-title").textContent = b.label || id;
    $("insp-stats").innerHTML = `
      <div><dt>Branch</dt><dd>${escapeHtml(b.id)}</dd></div>
      <div><dt>Status</dt><dd>${b.alive === false ? "Killed" : "Alive"}</dd></div>
      <div><dt>Goal</dt><dd>${pct(b.goal_coverage)}</dd></div>
      <div><dt>Risk</dt><dd>${pct(b.residual_risk)}</dd></div>
      <div><dt>Spent</dt><dd>${money(b.spent)}</dd></div>
      <div><dt>Uncertainty</dt><dd>${pct(b.uncertainty)}</dd></div>`;
    $("insp-summary").textContent = b.summary || "";
    const kill = $("insp-kill");
    if (b.kill_reason) {
      kill.hidden = false;
      kill.textContent = b.kill_reason;
    } else kill.hidden = true;
    const findings = (runData.findings || []).filter((f) => f.branch_id === id);
    $("insp-findings").innerHTML = findings.length
      ? findings.map((f) => `<li><strong>${escapeHtml(f.side)}</strong>${f.kill ? " · KILL" : ""} — ${escapeHtml(f.claim)}</li>`).join("")
      : "<li class='empty'>None yet</li>";
    const tools = (runData.tool_log || []).filter((t) => t.branch_id === id);
    $("insp-tools").innerHTML = tools.length
      ? tools.map((t) => `<li><strong class="${t.ok ? "" : "kill-line"}">${escapeHtml(t.tool)}</strong> — ${escapeHtml(t.detail)}</li>`).join("")
      : "<li class='empty'>None yet</li>";
    d3.select("#graph").selectAll(".branch-node").classed("selected", (d) => d.data.id === id);
  }

  $("close-insp").addEventListener("click", (e) => {
    e.stopPropagation();
    selectedId = null;
    $("inspector").hidden = true;
  });

  function renderMemo(data) {
    const m = data.memo || {};
    $("memo").innerHTML = `
      <h3 class="memo-title">${escapeHtml(m.title || "Decision memo")}</h3>
      <div class="pick-pill">Recommended ${escapeHtml(m.recommended_branch_id || "?")}</div>
      <p>${escapeHtml(m.prose || "")}</p>
      <p class="kill-line"><strong>Kill shots:</strong> ${escapeHtml(m.kill_shots || "")}</p>
      <p><strong>Open risks:</strong> ${escapeHtml(m.open_risks || "")}</p>
      <p><strong>Dissent:</strong> ${escapeHtml(m.dissent || "")}</p>`;
    $("baseline-out").innerHTML = `<p>${escapeHtml(data.baseline || "No baseline")}</p>`;
    $("hard-rules").innerHTML = (data.hard_rules || [])
      .map((r) => `<li><strong>${escapeHtml(r.rule)}</strong> — ${escapeHtml(r.description)}</li>`)
      .join("") || "<li class='empty'>None</li>";
  }

  function renderTimeline(data) {
    const events = data.events || [];
    $("timeline").innerHTML = events
      .map(
        (ev, i) => `<li data-kind="${escapeHtml(ev.kind)}" data-index="${i}">
        <div class="kind">${escapeHtml(ev.kind)} · ${escapeHtml(ev.branch_id || "")}</div>
        <div>${escapeHtml(ev.message)}</div></li>`
      )
      .join("");
    $("timeline").querySelectorAll("li").forEach((li) => {
      li.addEventListener("click", () => {
        stopPlay();
        setEventIndex(Number(li.dataset.index));
        const ev = events[Number(li.dataset.index)];
        if (ev?.branch_id) selectBranch(ev.branch_id);
      });
    });
  }

  function bindRun(data) {
    runData = data;
    svgReady = false; // rebuild viewport once per run (fixed stage height stays)
    stopPlay();
    selectedId = null;
    $("inspector").hidden = true;
    $("playback").hidden = false;
    const n = (data.events || []).length;
    $("scrub").min = "0";
    $("scrub").max = String(Math.max(0, n - 1));
    $("run-meta").textContent = `${data.title || "Hiring decision"} · ${data.branches?.length || 0} branches · 5-round protocol`;
    renderMemo(data);
    renderTimeline(data);
    setEventIndex(0);
    startPlay();
  }

  $("run").addEventListener("click", async () => {
    const btn = $("run");
    btn.disabled = true;
    $("status").textContent = "Seeding world · Blue & Red walking the graph…";
    stopPlay();
    try {
      const res = await fetch("/api/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          fixture_id: state.fixtureId || "hire",
          proposal: state.proposal || buildProposal(),
          baseline: $("baseline").checked,
          rounds: 5,
        }),
      });
      const data = await res.json();
      if (!res.ok || data.error) throw new Error(data.error || "Run failed");
      bindRun(data);
      $("status").textContent = `Done — recommended ${data.memo?.recommended_branch_id || "?"}. Scrub to replay.`;
    } catch (err) {
      $("status").textContent = `Error: ${err.message}`;
    } finally {
      btn.disabled = false;
    }
  });

  // Boot on landing
  showView("landing");
})();
