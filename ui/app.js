(() => {
  const $ = (id) => document.getElementById(id);
  const SCHEMA_COPY = {
    seed: "CompanyState loads from your answers: cash, burn, MRR, headcount, milestone date.",
    blue: "Blue proposes effect tags (hire_2_eng, …). Never invents dollar figures.",
    red: "Red attacks with claims. Verifiers apply stress arithmetic.",
    tools: "alive_at_milestone is brutal: cash-out must be on/after the milestone.",
    branch: "Each future is a Branch with copied state. Dead = failed hard check.",
    arbiter: "Rank = runway months + milestone hit. Output is a date line — not confidence %.",
  };

  const INTERLOCK = `DECISION: Should we hire two engineers to hit the October launch?

Company: Northline (seed CompanyState).
Tempted move: Hire two full-time engineers now so October 3 still lands.
Counter-move: One engineer + contractor.
Spine: what happens to the cash-out date, and does the milestone land before it?`;

  const state = {
    plan: "",
    answers: {},
    modules: [],
    proposal: "",
    fixtureId: "interlock",
    company: {},
    profile: null,
  };

  let runData = null, eventIndex = -1, playing = false, playTimer = null, selectedId = null, zoomBehavior = null, svgReady = false;

  const escapeHtml = (s) => String(s ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const pretty = (iso) => {
    if (!iso) return "—";
    const d = new Date(String(iso) + "T00:00:00");
    if (Number.isNaN(d.getTime())) return iso;
    return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
  };
  const money = (n) => (n == null ? "—" : `$${Number(n).toLocaleString()}`);

  function showView(name) {
    ["landing", "business", "intake", "app"].forEach((v) => {
      const el = $(`view-${v}`);
      if (el) el.hidden = v !== name;
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  // ---- Business profile (sign in) ----
  function profileAnswers(p) {
    const a = {};
    if (p.cash != null && p.cash !== "") a.cash = Number(p.cash);
    if (p.monthly_burn != null && p.monthly_burn !== "") a.monthly_burn = Number(p.monthly_burn);
    if (p.mrr != null && p.mrr !== "") a.mrr = Number(p.mrr);
    if (p.headcount != null && p.headcount !== "") a.headcount = Number(p.headcount);
    if (p.milestone) a.milestone = p.milestone;
    if (p.milestone_date) a.milestone_date = p.milestone_date;
    return a;
  }

  function setProfile(p) {
    state.profile = p;
    try { localStorage.setItem("splithorizon_profile", JSON.stringify(p)); } catch {}
    const chip = $("signed-in-chip");
    chip.hidden = false;
    chip.textContent = `Signed in: ${p.name} · ${money(p.cash)} cash · ${money(p.monthly_burn)}/mo burn`;
  }

  function restoreProfile() {
    try {
      const raw = localStorage.getItem("splithorizon_profile");
      if (raw) setProfile(JSON.parse(raw));
    } catch {}
  }

  async function loadProfileList() {
    const box = $("profile-list");
    box.innerHTML = "";
    $("profile-divider").hidden = true;
    try {
      const res = await fetch("/api/profiles");
      const profiles = await res.json();
      if (!Array.isArray(profiles) || !profiles.length) return;
      $("profile-divider").hidden = false;
      profiles.forEach((p) => {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "profile-row";
        btn.innerHTML = `<strong>${escapeHtml(p.name)}</strong><span class="mono">${money(p.cash)} cash · ${money(p.monthly_burn)}/mo · milestone ${escapeHtml(p.milestone_date || "—")}</span>`;
        btn.addEventListener("click", () => {
          setProfile(p);
          state.answers = profileAnswers(p);
          showView("intake");
          resetIntakeKeepProfile();
        });
        box.appendChild(btn);
      });
    } catch {}
  }

  function resetIntakeKeepProfile() {
    state.plan = "";
    state.modules = [];
    state.proposal = "";
    state.company = {};
    $("intake-plan").value = "";
    $("intake-thread").innerHTML = "";
    $("intake-current").innerHTML = "";
    $("intake-plan-block").hidden = false;
    $("intake-q-block").hidden = true;
    $("module-pills").hidden = true;
    $("intake-kicker").textContent = "Step 1 · Your plan";
    $("intake-title").textContent = "What’s the plan of action?";
    $("intake-help").textContent = state.profile
      ? `Using ${state.profile.name}'s saved numbers — we'll only ask what's missing.`
      : "One sentence is enough. We’ll figure out which modules apply.";
    $("intake-status").textContent = "";
  }

  $("cta-business").addEventListener("click", () => {
    showView("business");
    loadProfileList();
  });
  $("business-back").addEventListener("click", () => showView("landing"));

  $("business-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const profile = {
      name: $("biz-name").value.trim(),
      cash: Number($("biz-cash").value),
      monthly_burn: Number($("biz-burn").value),
      mrr: $("biz-mrr").value ? Number($("biz-mrr").value) : null,
      headcount: $("biz-headcount").value ? Number($("biz-headcount").value) : null,
      milestone: $("biz-milestone").value.trim(),
      milestone_date: $("biz-milestone-date").value,
    };
    if (!profile.name) {
      $("business-status").textContent = "Business name is required.";
      return;
    }
    $("business-status").textContent = "Saving…";
    try {
      const res = await fetch("/api/profiles", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(profile),
      });
      const data = await res.json();
      if (!res.ok || data.error) throw new Error(data.error || "Save failed");
      setProfile(profile);
      state.answers = profileAnswers(profile);
      $("business-status").textContent = "";
      showView("intake");
      resetIntakeKeepProfile();
    } catch (err) {
      $("business-status").textContent = `Error: ${err.message || err}`;
    }
  });

  function resetIntake() {
    state.plan = "";
    state.answers = {};
    state.modules = [];
    state.proposal = "";
    state.company = {};
    $("intake-plan").value = "";
    $("intake-thread").innerHTML = "";
    $("intake-current").innerHTML = "";
    $("intake-plan-block").hidden = false;
    $("intake-q-block").hidden = true;
    $("module-pills").hidden = true;
    $("module-pills").innerHTML = "";
    $("intake-kicker").textContent = "Step 1 · Your plan";
    $("intake-title").textContent = "What’s the plan of action?";
    $("intake-help").textContent = "One sentence is enough. We’ll figure out which modules apply.";
    $("intake-status").textContent = "";
  }

  function goWarRoom() {
    $("decision-summary").textContent = state.proposal;
    const c = state.company || {};
    const cash = c.cash != null ? money(c.cash) : "seed";
    const burn = c.monthly_burn != null ? money(c.monthly_burn) + "/mo" : "seed";
    const md = c.milestone_date || "seed milestone";
    $("company-chip").textContent = `${c.name || "Your company"} · ${cash} cash · ${burn} burn · milestone ${md}`;
    $("modules-chip").innerHTML = (state.modules || [])
      .map((m) => `<span>${escapeHtml(m)}</span>`)
      .join("");
    showView("app");
    initSchemaRail();
    renderTypeChips();
  }

  $("cta-start").addEventListener("click", () => {
    resetIntake();
    if (state.profile) state.answers = profileAnswers(state.profile);
    resetIntakeKeepProfile();
    showView("intake");
  });

  $("cta-demo").addEventListener("click", () => {
    state.plan = "Hire two engineers to hit the October launch";
    state.answers = {};
    state.modules = ["hire", "launch"];
    state.fixtureId = "interlock";
    state.proposal = INTERLOCK;
    state.company = {};
    goWarRoom();
  });

  $("intake-back").addEventListener("click", () => showView("landing"));
  $("btn-new").addEventListener("click", () => {
    stopPlay();
    resetIntake();
    showView("landing");
  });

  async function postIntake() {
    const res = await fetch("/api/intake", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ plan: state.plan, answers: state.answers }),
    });
    const data = await res.json();
    if (!res.ok || data.error) throw new Error(data.error || "Intake failed");
    return data;
  }

  function showModules(mods) {
    const el = $("module-pills");
    el.hidden = false;
    el.innerHTML = (mods || []).map((m) => `<span>${escapeHtml(m)}</span>`).join("");
  }

  function pushThread(who, text) {
    const div = document.createElement("div");
    div.className = `bubble ${who}`;
    div.textContent = text;
    $("intake-thread").appendChild(div);
    div.scrollIntoView({ block: "nearest" });
  }

  function renderQuestion(q) {
    $("intake-kicker").textContent = "Intake · one question at a time";
    $("intake-title").textContent = q.prompt;
    $("intake-help").textContent = "Answer this so the survival sim can run real arithmetic.";
    const box = $("intake-current");
    if (q.type === "choice") {
      box.innerHTML = `<div class="choice-grid" id="q-choices"></div><button type="button" class="run-btn" id="q-submit" disabled>Continue</button>`;
      let picked = null;
      (q.choices || []).forEach((c) => {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "choice";
        btn.textContent = c.label;
        btn.addEventListener("click", () => {
          picked = c.id;
          box.querySelectorAll(".choice").forEach((b) => b.classList.toggle("on", b === btn));
          $("q-submit").disabled = false;
        });
        $("q-choices").appendChild(btn);
      });
      $("q-submit").addEventListener("click", () => answerAndAdvance(q.field, picked));
    } else {
      const inputType = q.type === "number" ? "number" : q.type === "date" ? "date" : "text";
      box.innerHTML = `
        <label for="q-input">${escapeHtml(q.prompt)}</label>
        <input id="q-input" type="${inputType}" placeholder="${escapeHtml(q.placeholder || "")}" />
        <button type="button" class="run-btn" id="q-submit">Continue</button>`;
      $("q-submit").addEventListener("click", () => {
        const v = $("q-input").value.trim();
        if (!v) return;
        answerAndAdvance(q.field, q.type === "number" ? Number(v) : v);
      });
      $("q-input").addEventListener("keydown", (e) => {
        if (e.key === "Enter") $("q-submit").click();
      });
      setTimeout(() => $("q-input").focus(), 50);
    }
  }

  async function answerAndAdvance(field, value) {
    state.answers[field] = value;
    pushThread("you", String(value));
    $("intake-current").innerHTML = "";
    $("intake-status").textContent = "Updating simulation inputs…";
    try {
      const data = await postIntake();
      applyIntake(data);
    } catch (err) {
      const msg = String(err.message || err);
      $("intake-status").textContent =
        msg.includes("Failed to fetch") || msg.includes("NetworkError")
          ? "Can't reach the server on :8765 — restart: JAC_HOME=/tmp/jac_home python3 serve.py"
          : `Error: ${msg}`;
    }
  }

  function applyIntake(data) {
    state.modules = data.modules || [];
    state.fixtureId = data.fixture_id || "interlock";
    state.company = data.company || {};
    if (state.profile?.name && !state.company.name) state.company.name = state.profile.name;
    showModules(state.modules);
    $("intake-status").textContent = data.spine || "";
    if (data.ready) {
      state.proposal = data.proposal;
      goWarRoom();
      return;
    }
    const q = (data.questions || [])[0];
    if (!q) {
      state.proposal = data.proposal || state.plan;
      goWarRoom();
      return;
    }
    pushThread("sys", q.prompt);
    renderQuestion(q);
  }

  $("intake-plan-next").addEventListener("click", async () => {
    const plan = $("intake-plan").value.trim();
    if (!plan) {
      $("intake-status").textContent = "Type a plan of action first.";
      return;
    }
    state.plan = plan;
    state.answers = state.profile ? profileAnswers(state.profile) : {};
    $("intake-plan-block").hidden = true;
    $("intake-q-block").hidden = false;
    $("intake-thread").innerHTML = "";
    pushThread("you", plan);
    $("intake-status").textContent = "Classifying modules…";
    try {
      const data = await postIntake();
      applyIntake(data);
    } catch (err) {
      const msg = String(err.message || err);
      $("intake-status").textContent =
        msg.includes("Failed to fetch") || msg.includes("NetworkError")
          ? "Can't reach the server on :8765 — start it with: JAC_HOME=/tmp/jac_home python3 serve.py"
          : `Error: ${msg}`;
      $("intake-plan-block").hidden = false;
      $("intake-q-block").hidden = true;
    }
  });

  function initSchemaRail() {
    const explain = $("schema-explain");
    document.querySelectorAll(".schema-node").forEach((btn) => {
      btn.addEventListener("click", () => {
        document.querySelectorAll(".schema-node").forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
        explain.textContent = SCHEMA_COPY[btn.dataset.schema] || "";
      });
    });
  }
  function lightSchemaFromEvent(kind) {
    const map = { seed: "seed", blue: "blue", red: "red", tool: "tools", arbiter: "arbiter" };
    const key = map[kind];
    document.querySelectorAll(".schema-node").forEach((b) => b.classList.toggle("lit", key && b.dataset.schema === key));
    if (key && SCHEMA_COPY[key]) $("schema-explain").textContent = SCHEMA_COPY[key];
  }
  function renderTypeChips() {
    const root = $("schema-graph"), detail = $("schema-detail"), schema = window.SPLIT_SCHEMA;
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
        detail.innerHTML = `<strong>${escapeHtml(item.id)}</strong><p>${escapeHtml(item.blurb || "")}</p>`;
      });
      root.appendChild(btn);
    };
    (schema.nodes || []).forEach((n) => add(n, "node"));
    (schema.edges || []).forEach((e) => add(e, "edge"));
    (schema.walkers || []).forEach((w) => add(w, "walker"));
  }

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
    const width = stage.clientWidth || 700, height = stage.clientHeight || 480;
    svg.attr("viewBox", `0 0 ${width} ${height}`).attr("width", "100%").attr("height", "100%");
    if (!svgReady) {
      svg.selectAll("*").remove();
      const g = svg.append("g").attr("class", "viewport");
      zoomBehavior = d3.zoom().scaleExtent([0.5, 2.2]).on("zoom", (event) => g.attr("transform", event.transform));
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
    return { width, height, g: svg.select("g.viewport") };
  }
  function truncate(s, n = 22) {
    const t = String(s || "");
    return t.length > n ? `${t.slice(0, n - 1)}…` : t;
  }

  function renderGraph(data, allowedIds) {
    if (typeof d3 === "undefined") return;
    const { width, height, g } = ensureSvg();
    const rootData = buildHierarchy(data, allowedIds);
    const linksG = g.select("g.links"), nodesG = g.select("g.nodes");
    if (!rootData) {
      linksG.selectAll("*").remove();
      nodesG.selectAll("*").remove();
      return;
    }
    const root = d3.hierarchy(rootData);
    d3.tree().size([height - 70, width - 140])(root);
    root.each((d) => {
      const x = d.y + 70, y = d.x + 35;
      d.x = x;
      d.y = y;
    });
    const recommended = data.memo?.recommended_branch_id;
    const linkPath = (d) => {
      const s = d.source, t = d.target, mid = (s.x + t.x) / 2;
      return `M${s.x},${s.y}C${mid},${s.y} ${mid},${t.y} ${t.x},${t.y}`;
    };
    linksG
      .selectAll("path.branch-link")
      .data(root.links(), (d) => d.target.data.id)
      .join(
        (enter) =>
          enter
            .append("path")
            .attr("class", (d) => `branch-link ${d.target.data.alive === false ? "dead" : d.target.data.side_created || "seed"}`)
            .attr("d", linkPath)
            .attr("stroke-opacity", 0)
            .call((s) => s.transition().duration(450).attr("stroke-opacity", null)),
        (update) =>
          update
            .attr("class", (d) => `branch-link ${d.target.data.alive === false ? "dead" : d.target.data.side_created || "seed"}`)
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
    nodesEnter.append("circle").attr("class", "node-core").attr("r", 10).attr("fill", (d) => colorFor(d.data.side_created, d.data.alive)).attr("stroke", "#fff").attr("stroke-width", 1.5);
    nodesEnter.append("text").attr("class", "node-label").attr("text-anchor", "middle").attr("y", -14);
    nodesEnter.append("text").attr("class", "node-sub").attr("text-anchor", "middle").attr("y", 24);
    nodesEnter.transition().duration(400).style("opacity", 1);
    const merged = nodesEnter.merge(nodes);
    merged.transition().duration(350).attr("transform", (d) => `translate(${d.x},${d.y})`);
    merged
      .select(".node-core")
      .attr("r", (d) => (d.data.id === recommended ? 13 : 10))
      .attr("fill", (d) => colorFor(d.data.side_created, d.data.alive))
      .attr("stroke", (d) => (d.data.id === recommended ? "#c9a227" : "#fff"))
      .attr("stroke-width", (d) => (d.data.id === recommended ? 3 : 1.5));
    merged.select(".node-label").text((d) => `${d.data.id}${d.data.alive === false ? " ✕" : ""}`);
    merged.select(".node-sub").text((d) => truncate(d.data.cash_out_date ? pretty(d.data.cash_out_date) : d.data.move || d.data.label, 24));
    merged.classed("selected", (d) => d.data.id === selectedId);
    nodes.exit().transition().duration(200).style("opacity", 0).remove();
  }

  function pulseBranch(id) {
    const sel = d3.select("#graph").selectAll(".branch-node").filter((d) => d.data.id === id).select(".walker-pulse");
    sel.classed("on", false);
    requestAnimationFrame(() => sel.classed("on", true));
  }
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

  function selectBranch(id) {
    if (!runData) return;
    selectedId = id;
    const b = runData.branches.find((x) => x.id === id);
    if (!b) return;
    $("inspector").hidden = false;
    $("insp-kicker").textContent = `${b.side_created || "branch"} · round ${b.round ?? "—"}`;
    $("insp-title").textContent = b.label || id;
    $("insp-stats").innerHTML = `
      <div><dt>Status</dt><dd>${b.alive === false ? "Killed" : "Alive"}</dd></div>
      <div><dt>Cash-out</dt><dd>${escapeHtml(pretty(b.cash_out_date))}</dd></div>
      <div><dt>Milestone</dt><dd>${escapeHtml(pretty(b.milestone_date))}</dd></div>
      <div><dt>Runway</dt><dd>${b.runway_months != null ? Number(b.runway_months).toFixed(2) + " mo" : "—"}</dd></div>
      <div><dt>Milestone hit</dt><dd>${b.milestone_hit ? "yes" : "no"}</dd></div>
      <div><dt>Cost Δ</dt><dd>${money(b.cost_delta)}</dd></div>`;
    $("insp-summary").textContent = b.summary || "";
    const kill = $("insp-kill");
    if (b.kill_reason) {
      kill.hidden = false;
      kill.textContent = b.kill_reason;
    } else kill.hidden = true;
    const tools = (runData.evidence_log || runData.tool_log || []).filter((t) => t.branch_id === id);
    $("insp-tools").innerHTML = tools.length
      ? tools
          .map(
            (t) =>
              `<li><strong class="${(t.passed ?? t.ok) ? "" : "kill-line"}">${escapeHtml(t.check || t.tool)}</strong> — ${escapeHtml(t.detail || t.value || "")}</li>`
          )
          .join("")
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
      <p class="date-line mono">${escapeHtml(m.date_line || "")}</p>
      <p>${escapeHtml(m.prose || "")}</p>
      <p class="kill-line"><strong>Kill shots:</strong> ${escapeHtml(m.kill_shots || "")}</p>
      <p><strong>Open risks:</strong> ${escapeHtml(m.open_risks || "")}</p>
      <p><strong>Dissent:</strong> ${escapeHtml(m.dissent || "")}</p>`;
    $("baseline-out").innerHTML = `<p>${escapeHtml(data.baseline || "No baseline")}</p>`;
    $("hard-rules").innerHTML =
      (data.verifier_registry || [])
        .map((v) => `<li><strong>${escapeHtml(v.name)}</strong> · ${escapeHtml(v.module)} — ${escapeHtml(v.blurb)}</li>`)
        .join("") || "<li class='empty'>None</li>";
    $("reco-banner").hidden = false;
    $("reco-title").textContent = m.date_line || m.title || "Survivor";
    $("reco-body").textContent = m.prose || "";
    renderPlan(m);
  }

  function renderPlan(m) {
    const steps = m.action_plan || [];
    const block = $("plan-block");
    if (!steps.length && !m.analysis) {
      block.hidden = true;
      return;
    }
    block.hidden = false;
    $("plan-analysis").textContent = m.analysis || "";
    const watch = $("plan-watch");
    if (m.watch_for) {
      watch.hidden = false;
      watch.textContent = `Watch for: ${m.watch_for}`;
    } else watch.hidden = true;
    $("plan-steps").innerHTML = steps
      .map(
        (s) =>
          `<li class="plan-step ${s.when === "Avoid" ? "avoid" : ""}"><span class="plan-when mono">${escapeHtml(s.when)}</span><div><strong>${escapeHtml(s.title)}</strong><p>${escapeHtml(s.detail)}</p></div></li>`
      )
      .join("");
  }

  function renderTimeline(data) {
    const events = data.events || [];
    $("timeline").innerHTML = events
      .map(
        (ev, i) =>
          `<li data-kind="${escapeHtml(ev.kind)}" data-index="${i}"><div class="kind">${escapeHtml(ev.kind)} · ${escapeHtml(ev.branch_id || "")}</div><div>${escapeHtml(ev.message)}</div></li>`
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
    svgReady = false;
    stopPlay();
    selectedId = null;
    $("inspector").hidden = true;
    $("playback").hidden = false;
    const n = (data.events || []).length;
    $("scrub").min = "0";
    $("scrub").max = String(Math.max(0, n - 1));
    $("run-meta").textContent = `${data.title || "Decision"} · ${data.branches?.length || 0} branches · survival scoring`;
    if (data.company) {
      const c = data.company;
      $("company-chip").textContent = `${c.name || "Company"} · $${Number(c.cash).toLocaleString()} cash · $${Number(c.monthly_burn).toLocaleString()}/mo burn · milestone ${c.milestone_date}`;
    }
    renderMemo(data);
    renderTimeline(data);
    setEventIndex(0);
    startPlay();
  }

  $("run").addEventListener("click", async () => {
    const btn = $("run");
    btn.disabled = true;
    $("status").textContent = "Seeding CompanyState · Blue/Red · verifiers…";
    stopPlay();
    try {
      const res = await fetch("/api/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          fixture_id: state.fixtureId || "interlock",
          proposal: state.proposal,
          company: state.company || {},
          baseline: $("baseline").checked,
          rounds: 3,
        }),
      });
      const data = await res.json();
      if (!res.ok || data.error) throw new Error(data.error || "Run failed");
      bindRun(data);
      $("status").textContent = data.memo?.date_line || `Done — ${data.memo?.recommended_branch_id || "?"}`;
    } catch (err) {
      const msg = String(err.message || err);
      $("status").textContent =
        msg.includes("Failed to fetch") || msg.includes("NetworkError")
          ? "Can't reach the server on :8765 — restart: JAC_HOME=/tmp/jac_home python3 serve.py"
          : `Error: ${msg}`;
    } finally {
      btn.disabled = false;
    }
  });

  restoreProfile();
  showView("landing");
})();
