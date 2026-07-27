(() => {
  const $ = (id) => document.getElementById(id);
  const SCHEMA_COPY = {
    seed: "CompanyState loads from your answers: cash, burn, MRR, headcount, milestone date.",
    blue: "Blue proposes a move for YOUR plan (custom effects). Never invents dollar figures — verifiers compute.",
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

  const CONSULT_AREAS = [
    { id: "finance", label: "Finance", blurb: "Raise, burn, pricing, MRR, runway", agents: "Finance Blue / Red" },
    { id: "management", label: "Management", blurb: "Hiring, headcount, contractors, infra", agents: "Management Blue / Red" },
    { id: "launch", label: "Launch", blurb: "Ship dates, staged release, go-live", agents: "Launch Blue / Red" },
    { id: "publicity", label: "Publicity", blurb: "Ads, campaigns, influencers, GTM", agents: "Publicity Blue / Red" },
  ];
  const AREA_LABEL = Object.fromEntries(CONSULT_AREAS.map((a) => [a.id, a.label]));

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
  let activeChatId = null;

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
  function setProfile(p) {
    if (!p) return;
    state.profile = p;
    try { localStorage.setItem("splithorizon_profile", JSON.stringify(p)); } catch {}
    const chip = $("signed-in-chip");
    if (chip) {
      chip.hidden = false;
      const site = p.website ? ` · ${String(p.website).replace(/^https?:\/\//, "").split("/")[0]}` : "";
      const mode = p.quick ? " · quick" : "";
      const nChats = Array.isArray(p.chats) ? p.chats.length : 0;
      const hist = nChats ? ` · ${nChats} saved decision${nChats === 1 ? "" : "s"}` : "";
      chip.textContent = `Signed in: ${p.name}${site} · ${money(p.cash)} cash · ${money(p.monthly_burn)}/mo burn${mode}${hist}`;
    }
    const qcta = $("cta-quick");
    if (qcta) qcta.hidden = !p;
    const actions = $("biz-selected-actions");
    if (actions) actions.hidden = !p;
  }

  function clearProfile() {
    state.profile = null;
    activeChatId = null;
    try { localStorage.removeItem("splithorizon_profile"); } catch {}
    const chip = $("signed-in-chip");
    if (chip) {
      chip.hidden = true;
      chip.textContent = "";
    }
    const qcta = $("cta-quick");
    if (qcta) qcta.hidden = true;
    const actions = $("biz-selected-actions");
    if (actions) actions.hidden = true;
  }

  async function ensureProfileSynced() {
    // localStorage profiles from before IDs existed can't save chats — refresh from server.
    let local = state.profile;
    if (!local) {
      try {
        const raw = localStorage.getItem("splithorizon_profile");
        if (raw) local = JSON.parse(raw);
      } catch {}
    }
    if (!local || !local.name) return null;
    try {
      const res = await fetch("/api/profiles");
      const profiles = await res.json();
      if (!Array.isArray(profiles)) return local;
      let match = null;
      if (local.id) match = profiles.find((p) => p.id === local.id);
      if (!match) {
        match = profiles.find((p) => (p.name || "").toLowerCase() === (local.name || "").toLowerCase());
      }
      if (match) {
        setProfile(match);
        return match;
      }
      // Local-only → persist so it gets an id
      const save = await fetch("/api/profiles", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(local),
      });
      const data = await save.json();
      if (save.ok && data.profile) {
        setProfile(data.profile);
        return data.profile;
      }
    } catch {}
    if (local) setProfile(local);
    return local;
  }

  function restoreProfile() {
    try {
      const raw = localStorage.getItem("splithorizon_profile");
      if (raw) setProfile(JSON.parse(raw));
    } catch {}
    ensureProfileSynced().catch(() => {});
  }

  function priorHistoryText(p) {
    const chats = (p && p.chats) || [];
    const decided = chats.filter((c) => c.outcome && c.outcome.went_through !== null && c.outcome.went_through !== undefined);
    if (!decided.length) return "";
    return decided.slice(0, 8).map((c) => {
      const verb = c.outcome.went_through ? "DID go through" : "DID NOT go through";
      const rec = c.recommended || c.memo_title || "—";
      const note = c.outcome.note ? ` — note: ${c.outcome.note}` : "";
      return `- ${verb} with «${c.plan || "decision"}» (sim recommended: ${rec})${note}`;
    }).join("\n");
  }

  function withPriorHistory(proposal) {
    const block = priorHistoryText(state.profile);
    if (!block) return proposal || "";
    if ((proposal || "").includes("PRIOR DECISIONS")) return proposal;
    return `${proposal || ""}\n\nPRIOR DECISIONS (founder follow-through):\n${block}\nWeight these outcomes in the next forks.`;
  }

  function clearBusinessForm() {
    ["biz-name","biz-website","biz-describe","biz-cash","biz-burn","biz-mrr","biz-growth","biz-headcount","biz-milestone","biz-milestone-date"].forEach((id) => {
      if ($(id)) $(id).value = "";
    });
    if ($("biz-quick")) $("biz-quick").checked = false;
    if ($("biz-scan-preview")) { $("biz-scan-preview").hidden = true; $("biz-scan-preview").innerHTML = ""; }
    renderBizChats(null);
  }

  function fillBusinessForm(p) {
    if (!p) return;
    $("biz-name").value = p.name || "";
    $("biz-website").value = p.website || "";
    $("biz-describe").value = p.describe || "";
    $("biz-cash").value = p.cash ?? "";
    $("biz-burn").value = p.monthly_burn ?? "";
    $("biz-mrr").value = p.mrr ?? "";
    $("biz-growth").value = p.growth ?? "";
    $("biz-headcount").value = p.headcount ?? "";
    $("biz-milestone").value = p.milestone || "";
    $("biz-milestone-date").value = p.milestone_date || "";
    $("biz-quick").checked = !!p.quick;
    const prev = $("biz-scan-preview");
    if (p.summary) {
      prev.hidden = false;
      prev.innerHTML = `<strong>Remembered site intel</strong><p>${escapeHtml(p.summary)}</p>${p.product_guess ? `<em>${escapeHtml(p.product_guess)}</em>` : ""}`;
    } else {
      prev.hidden = true;
      prev.innerHTML = "";
    }
    renderBizChats(p);
    const actions = $("biz-selected-actions");
    if (actions) actions.hidden = false;
  }

  function renderBizChats(p) {
    const wrap = $("biz-chats");
    const list = $("biz-chat-list");
    if (!wrap || !list) return;
    const chats = (p && p.chats) || [];
    if (!chats.length) {
      wrap.hidden = true;
      list.innerHTML = "";
      return;
    }
    wrap.hidden = false;
    list.innerHTML = "";
    chats.slice(0, 12).forEach((c) => {
      const o = c.outcome || {};
      const pending = o.went_through === null || o.went_through === undefined;
      const card = document.createElement("article");
      card.className = "biz-chat-card";
      let tag = `<span class="outcome-tag pending">Pending follow-through</span>`;
      if (o.went_through === true) tag = `<span class="outcome-tag yes">Went through</span>`;
      else if (o.went_through === false) tag = `<span class="outcome-tag no">Did not go through</span>`;
      const note = o.note ? `<p class="biz-chat-note">${escapeHtml(o.note)}</p>` : "";
      card.innerHTML = `
        <strong>${escapeHtml(c.plan || "Decision")}</strong>
        <p class="mono">${escapeHtml(c.recommended || c.date_line || "—")} · ${escapeHtml((c.created_at || "").slice(0, 10) || "—")}</p>
        ${tag}${note}
        <div class="biz-chat-follow" data-chat-id="${escapeHtml(c.id || "")}"></div>`;
      const follow = card.querySelector(".biz-chat-follow");
      if (pending && c.id) {
        const noteIn = document.createElement("input");
        noteIn.type = "text";
        noteIn.className = "biz-chat-note-input";
        noteIn.placeholder = "Optional note";
        const yes = document.createElement("button");
        yes.type = "button";
        yes.className = "run-btn biz-chat-yes";
        yes.textContent = "Yes, I did";
        const no = document.createElement("button");
        no.type = "button";
        no.className = "ghost-btn biz-chat-no";
        no.textContent = "No, I didn’t";
        yes.addEventListener("click", async () => {
          yes.disabled = true;
          no.disabled = true;
          await submitOutcome(true, c.id, noteIn.value.trim());
          renderBizChats(state.profile);
        });
        no.addEventListener("click", async () => {
          yes.disabled = true;
          no.disabled = true;
          await submitOutcome(false, c.id, noteIn.value.trim());
          renderBizChats(state.profile);
        });
        follow.appendChild(noteIn);
        follow.appendChild(yes);
        follow.appendChild(no);
      } else if (!pending) {
        follow.innerHTML = `<button type="button" class="text-btn biz-chat-reset">Change answer</button>`;
        follow.querySelector(".biz-chat-reset")?.addEventListener("click", async () => {
          await submitOutcome(null, c.id, "");
          renderBizChats(state.profile);
        });
      }
      list.appendChild(card);
    });
  }

  async function deleteBusiness(p) {
    if (!p || (!p.id && !p.name)) throw new Error("No business selected");
    const r = await fetch("/api/profiles/delete", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: p.id || "", name: p.name || "" }),
    });
    const data = await r.json();
    if (!r.ok || data.error) throw new Error(data.error || "Delete failed");
    const same =
      state.profile &&
      ((p.id && state.profile.id === p.id) ||
        (state.profile.name || "").toLowerCase() === (p.name || "").toLowerCase());
    if (same) {
      clearProfile();
      clearBusinessForm();
    }
    return data;
  }

  async function loadProfileList() {
    const box = $("profile-list");
    box.innerHTML = "";
    $("profile-divider").hidden = true;
    try {
      const res = await fetch("/api/profiles");
      const profiles = await res.json();
      if (!Array.isArray(profiles) || !profiles.length) {
        if (state.profile) renderBizChats(state.profile);
        return;
      }
      $("profile-divider").hidden = false;
      profiles.forEach((p) => {
        const wrap = document.createElement("div");
        wrap.className = "profile-row-wrap";
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "profile-row";
        if (state.profile && ((p.id && state.profile.id === p.id) || state.profile.name === p.name)) {
          btn.classList.add("on");
        }
        const host = p.website ? String(p.website).replace(/^https?:\/\//, "").split("/")[0] : "";
        const n = Array.isArray(p.chats) ? p.chats.length : 0;
        btn.innerHTML = `<strong>${escapeHtml(p.name)}</strong><span class="mono">${money(p.cash)} cash · ${money(p.monthly_burn)}/mo · ${escapeHtml(host || p.milestone_date || "—")}${p.quick ? " · quick" : ""}${n ? ` · ${n} chats` : ""}</span>`;
        btn.addEventListener("click", () => {
          setProfile(p);
          fillBusinessForm(p);
          $("business-status").textContent = `Selected ${p.name}. Review saved decisions below, or continue.`;
          loadProfileList();
        });
        const del = document.createElement("button");
        del.type = "button";
        del.className = "profile-delete";
        del.textContent = "Delete";
        del.title = `Delete ${p.name}`;
        del.addEventListener("click", async (e) => {
          e.stopPropagation();
          if (!confirm(`Delete business «${p.name}» and all saved decisions?`)) return;
          try {
            await deleteBusiness(p);
            $("business-status").textContent = `Deleted ${p.name}.`;
            loadProfileList();
          } catch (err) {
            $("business-status").textContent = `Delete error: ${err.message || err}`;
          }
        });
        wrap.appendChild(btn);
        wrap.appendChild(del);
        box.appendChild(wrap);
      });
      if (state.profile) {
        const fresh = profiles.find((x) => x.id === state.profile.id) || profiles.find((x) => x.name === state.profile.name);
        if (fresh) {
          setProfile(fresh);
          renderBizChats(fresh);
        }
      }
    } catch (err) {
      $("business-status").textContent = `Could not load businesses: ${err.message || err}`;
    }
  }

  function collectBusinessForm(forceQuick = false) {
    const scan = state._lastScan || {};
    return {
      id: (state.profile && state.profile.id) || undefined,
      name: $("biz-name").value.trim(),
      website: $("biz-website").value.trim(),
      describe: $("biz-describe").value.trim(),
      summary: scan.summary || (state.profile && state.profile.summary) || "",
      product_guess: scan.product_guess || (state.profile && state.profile.product_guess) || "",
      scan_title: scan.title || (state.profile && state.profile.scan_title) || "",
      scanned_at: scan.scanned_at || (state.profile && state.profile.scanned_at) || "",
      cash: Number($("biz-cash").value),
      monthly_burn: Number($("biz-burn").value),
      mrr: $("biz-mrr").value ? Number($("biz-mrr").value) : null,
      growth: $("biz-growth").value ? Number($("biz-growth").value) : null,
      headcount: $("biz-headcount").value ? Number($("biz-headcount").value) : null,
      milestone: $("biz-milestone").value.trim(),
      milestone_date: $("biz-milestone-date").value,
      quick: forceQuick || $("biz-quick").checked,
    };
  }

  async function saveBusinessProfile(forceQuick = false) {
    const profile = collectBusinessForm(forceQuick);
    if (!profile.name) {
      $("business-status").textContent = "Business name is required.";
      return null;
    }
    if (!(profile.cash >= 0) || !(profile.monthly_burn >= 0)) {
      $("business-status").textContent = "Cash and burn are required.";
      return null;
    }
    $("business-status").textContent = "Saving…";
    const res = await fetch("/api/profiles", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(profile),
    });
    const data = await res.json();
    if (!res.ok || data.error) throw new Error(data.error || "Save failed");
    const saved = data.profile || profile;
    setProfile(saved);
    return saved;
  }

  $("cta-business").addEventListener("click", () => {
    showView("business");
    loadProfileList();
    if (state.profile) fillBusinessForm(state.profile);
  });
  $("business-back").addEventListener("click", () => showView("landing"));

  $("biz-use")?.addEventListener("click", () => {
    if (!state.profile) {
      $("business-status").textContent = "Select or save a business first.";
      return;
    }
    state.answers = {};
    showView("intake");
    resetIntakeKeepProfile();
  });

  $("biz-delete-selected")?.addEventListener("click", async () => {
    if (!state.profile) {
      $("business-status").textContent = "Select a business to delete.";
      return;
    }
    const name = state.profile.name;
    if (!confirm(`Delete business «${name}» and all saved decisions?`)) return;
    try {
      await deleteBusiness(state.profile);
      $("business-status").textContent = `Deleted ${name}.`;
      loadProfileList();
    } catch (err) {
      $("business-status").textContent = `Delete error: ${err.message || err}`;
    }
  });

  $("biz-scan").addEventListener("click", async () => {
    const url = $("biz-website").value.trim();
    if (!url) {
      $("business-status").textContent = "Paste a website URL first.";
      return;
    }
    $("business-status").textContent = "Scanning website…";
    const prev = $("biz-scan-preview");
    prev.hidden = false;
    prev.textContent = "Fetching title, meta, and product blurb…";
    try {
      const res = await fetch("/api/scan-site", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url }),
      });
      const data = await res.json();
      if (!res.ok || data.error) throw new Error(data.error || "Scan failed");
      state._lastScan = data;
      $("biz-website").value = data.url || url;
      if (!$("biz-name").value.trim() && (data.site_name || data.title)) {
        $("biz-name").value = (data.site_name || data.title).split(/[|\-–—]/)[0].trim().slice(0, 48);
      }
      if (data.describe) $("biz-describe").value = data.describe;
      prev.innerHTML = `<strong>Scanned · ${escapeHtml(data.title || data.url)}</strong><p>${escapeHtml(data.summary || "")}</p><em>${escapeHtml(data.product_guess || "")}</em>`;
      $("business-status").textContent = "Site intel loaded — edit anything before saving.";
    } catch (err) {
      prev.hidden = true;
      $("business-status").textContent = `Scan error: ${err.message || err}`;
    }
  });

  $("business-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    try {
      const profile = await saveBusinessProfile(false);
      if (!profile) return;
      state.answers = {};
      $("business-status").textContent = "";
      showView("intake");
      resetIntakeKeepProfile();
    } catch (err) {
      $("business-status").textContent = `Error: ${err.message || err}`;
    }
  });

  $("biz-save-quick").addEventListener("click", async () => {
    try {
      const profile = await saveBusinessProfile(true);
      if (!profile) return;
      $("business-status").textContent = "";
      showView("intake");
      resetIntakeKeepProfile();
      if ($("intake-quick")) $("intake-quick").checked = true;
    } catch (err) {
      $("business-status").textContent = `Error: ${err.message || err}`;
    }
  });

  $("cta-quick")?.addEventListener("click", () => {
    if (!state.profile) {
      showView("business");
      loadProfileList();
      return;
    }
    resetIntake();
    resetIntakeKeepProfile();
    if ($("intake-quick")) $("intake-quick").checked = true;
    showView("intake");
  });

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
    $("intake-kicker").textContent = "Step 1 · Consult desk";
    $("intake-title").textContent = "What are you consulting on?";
    const wrap = $("intake-quick-wrap");
    const qbox = $("intake-quick");
    if (wrap && qbox) {
      wrap.hidden = !state.profile;
      qbox.checked = !!(state.profile && state.profile.quick);
    }
    $("intake-help").textContent = state.profile
      ? `Signed in as ${state.profile.name}${state.profile.website ? " · " + state.profile.website.replace(/^https?:\/\//, "").split("/")[0] : ""} — desks use your saved business intel.`
      : "Pick one or more desks. Each desk runs its own Blue/Red agent pair on your plan.";
    $("intake-status").textContent = "";
    renderAreaGrid();
  }

  function profileAsAnswers(p) {
    if (!p) return {};
    const a = {
      biz_name: p.name || "",
      describe: p.describe || p.summary || "",
      website: p.website || "",
      summary: p.summary || "",
      cash: Number(p.cash),
      monthly_burn: Number(p.monthly_burn),
      mrr: p.mrr != null && p.mrr !== "" ? Number(p.mrr) : 0,
      growth: p.growth != null && p.growth !== "" ? Number(p.growth) : 0,
      headcount: p.headcount != null && p.headcount !== "" ? Number(p.headcount) : 1,
      milestone: p.milestone || "Milestone",
      milestone_date: p.milestone_date || "",
    };
    return a;
  }

  function defaultShapesForModules(mods) {
    const a = {};
    if ((mods || []).includes("finance")) a.finance_shape = "fund";
    if ((mods || []).includes("management")) a.management_shape = "full";
    if ((mods || []).includes("launch")) a.launch_shape = "staged";
    if ((mods || []).includes("publicity")) a.publicity_shape = "paid";
    return a;
  }

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
    $("intake-kicker").textContent = "Step 1 · Consult desk";
    $("intake-title").textContent = "What are you consulting on?";
    $("intake-help").textContent = "Pick one or more desks. Each desk runs its own Blue/Red agent pair on your plan.";
    $("intake-status").textContent = "";
    renderAreaGrid();
  }

  function goWarRoom() {
    $("decision-summary").textContent = state.proposal;
    const c = state.company || {};
    const cash = c.cash != null ? money(c.cash) : "seed";
    const burn = c.monthly_burn != null ? money(c.monthly_burn) + "/mo" : "seed";
    const md = c.milestone_date || "seed milestone";
    const host = c.website ? String(c.website).replace(/^https?:\/\//, "").split("/")[0] : "";
    $("company-chip").textContent = `${c.name || "Your company"}${host ? " · " + host : ""} · ${cash} cash · ${burn} burn · milestone ${md}`;
    $("modules-chip").innerHTML = (state.modules || [])
      .map((m) => `<span>${escapeHtml(AREA_LABEL[m] || m)}</span>`)
      .join("");
    showView("app");
    initSchemaRail();
    renderTypeChips();
  }

  $("cta-start").addEventListener("click", () => {
    resetIntake();
    resetIntakeKeepProfile();
    showView("intake");
  });

  $("cta-demo").addEventListener("click", () => {
    state.plan = "Hire two engineers to hit the October launch";
    state.answers = {};
    state.modules = ["management", "launch"];
    state.fixtureId = "interlock";
    state.proposal = INTERLOCK;
    state.company = {};
    $("depth").value = "3"; // cached demo is authored at 3 rounds
    goWarRoom();
  });

  $("intake-back").addEventListener("click", () => showView("landing"));
  $("btn-new").addEventListener("click", () => {
    stopPlay();
    resetIntake();
    showView("landing");
  });

  async function postIntake() {
    const answers = { ...state.answers };
    const hist = priorHistoryText(state.profile);
    if (hist) answers.prior_history = hist;
    const res = await fetch("/api/intake", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ plan: state.plan, answers, modules: state.modules }),
    });
    const data = await res.json();
    if (!res.ok || data.error) throw new Error(data.error || "Intake failed");
    return data;
  }

  function renderAreaGrid() {
    const grid = $("area-grid");
    if (!grid) return;
    grid.innerHTML = "";
    CONSULT_AREAS.forEach((a) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "area-card" + (state.modules.includes(a.id) ? " on" : "");
      btn.dataset.area = a.id;
      btn.innerHTML = `<strong>${escapeHtml(a.label)}</strong><span>${escapeHtml(a.blurb)}</span><em>${escapeHtml(a.agents)}</em>`;
      btn.addEventListener("click", () => {
        if (state.modules.includes(a.id)) {
          state.modules = state.modules.filter((x) => x !== a.id);
        } else {
          state.modules = [...state.modules, a.id];
        }
        renderAreaGrid();
        showModules(state.modules);
      });
      grid.appendChild(btn);
    });
  }

  function showModules(mods) {
    const el = $("module-pills");
    if (!mods || !mods.length) {
      el.hidden = true;
      el.innerHTML = "";
      return;
    }
    el.hidden = false;
    el.innerHTML = mods
      .map((m) => `<span>${escapeHtml(AREA_LABEL[m] || m)}</span>`)
      .join("");
  }

  function pushThread(who, text) {
    const div = document.createElement("div");
    div.className = `bubble ${who}`;
    div.textContent = text;
    $("intake-thread").appendChild(div);
    div.scrollIntoView({ block: "nearest" });
  }

  function profileDefaultForField(field) {
    const p = state.profile;
    if (!p) return "";
    const map = {
      describe: p.describe,
      cash: p.cash,
      monthly_burn: p.monthly_burn,
      mrr: p.mrr,
      growth: p.growth,
      headcount: p.headcount,
      milestone: p.milestone,
      milestone_date: p.milestone_date,
    };
    const v = map[field];
    return v == null || v === "" ? "" : String(v);
  }

  function renderQuestion(q, onAnswer = answerAndAdvance) {
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
      $("q-submit").addEventListener("click", () => onAnswer(q.field, picked));
    } else {
      const inputType = q.type === "number" ? "number" : q.type === "date" ? "date" : "text";
      const pref = profileDefaultForField(q.field);
      const ph = q.placeholder || "";
      box.innerHTML = `
        <label for="q-input">${escapeHtml(q.prompt)}</label>
        <input id="q-input" type="${inputType}" placeholder="${escapeHtml(ph)}" value="${escapeHtml(pref)}" />
        <button type="button" class="run-btn" id="q-submit">Continue</button>`;
      $("q-submit").addEventListener("click", () => {
        const v = $("q-input").value.trim();
        if (!v) return;
        onAnswer(q.field, q.type === "number" ? Number(v) : v);
      });
      $("q-input").addEventListener("keydown", (e) => {
        if (e.key === "Enter") $("q-submit").click();
      });
      setTimeout(() => $("q-input").focus(), 50);
    }
  }

  // Adaptive follow-ups are answered locally (no server round-trip per answer),
  // then the batch is submitted with _extra_done set.
  function askExtras(queue) {
    if (!queue.length) {
      state.answers._extra_done = 1;
      $("intake-current").innerHTML = "";
      $("intake-status").textContent = "Building your simulation brief…";
      postIntake().then(applyIntake).catch((err) => {
        $("intake-status").textContent = `Error: ${err.message || err}`;
      });
      return;
    }
    const q = queue[0];
    pushThread("sys", q.prompt);
    renderQuestion(q, (field, value) => {
      state.answers[field] = value;
      pushThread("you", String(value));
      $("intake-current").innerHTML = "";
      askExtras(queue.slice(1));
    });
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
    if (state.profile) {
      if (state.profile.name && !state.company.name) state.company.name = state.profile.name;
      if (state.profile.website && !state.company.website) state.company.website = state.profile.website;
      if (state.profile.summary && !state.company.summary) state.company.summary = state.profile.summary;
      if (state.profile.describe && !state.company.describe) state.company.describe = state.profile.describe;
    }
    showModules(state.modules);
    if (data.restated) pushThread("sys", `Decision as I understand it: ${data.restated}`);
    $("intake-status").textContent = data.spine || "";
    if (data.ready) {
      state.proposal = withPriorHistory(data.proposal);
      goWarRoom();
      return;
    }
    const q = (data.questions || [])[0];
    if (!q) {
      const extras = data.extra_questions || [];
      if (extras.length) {
        pushThread("sys", "Now a few questions specific to your plan —");
        askExtras(extras);
        return;
      }
      state.proposal = withPriorHistory(data.proposal || state.plan);
      goWarRoom();
      return;
    }
    pushThread("sys", q.prompt);
    renderQuestion(q);
  }

  $("intake-plan-next").addEventListener("click", async () => {
    const plan = $("intake-plan").value.trim();
    if (!state.modules.length) {
      $("intake-status").textContent = "Pick at least one consult desk first.";
      return;
    }
    if (!plan) {
      $("intake-status").textContent = "Type a plan of action first.";
      return;
    }
    state.plan = plan;
    const quick = !!(state.profile && $("intake-quick") && $("intake-quick").checked);
    $("intake-plan-block").hidden = true;
    $("intake-q-block").hidden = false;
    $("intake-thread").innerHTML = "";
    pushThread("you", plan);
    pushThread("sys", `Desks: ${(state.modules || []).map((m) => AREA_LABEL[m] || m).join(" · ")}`);
    const hist = priorHistoryText(state.profile);
    if (hist) {
      pushThread("sys", `Using ${hist.split("\n").length} prior follow-through note(s) from ${state.profile.name}.`);
    }
    if (quick) {
      state.answers = {
        ...profileAsAnswers(state.profile),
        ...defaultShapesForModules(state.modules),
        _extra_done: 1,
      };
      pushThread(
        "sys",
        `Quick mode — using saved ${state.profile.name} numbers${state.profile.website ? " + site intel" : ""}. Skipping long intake.`
      );
      $("intake-status").textContent = "Building brief from saved business…";
    } else {
      state.answers = state.profile
        ? {
            biz_name: state.profile.name || "",
            website: state.profile.website || "",
            summary: state.profile.summary || "",
          }
        : {};
      $("intake-status").textContent = "Loading desk intake…";
    }
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

  const PIPELINE_FOCUS = {
    seed: ["CompanyState", "Branch", "Tool", "SeedWorldWalker", "ProtocolWalker"],
    blue: ["Branch", "Tool", "Evidence", "BlueWalker", "ProtocolWalker"],
    red: ["Branch", "Attack", "Tool", "RedWalker", "ProtocolWalker"],
    tools: ["Tool", "Evidence", "verified_by", "has_tool", "ProtocolWalker"],
    branch: ["Branch", "derives_from", "leads_to", "Evidence", "ScoreWalker", "BlueWalker"],
    arbiter: ["Memo", "Branch", "ArbiterWalker", "ScoreWalker", "ProtocolWalker"],
  };

  let schemaSelection = null;
  let schemaFilter = "all";
  let schemaPipelineFocus = null;
  let ospReady = false;

  function liveCounts() {
    if (!runData) return {};
    return {
      CompanyState: runData.company ? 1 : 0,
      Branch: (runData.branches || []).length,
      Attack: (runData.attacks || []).length,
      Evidence: (runData.evidence_log || []).length,
      Tool: 2,
      Memo: runData.memo ? 1 : 0,
    };
  }

  function initSchemaRail() {
    const explain = $("schema-explain");
    document.querySelectorAll(".schema-node").forEach((btn) => {
      btn.addEventListener("click", () => {
        document.querySelectorAll(".schema-node").forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
        const key = btn.dataset.schema;
        explain.textContent = SCHEMA_COPY[key] || "";
        schemaPipelineFocus = key;
        renderOspMap();
        const focusIds = PIPELINE_FOCUS[key] || [];
        if (focusIds[0]) selectSchemaItem(focusIds[0]);
        $("osp-board")?.scrollIntoView({ behavior: "smooth", block: "nearest" });
      });
    });
    document.querySelectorAll(".schema-filter").forEach((btn) => {
      btn.addEventListener("click", () => {
        document.querySelectorAll(".schema-filter").forEach((b) => b.classList.remove("on"));
        btn.classList.add("on");
        schemaFilter = btn.dataset.filter;
        renderOspMap();
      });
    });
  }

  function lightSchemaFromEvent(kind) {
    const map = { seed: "seed", blue: "blue", red: "red", tool: "tools", arbiter: "arbiter", walker: "branch" };
    const key = map[kind];
    document.querySelectorAll(".schema-node").forEach((b) => b.classList.toggle("lit", key && b.dataset.schema === key));
    if (key && SCHEMA_COPY[key]) $("schema-explain").textContent = SCHEMA_COPY[key];
    if (key) {
      schemaPipelineFocus = key;
      if (ospReady) renderOspMap();
    }
  }

  function schemaCatalog() {
    const schema = window.SPLIT_SCHEMA || {};
    const items = [];
    (schema.nodes || []).forEach((n) => items.push({ ...n, kind: "node" }));
    (schema.edges || []).forEach((e) => items.push({ ...e, kind: "edge" }));
    (schema.walkers || []).forEach((w) => items.push({ ...w, kind: "walker" }));
    return { schema, items };
  }

  function selectSchemaItem(id) {
    const { items, schema } = schemaCatalog();
    const item = items.find((x) => x.id === id);
    if (!item) return;
    schemaSelection = id;
    renderSchemaDetail(item, schema);
    renderOspMap();
  }

  function renderSchemaDetail(item, schema) {
    const detail = $("schema-detail");
    if (!detail || !item) return;
    const counts = liveCounts();
    const count = counts[item.id];
    let html = `<div class="sd-kicker">${escapeHtml(item.kind)}</div>`;
    html += `<h3 class="sd-title">${escapeHtml(item.id)}</h3>`;
    html += `<p>${escapeHtml(item.blurb || "")}</p>`;
    if (count != null) {
      html += `<p class="sd-live mono">Live this run: <strong>${count}</strong> instance${count === 1 ? "" : "s"}</p>`;
    }
    if (item.fields?.length) {
      html += `<h4>Fields</h4><ul class="sd-fields">${item.fields.map((f) => `<li><code>${escapeHtml(f)}</code></li>`).join("")}</ul>`;
    }
    if (item.kind === "edge") {
      html += `<p class="sd-edge mono">${escapeHtml(item.from)} → ${escapeHtml(item.to)}</p>`;
    }
    if (item.kind === "walker" && item.visits?.length) {
      html += `<h4>Visits</h4><div class="sd-pills">${item.visits.map((v) => `<button type="button" class="sd-pill" data-jump="${escapeHtml(v)}">${escapeHtml(v)}</button>`).join("")}</div>`;
    }
    if (item.kind === "node") {
      const inbound = (schema.edges || []).filter((e) => e.to === item.id);
      const outbound = (schema.edges || []).filter((e) => e.from === item.id);
      const walkers = (schema.walkers || []).filter((w) => (w.visits || []).includes(item.id));
      if (outbound.length) {
        html += `<h4>Outgoing edges</h4><div class="sd-pills">${outbound.map((e) => `<button type="button" class="sd-pill" data-jump="${escapeHtml(e.id)}">${escapeHtml(e.id)} → ${escapeHtml(e.to)}</button>`).join("")}</div>`;
      }
      if (inbound.length) {
        html += `<h4>Incoming edges</h4><div class="sd-pills">${inbound.map((e) => `<button type="button" class="sd-pill" data-jump="${escapeHtml(e.id)}">${escapeHtml(e.from)} → ${escapeHtml(e.id)}</button>`).join("")}</div>`;
      }
      if (walkers.length) {
        html += `<h4>Walkers that visit</h4><div class="sd-pills">${walkers.map((w) => `<button type="button" class="sd-pill walker" data-jump="${escapeHtml(w.id)}">${escapeHtml(w.id)}</button>`).join("")}</div>`;
      }
    }
    if (item.pipeline?.length) {
      html += `<h4>Pipeline</h4><div class="sd-pills">${item.pipeline.map((p) => `<span class="sd-pill dim">${escapeHtml(p)}</span>`).join("")}</div>`;
    }
    detail.innerHTML = html;
    detail.querySelectorAll("[data-jump]").forEach((btn) => {
      btn.addEventListener("click", () => selectSchemaItem(btn.dataset.jump));
    });
  }

  function renderTypeChips() {
    renderOspMap();
  }

  function renderOspMap() {
    const board = $("osp-board");
    if (!board) return;
    const { schema, items } = schemaCatalog();
    if (!items.length) return;

    const focusSet = schemaPipelineFocus ? new Set(PIPELINE_FOCUS[schemaPipelineFocus] || []) : null;
    const visible = items.filter((it) => {
      if (schemaFilter === "nodes" && it.kind !== "node") return false;
      if (schemaFilter === "edges" && it.kind !== "edge") return false;
      if (schemaFilter === "walkers" && it.kind !== "walker") return false;
      if (focusSet) {
        if (it.kind === "edge") return focusSet.has(it.from) && focusSet.has(it.to);
        return focusSet.has(it.id);
      }
      return true;
    });

    const counts = liveCounts();
    const groups = [
      { key: "node", title: "Nodes", list: visible.filter((v) => v.kind === "node") },
      { key: "edge", title: "Edges", list: visible.filter((v) => v.kind === "edge") },
      { key: "walker", title: "Walkers", list: visible.filter((v) => v.kind === "walker") },
    ].filter((g) => g.list.length);

    board.innerHTML = groups
      .map((g) => {
        const cards = g.list
          .map((it) => {
            const live = counts[it.id];
            const sub =
              it.kind === "edge"
                ? `${it.from} → ${it.to}`
                : it.kind === "walker"
                  ? (it.visits || []).slice(0, 3).join(", ")
                  : (it.fields || []).slice(0, 3).join(", ");
            const countBadge = live != null ? `<span class="osp-badge">${live}</span>` : "";
            return `<button type="button" class="osp-card ${it.kind} ${it.role || ""} ${schemaSelection === it.id ? "selected" : ""}" data-id="${escapeHtml(it.id)}">
              <span class="osp-card-kicker">${escapeHtml(it.kind)}${countBadge}</span>
              <strong>${escapeHtml(it.id)}</strong>
              <span class="osp-card-sub mono">${escapeHtml(sub)}</span>
            </button>`;
          })
          .join("");
        return `<div class="osp-col"><p class="osp-col-title">${g.title}</p><div class="osp-cards">${cards}</div></div>`;
      })
      .join("");

    board.querySelectorAll(".osp-card").forEach((btn) => {
      btn.addEventListener("click", () => selectSchemaItem(btn.dataset.id));
    });

    ospReady = true;
    if (schemaSelection) {
      const still = items.find((x) => x.id === schemaSelection);
      if (still) renderSchemaDetail(still, schema);
    }
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
    // Stable order: blue before red, alive before dead
    const sortKids = (node) => {
      if (!node?.children) return;
      node.children.sort((a, b) => {
        const side = (x) => (x.side_created === "blue" ? 0 : x.side_created === "red" ? 1 : 2);
        if (side(a) !== side(b)) return side(a) - side(b);
        if ((a.alive === false) !== (b.alive === false)) return a.alive === false ? 1 : -1;
        return String(a.id).localeCompare(String(b.id));
      });
      node.children.forEach(sortKids);
    };
    sortKids(root);
    return root;
  }
  function ensureSvg() {
    const svg = d3.select("#graph");
    const stage = $("viz-stage");
    const width = stage.clientWidth || 700, height = stage.clientHeight || 560;
    svg.attr("viewBox", `0 0 ${width} ${height}`).attr("width", "100%").attr("height", "100%");
    if (!svgReady) {
      svg.selectAll("*").remove();
      const g = svg.append("g").attr("class", "viewport");
      zoomBehavior = d3.zoom().scaleExtent([0.35, 2.4]).on("zoom", (event) => g.attr("transform", event.transform));
      svg.call(zoomBehavior);
      g.append("g").attr("class", "links");
      g.append("g").attr("class", "link-labels");
      g.append("g").attr("class", "nodes");
      svgReady = true;
      svg.on("click", () => {
        selectedId = null;
        $("inspector").hidden = true;
        g.selectAll(".branch-node").classed("selected", false);
        document.querySelectorAll(".branch-chip").forEach((c) => c.classList.remove("on"));
      });
    }
    return { width, height, g: svg.select("g.viewport"), svg };
  }
  function truncate(s, n = 22) {
    const t = String(s || "");
    return t.length > n ? `${t.slice(0, n - 1)}…` : t;
  }
  function branchTitle(b) {
    if (!b.parent_id) return b.label || "Seed company";
    return b.last_action || b.last_stressor || b.label || b.move || b.id;
  }
  function branchVerdictLine(b, recommended) {
    if (b.alive === false) {
      const reason = humanizeDetail(b.kill_reason || "Failed hard arithmetic");
      return { text: truncate(reason, 46), fail: true };
    }
    const rw = Number(b.runway_months);
    const cf = Number.isFinite(rw) && rw >= 900;
    if (b.id === recommended) {
      return { text: cf ? "Recommended · cash-flow positive" : `Recommended · cash-out ${pretty(b.cash_out_date)}`, fail: false };
    }
    if (!b.parent_id) {
      return { text: cf ? "Seed · cash-flow positive" : `Seed · runway ${Number.isFinite(rw) ? rw.toFixed(1) : "—"} mo`, fail: false };
    }
    if (b.milestone_hit) {
      return { text: cf ? "Survives · cash-flow positive" : `Survives · clears milestone · ${pretty(b.cash_out_date)}`, fail: false };
    }
    return { text: cf ? "Alive · cash-flow positive" : `Alive · cash-out ${pretty(b.cash_out_date)} · milestone miss`, fail: false };
  }
  function wrapSvgText(selection, text, maxChars, lineHeight = 11) {
    const words = String(text || "").split(/\s+/).filter(Boolean);
    const lines = [];
    let cur = "";
    words.forEach((w) => {
      const next = cur ? `${cur} ${w}` : w;
      if (next.length > maxChars && cur) {
        lines.push(cur);
        cur = w;
      } else cur = next;
    });
    if (cur) lines.push(cur);
    selection.selectAll("tspan").remove();
    lines.slice(0, 2).forEach((line, i) => {
      selection
        .append("tspan")
        .attr("x", PAD_X)
        .attr("dy", i === 0 ? 0 : lineHeight)
        .text(line);
    });
  }
  function fitGraph() {
    if (!svgReady || typeof d3 === "undefined") return;
    const svg = d3.select("#graph");
    const g = svg.select("g.viewport");
    const nodes = g.selectAll("g.branch-node").nodes();
    if (!nodes.length) return;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    nodes.forEach((n) => {
      const t = n.transform.baseVal.consolidate()?.matrix;
      if (!t) return;
      minX = Math.min(minX, t.e);
      minY = Math.min(minY, t.f);
      maxX = Math.max(maxX, t.e + CARD_W);
      maxY = Math.max(maxY, t.f + CARD_H);
    });
    const stage = $("viz-stage");
    const width = stage.clientWidth || 700, height = stage.clientHeight || 560;
    const bw = Math.max(1, maxX - minX), bh = Math.max(1, maxY - minY);
    const scale = Math.min(1.15, Math.max(0.4, Math.min((width - 48) / bw, (height - 48) / bh)));
    const tx = (width - bw * scale) / 2 - minX * scale;
    const ty = (height - bh * scale) / 2 - minY * scale;
    svg.transition().duration(350).call(zoomBehavior.transform, d3.zoomIdentity.translate(tx, ty).scale(scale));
  }

  // Card geometry. Text is laid out on a fixed grid: id at the top, title in the
  // middle (up to 2 wrapped lines), then meta and verdict anchored to the BOTTOM so
  // rows never collide whether the title wraps to one line or two.
  const CARD_W = 212;
  const CARD_H = 94;
  const PAD_X = 11;
  const TEXT_W = CARD_W - PAD_X * 2;
  // Approx advance width per character, by the font each row uses.
  const CH_MONO = 5.75;
  const CH_DISPLAY = 7.0;
  const CH_SANS = 5.35;
  const fitChars = (px, per) => Math.max(8, Math.floor(px / per));

  function renderGraph(data, allowedIds, revealedIds = null) {
    if (typeof d3 === "undefined") return;
    const { width, height, g } = ensureSvg();
    const rootData = buildHierarchy(data, allowedIds);
    const linksG = g.select("g.links");
    const labelsG = g.select("g.link-labels");
    const nodesG = g.select("g.nodes");
    if (!rootData) {
      linksG.selectAll("*").remove();
      labelsG.selectAll("*").remove();
      nodesG.selectAll("*").remove();
      return;
    }
    const root = d3.hierarchy(rootData);
    d3.tree().nodeSize([CARD_H + 28, CARD_W + 56])(root);

    // Left → right tree (Obsidian-like flow)
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    root.each((d) => {
      const x = d.y;
      const y = d.x;
      d.x = x;
      d.y = y;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
    });
    const treeW = Math.max(1, maxX - minX);
    const treeH = Math.max(1, maxY - minY);
    const padX = 24;
    const padY = 20;
    const offsetX = padX - minX;
    const offsetY = (height - treeH) / 2 - minY;
    root.each((d) => {
      d.x += offsetX;
      d.y += offsetY;
    });

    const recommended = data.memo?.recommended_branch_id;
    const revealed = revealedIds || allowedIds;
    const linkPath = (d) => {
      const s = d.source, t = d.target;
      const x0 = s.x + CARD_W, y0 = s.y + CARD_H / 2;
      const x1 = t.x, y1 = t.y + CARD_H / 2;
      const mid = (x0 + x1) / 2;
      return `M${x0},${y0}C${mid},${y0} ${mid},${y1} ${x1},${y1}`;
    };

    linksG
      .selectAll("path.branch-link")
      .data(root.links(), (d) => d.target.data.id)
      .join(
        (enter) =>
          enter
            .append("path")
            .attr("class", (d) => linkClass(d))
            .attr("d", linkPath)
            .attr("stroke-opacity", 0)
            .call((s) => s.transition().duration(400).attr("stroke-opacity", null)),
        (update) =>
          update
            .attr("class", (d) => linkClass(d))
            .transition()
            .duration(300)
            .attr("d", linkPath),
        (exit) => exit.transition().duration(180).attr("stroke-opacity", 0).remove()
      );

    function linkClass(d) {
      const dead = d.target.data.alive === false;
      const side = d.target.data.side_created || "seed";
      const dim = revealed && !revealed.has(d.target.data.id) ? "dim" : "";
      return `branch-link ${dead ? "dead" : side} ${dim}`.trim();
    }

    labelsG
      .selectAll("text.link-tag")
      .data(root.links(), (d) => d.target.data.id)
      .join("text")
      .attr("class", "link-tag")
      .attr("text-anchor", "middle")
      .attr("x", (d) => (d.source.x + CARD_W + d.target.x) / 2)
      .attr("y", (d) => (d.source.y + d.target.y) / 2 + CARD_H / 2 - 6)
      .text((d) => {
        if (d.target.data.alive === false) return "kill";
        if (d.target.data.side_created === "blue") return "blue";
        if (d.target.data.side_created === "red") return "red";
        return "";
      })
      .style("opacity", (d) => (revealed && !revealed.has(d.target.data.id) ? 0.25 : 0.9));

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

    nodesEnter.append("circle").attr("class", "walker-pulse").attr("cx", CARD_W / 2).attr("cy", CARD_H / 2).attr("r", 12);
    nodesEnter
      .append("rect")
      .attr("class", "node-card")
      .attr("width", CARD_W)
      .attr("height", CARD_H)
      .attr("rx", 6)
      .attr("ry", 6);
    nodesEnter.append("rect").attr("class", "node-accent").attr("width", 4).attr("height", CARD_H).attr("rx", 2);
    nodesEnter.append("text").attr("class", "node-id").attr("x", PAD_X).attr("y", 17);
    nodesEnter.append("text").attr("class", "node-title").attr("x", PAD_X).attr("y", 36);
    nodesEnter.append("text").attr("class", "node-meta").attr("x", PAD_X).attr("y", CARD_H - 26);
    nodesEnter.append("text").attr("class", "node-verdict").attr("x", PAD_X).attr("y", CARD_H - 10);

    // Named transition on purpose: the unnamed transform transition on `merged` below
    // includes these same elements, and an unnamed fade would be interrupted by it —
    // leaving every card stuck at opacity 0 (links visible, nodes invisible).
    // Clearing the inline style on end also hands opacity back to CSS, so .dim works.
    nodesEnter
      .transition("fade")
      .duration(350)
      .style("opacity", 1)
      .on("end", function () {
        d3.select(this).style("opacity", null);
      });
    const merged = nodesEnter.merge(nodes);
    merged
      .classed("dim", (d) => revealed && !revealed.has(d.data.id))
      .classed("selected", (d) => d.data.id === selectedId)
      .transition()
      .duration(280)
      .attr("transform", (d) => `translate(${d.x},${d.y})`);

    merged.select(".node-card").attr("class", (d) => {
      const dead = d.data.alive === false;
      const pick = d.data.id === recommended;
      const side = d.data.side_created || "seed";
      return `node-card ${dead ? "dead" : "alive"} ${side}${pick ? " pick" : ""}`;
    });
    merged.select(".node-accent").attr("class", (d) => {
      if (d.data.id === recommended) return "node-accent pick";
      if (d.data.alive === false) return "node-accent dead";
      return `node-accent ${d.data.side_created || "seed"}`;
    });
    merged.select(".node-id").text((d) => {
      const side = (d.data.side_created || "seed").toUpperCase();
      const status = d.data.alive === false ? "KILLED" : d.data.id === recommended ? "PICK" : "ALIVE";
      const budget = fitChars(TEXT_W, CH_MONO);
      // Desk is the first thing to drop when the row would overflow.
      const full = `${d.data.id} · ${side}${d.data.desk ? ` · ${d.data.desk}` : ""} · ${status}`;
      return full.length <= budget ? full : `${d.data.id} · ${side} · ${status}`;
    });
    merged.select(".node-title").each(function (d) {
      const perLine = fitChars(TEXT_W, CH_DISPLAY);
      wrapSvgText(d3.select(this), truncate(branchTitle(d.data), perLine * 2 - 2), perLine, 15);
    });
    merged.select(".node-meta").text((d) => {
      const rw = Number(d.data.runway_months);
      const cf = Number.isFinite(rw) && rw >= 900;
      const budget = fitChars(TEXT_W, CH_MONO);
      if (cf) return "cash-flow positive";
      const long = `cash-out ${pretty(d.data.cash_out_date)} · ${rw.toFixed(1)}mo runway`;
      if (long.length <= budget) return long;
      return `cash-out ${pretty(d.data.cash_out_date)} · ${rw.toFixed(1)}mo`;
    });
    merged.select(".node-verdict").each(function (d) {
      const v = branchVerdictLine(d.data, recommended);
      const el = d3.select(this);
      el.attr("class", `node-verdict${v.fail ? " fail" : ""}`)
        .text(truncate(v.text, fitChars(TEXT_W, CH_SANS)));
    });

    nodes.exit().transition().duration(180).style("opacity", 0).remove();

    // Keep tree roughly in view on first paint of a new run
    if (!revealedIds || revealedIds.size >= allowedIds.size) {
      requestAnimationFrame(() => fitGraph());
    }
  }

  // Branch ids are references INTO the tree, not a separate list to read. Anywhere the
  // arbiter says "b3", it becomes a chip that selects and scrolls to that node.
  const BRANCH_REF_RE = /\b(b\d{1,3})\b/g;

  function linkifyBranches(text) {
    return escapeHtml(text).replace(BRANCH_REF_RE, (id) => {
      const known = (runData?.branches || []).some((b) => b.id === id);
      return known ? `<button type="button" class="branch-ref" data-id="${id}">${id}</button>` : id;
    });
  }

  function setLinkedText(elId, text) {
    const el = $(elId);
    if (!el) return;
    el.innerHTML = linkifyBranches(text || "");
  }

  function focusBranch(id) {
    if (!(runData?.branches || []).some((b) => b.id === id)) return;
    selectBranch(id);
    const stage = $("viz-stage");
    if (stage) stage.scrollIntoView({ behavior: "smooth", block: "center" });
    pulseBranch(id);
  }

  document.addEventListener("click", (e) => {
    const btn = e.target.closest && e.target.closest(".branch-ref");
    if (btn && btn.dataset.id) focusBranch(btn.dataset.id);
  });

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
  function allBranchIds(data) {
    return new Set((data.branches || []).map((b) => b.id));
  }
  function setEventIndex(i, { pulse = true } = {}) {
    if (!runData) return;
    const events = runData.events || [];
    eventIndex = Math.max(-1, Math.min(i, events.length - 1));
    $("scrub").value = String(Math.max(0, eventIndex));
    $("scrub-label").textContent = `${Math.max(0, eventIndex + 1)} / ${events.length}`;
    const all = allBranchIds(runData);
    // Always draw the full tree; dim branches not yet reached in the replay.
    const revealed = eventIndex < 0 ? all : idsThroughEvent(eventIndex);
    renderGraph(runData, all, revealed.size ? revealed : all);
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
    }, 900);
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
  $("btn-fit")?.addEventListener("click", () => fitGraph());

  // ---- Human-readable verifier vocabulary --------------------------------
  // The engine speaks in check ids and shouty assert strings. Founders shouldn't
  // have to. Names of art (runway, net burn, cash-out, milestone) are kept.
  const CHECK_META = {
    runway_floor: { label: "Runway floor", blurb: "Cash ÷ net burn must clear 1.5 months" },
    alive_at_milestone: { label: "Alive at the milestone", blurb: "Cash must outlast the milestone date" },
    hire_burn_delta: { label: "Hire burn step", blurb: "A hire must not add $30k+/mo of burn at once" },
    milestone_before_cashout: { label: "Milestone before cash-out", blurb: "The date must land while cash remains" },
    cash_out_date: { label: "Cash-out date", blurb: "Deterministic from cash, burn and MRR" },
    plan_cost_applied: { label: "Your stated cost applied", blurb: "The plan's price comes from your intake answers, not the model" },
    apply_effect: { label: "Effect application", blurb: "Model proposes the move, code computes the numbers" },
  };

  const checkLabel = (id) => CHECK_META[id]?.label || String(id || "").replace(/_/g, " ");

  // Add thousands separators to bare figures the engine emitted unformatted.
  const commafy = (t) => String(t).replace(/\$(\d{4,})(?!\d*,)/g, (_, n) => `$${Number(n).toLocaleString()}`);

  function humanizeDetail(text) {
    let t = commafy(String(text || "").trim());
    t = t
      .replace(/^ALIVE CHECK:\s*/i, "")
      .replace(/\s*—\s*KILL\s*—\s*cash ends before ship/i, " — cash runs out first")
      .replace(/\s*—\s*KILL\s*—\s*/i, " — ")
      .replace(/\s*—\s*BRUTAL FAIL\s*\(([^)]+)\)/i, " — too big a step in one go ($1)")
      .replace(/\s*—\s*OK\s*$/i, "")
      .replace(/^No prior burn$/i, "Not a hiring move — this check does not apply")
      .replace(/^Runway\s+([\d.]+)\s+months/i, "Runway $1 months")
      .replace(/\bCF\+/g, "cash-flow positive");
    return t;
  }

  // "finance Blue: <claim> [Move name]" → just the claim; the title and kicker
  // already carry the move name and the desk.
  function branchClaim(b) {
    return String(b.claim || b.summary || "")
      .replace(/^\s*\w+\s+(Blue|Red):\s*/i, "")
      .replace(/\s*\[[^\]]*\]\s*$/, "")
      .trim();
  }

  function selectBranch(id) {
    if (!runData) return;
    selectedId = id;
    const b = runData.branches.find((x) => x.id === id);
    if (!b) return;
    const recommended = runData.memo?.recommended_branch_id;
    const parent = b.parent_id ? runData.branches.find((x) => x.id === b.parent_id) : null;
    $("inspector").hidden = false;
    const desk = b.desk ? ` · ${b.desk}` : "";
    $("insp-kicker").textContent = `${b.side_created || "seed"}${desk} · round ${b.round ?? 0}`;
    $("insp-title").textContent = branchTitle(b);
    const verdict = $("insp-verdict");
    const v = branchVerdictLine(b, recommended);
    let why = v.text;
    if (parent) {
      why += b.alive === false
        ? ` Forked from ${parent.id} (${truncate(branchTitle(parent), 28)}) and failed the date race.`
        : ` Forked from ${parent.id}; cash-out ${pretty(b.cash_out_date)} vs parent ${pretty(parent.cash_out_date)}.`;
    }
    verdict.textContent = why;
    verdict.className = `insp-verdict${v.fail ? " fail" : ""}`;
    $("insp-stats").innerHTML = `
      <div><dt>Status</dt><dd>${b.alive === false ? "Killed" : b.id === recommended ? "Recommended" : "Alive"}</dd></div>
      <div><dt>Desk</dt><dd>${escapeHtml(b.desk || "—")}</dd></div>
      <div><dt>Cash-out</dt><dd>${escapeHtml(pretty(b.cash_out_date))}</dd></div>
      <div><dt>Milestone</dt><dd>${escapeHtml(pretty(b.milestone_date))}</dd></div>
      <div><dt>Runway</dt><dd>${b.runway_months != null ? (Number(b.runway_months) >= 900 ? "CF+" : Number(b.runway_months).toFixed(2) + " mo") : "—"}</dd></div>
      <div><dt>Milestone hit</dt><dd>${b.milestone_hit ? "yes" : "no"}</dd></div>
      <div><dt>Cash</dt><dd>${money(b.cash)}</dd></div>
      <div><dt>Burn / MRR</dt><dd>${money(b.monthly_burn)} / ${money(b.mrr)}</dd></div>
      <div><dt>Headcount</dt><dd>${b.headcount != null ? b.headcount : "—"}</dd></div>
      <div><dt>Cost Δ</dt><dd>${money(b.cost_delta)}</dd></div>`;
    $("insp-summary").textContent = branchClaim(b);
    const kill = $("insp-kill");
    const win = $("insp-win");
    if (b.kill_reason) {
      kill.hidden = false;
      kill.innerHTML = `<strong>Why it fails</strong><br>${escapeHtml(humanizeDetail(b.kill_reason))}`;
      win.hidden = true;
    } else {
      kill.hidden = true;
      if (b.milestone_hit) {
        win.hidden = false;
        win.innerHTML = `<strong>Why it succeeds</strong><br>Cash lasts until ${escapeHtml(pretty(b.cash_out_date))}, which is after the ${escapeHtml(pretty(b.milestone_date))} milestone — so the company is still solvent on the day it has to deliver.`;
      } else if (!b.parent_id) {
        win.hidden = false;
        win.innerHTML = `<strong>Seed</strong><br>Starting company state before Blue/Red forks.`;
      } else {
        win.hidden = false;
        win.innerHTML = `<strong>Still alive</strong><br>Hard checks passed, but milestone clearance may be thin — compare cash-out to ${escapeHtml(pretty(b.milestone_date))}.`;
      }
    }
    const tools = (runData.evidence_log || runData.tool_log || []).filter((t) => t.branch_id === id);
    $("insp-tools").innerHTML = tools.length
      ? tools
          .map((t) => {
            const id = t.check || t.tool;
            const ok = t.passed ?? t.ok;
            const meta = CHECK_META[id];
            return `<li class="ev-row ${ok ? "pass" : "fail"}" title="${escapeHtml(id)}">
              <div class="ev-head">
                <span class="ev-mark">${ok ? "✓" : "✕"}</span>
                <strong>${escapeHtml(checkLabel(id))}</strong>
                <span class="ev-rule">${escapeHtml(meta ? meta.blurb : "")}</span>
              </div>
              <p class="ev-detail">${escapeHtml(humanizeDetail(t.detail || t.value || ""))}</p>
            </li>`;
          })
          .join("")
      : "<li class='empty'>No checks run yet</li>";
    if (typeof d3 !== "undefined") {
      d3.select("#graph").selectAll(".branch-node").classed("selected", (d) => d.data.id === id);
    }
    document.querySelectorAll(".branch-chip").forEach((c) => c.classList.toggle("on", c.dataset.id === id));
  }
  $("close-insp").addEventListener("click", (e) => {
    e.stopPropagation();
    selectedId = null;
    $("inspector").hidden = true;
    if (typeof d3 !== "undefined") {
      d3.select("#graph").selectAll(".branch-node").classed("selected", false);
    }
    document.querySelectorAll(".branch-chip").forEach((c) => c.classList.remove("on"));
  });

  // Money/measure formatting kept explicit — founders read these as terms of art.
  const usd = (n) => (n == null || !Number.isFinite(Number(n)) ? "—" : `$${Math.round(Number(n)).toLocaleString()}`);

  function countUp(el, text) {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const isDate = /[A-Za-z]{3}\s+\d{1,2},/.test(text);
    const m = String(text).match(/^(.*?)(-?[\d,]+(?:\.\d+)?)(.*)$/);
    if (!m || reduce || isDate) {
      el.textContent = text;
      return;
    }
    const [, pre, raw, post] = m;
    const target = parseFloat(raw.replace(/,/g, ""));
    if (!Number.isFinite(target)) {
      el.textContent = text;
      return;
    }
    const dp = (raw.split(".")[1] || "").length;
    const t0 = performance.now();
    const step = (now) => {
      const p = Math.min(1, (now - t0) / 520);
      const v = target * (1 - Math.pow(1 - p, 3));
      el.textContent = pre + v.toLocaleString(undefined, { minimumFractionDigits: dp, maximumFractionDigits: dp }) + post;
      if (p < 1) requestAnimationFrame(step);
      else el.textContent = text;
    };
    requestAnimationFrame(step);
  }

  function metric(label, value, note, tone) {
    return `<div class="metric${tone ? " " + tone : ""}">
      <dt>${escapeHtml(label)}</dt>
      <dd data-value="${escapeHtml(value)}">${escapeHtml(value)}</dd>
      ${note ? `<span class="metric-note">${escapeHtml(note)}</span>` : ""}
    </div>`;
  }

  function renderMetricRow(m) {
    const row = $("metric-row");
    if (!row) return;
    const a = m.answer || {};
    const best = (runData?.branches || []).find((b) => b.id === m.recommended_branch_id);
    if (!best) {
      row.innerHTML = "";
      return;
    }
    const rw = Number(best.runway_months);
    const cfPositive = Number.isFinite(rw) && rw >= 900;
    const netBurn = Number(best.monthly_burn) - Number(best.mrr);
    const margin = a.margin_days;
    const cells = [];

    cells.push(
      metric("Cash-out date", cfPositive ? "none" : pretty(best.cash_out_date),
        cfPositive ? "MRR covers burn" : "when cash hits zero")
    );
    cells.push(
      metric("Milestone", pretty(best.milestone_date), best.milestone || "target date")
    );
    if (margin != null && !cfPositive) {
      cells.push(
        metric("Margin", `${margin} days`,
          margin >= 0 ? "milestone clears first" : "cash dies first",
          margin >= 0 ? "good" : "bad")
      );
    }
    cells.push(
      metric("Runway", cfPositive ? "cash-flow positive" : `${rw.toFixed(1)} months`,
        "cash ÷ net burn", cfPositive ? "good" : rw < 6 ? "warn" : "")
    );
    cells.push(
      metric("Net burn", netBurn <= 0 ? "profitable" : `${usd(netBurn)}/mo`, "burn − MRR")
    );
    cells.push(metric("MRR", `${usd(best.mrr)}/mo`, `${best.headcount} headcount`));
    cells.push(
      metric("Branches", `${a.survivors ?? "—"} survived`,
        `${a.kills ?? 0} killed by verifiers`, Number(a.kills) > 0 ? "warn" : "")
    );
    row.innerHTML = cells.join("");
    row.querySelectorAll("dd[data-value]").forEach((dd, i) => {
      const text = dd.getAttribute("data-value");
      dd.textContent = "";
      setTimeout(() => countUp(dd, text), 70 + i * 50);
    });
  }

  function renderSides(m) {
    const branchOf = (id) => (runData?.branches || []).find((b) => b.id === id);
    const chip = (id) => (branchOf(id) ? `<button type="button" class="branch-ref" data-id="${id}">${id}</button>` : "");

    const blue = (runData?.findings || []).filter((f) => f.side === "blue");
    $("blue-count").textContent = blue.length ? `· ${blue.length} moves` : "";
    $("blue-list").innerHTML = blue.length
      ? blue
          .map((f) => {
            const b = branchOf(f.branch_id);
            const dead = b && b.alive === false;
            const pick = b && b.id === m.recommended_branch_id;
            const tag = pick
              ? `<span class="outcome pick">recommended</span>`
              : dead
                ? `<span class="outcome dead">killed</span>`
                : `<span class="outcome live">survives</span>`;
            const num = dead
              ? humanizeDetail(b.kill_reason || "")
              : b
                ? `cash-out ${pretty(b.cash_out_date)}`
                : "";
            return `<li>
              <div class="side-top">${chip(f.branch_id)}<strong>${escapeHtml(f.label || f.claim || "move")}</strong>${tag}</div>
              <p class="side-why">${escapeHtml(f.claim || "")}</p>
              <p class="side-num mono">${escapeHtml(num)}</p>
            </li>`;
          })
          .join("")
      : `<li class="empty">No Blue moves recorded.</li>`;

    const red = runData?.attacks || [];
    $("red-count").textContent = red.length ? `· ${red.length} attacks` : "";
    $("red-list").innerHTML = red.length
      ? red
          .map((a) => {
            const b = branchOf(a.branch_id);
            const dead = b && b.alive === false;
            return `<li>
              <div class="side-top">${chip(a.branch_id)}<span class="sev ${escapeHtml(a.severity || "medium")}">${escapeHtml(a.severity || "medium")}</span>${dead ? `<span class="outcome dead">broke it</span>` : `<span class="outcome live">survived</span>`}</div>
              <p class="side-why">${escapeHtml(a.claim || "")}</p>
              <p class="side-num mono">${escapeHtml(b ? (dead ? "branch killed" : `held · cash-out ${pretty(b.cash_out_date)}`) : "")}</p>
            </li>`;
          })
          .join("")
      : `<li class="empty">No Red attacks recorded.</li>`;
  }

  function renderPath(m) {
    // A recommended branch is the END of a chain of moves, not a single move. Without
    // the chain the metrics look wrong (headcount/MRR are cumulative), so show the route.
    const strip = $("path-strip");
    const chain = $("path-chain");
    if (!strip || !chain) return;
    const byId = new Map((runData?.branches || []).map((b) => [b.id, b]));
    let node = byId.get(m.recommended_branch_id);
    if (!node) {
      strip.hidden = true;
      return;
    }
    const route = [];
    const guard = new Set();
    while (node && !guard.has(node.id)) {
      guard.add(node.id);
      route.unshift(node);
      node = node.parent_id ? byId.get(node.parent_id) : null;
    }
    if (route.length < 2) {
      strip.hidden = true;
      return;
    }
    strip.hidden = false;
    chain.innerHTML = route
      .map((b, i) => {
        const isSeed = !b.parent_id;
        const isLast = i === route.length - 1;
        const name = isSeed
          ? "Seed"
          : b.side_created === "red"
            ? `Red: ${truncate(String(b.last_stressor || "stress"), 30)}`
            : truncate(String(b.last_action || b.label || "move"), 30);
        const cls = ["path-node", b.side_created, isLast ? "final" : ""].filter(Boolean).join(" ");
        return `${i ? '<span class="path-arrow">→</span>' : ""}<button type="button" class="${cls}" data-id="${b.id}"><span class="path-id mono">${escapeHtml(b.id)}</span>${escapeHtml(name)}</button>`;
      })
      .join("");
    chain.querySelectorAll(".path-node").forEach((btn) => {
      btn.addEventListener("click", () => focusBranch(btn.dataset.id));
    });

    const moves = route.filter((b) => b.side_created === "blue").length;
    const stresses = route.filter((b) => b.side_created === "red").length;
    const cap = $("metric-caption");
    if (cap) {
      cap.textContent = `State after ${moves} move${moves === 1 ? "" : "s"} and ${stresses} Red stress test${stresses === 1 ? "" : "s"} along this route — not the seed figures.`;
      cap.hidden = false;
    }
  }

  function renderClearAnswer(m) {
    const box = $("clear-answer");
    if (!box) return;
    const a = m.answer || {};
    const headline = a.do || m.title || "";
    if (!headline && !m.prose) {
      box.hidden = true;
      return;
    }
    box.hidden = false;
    box.classList.remove("is-scrolled-away");

    // Split the leading YES / NO / PARTIAL / NOT YET off into its own badge so the
    // verdict reads at a glance instead of hiding inside a sentence.
    const verdict = headline.match(/^\s*(NOT YET|PARTIAL|YES|NO)\b[\s—:,-]*/i);
    const badge = $("verdict-badge");
    if (verdict) {
      const word = verdict[1].toUpperCase();
      badge.hidden = false;
      badge.textContent = word;
      badge.className = `verdict-badge ${word === "YES" ? "yes" : word === "NO" ? "no" : "partial"}`;
      $("answer-do").textContent = headline.slice(verdict[0].length).trim() || headline;
    } else {
      badge.hidden = true;
      $("answer-do").textContent = headline;
    }

    setLinkedText("answer-because", a.because || m.prose || "");
    $("answer-asked").textContent = a.decision ? `You asked: ${a.decision}` : "";
    $("answer-asked").hidden = !a.decision;

    const dont = $("answer-dont");
    const dontText = a.dont && !/^No alternative/i.test(a.dont) ? a.dont : "";
    dont.hidden = !dontText;
    if (dontText) dont.innerHTML = `<strong>Don’t:</strong> ${linkifyBranches(dontText)}`;

    renderPath(m);
    renderMetricRow(m);
    renderSides(m);
  }

  function syncClearAnswerOnScroll() {
    const box = $("clear-answer");
    if (!box || box.hidden) return;
    box.classList.toggle("is-scrolled-away", window.scrollY > 24);
  }
  window.addEventListener("scroll", syncClearAnswerOnScroll, { passive: true });

  function renderMemo(data) {
    const m = data.memo || {};
    const decision = m.decision || "";
    const desk = m.desk ? String(m.desk) : "";
    renderClearAnswer(m);
    // The verdict panel above already carries the answer, the numbers and Blue/Red.
    // The memo only holds what is NOT shown there.
    $("memo").innerHTML = `
      <h3 class="memo-title">${escapeHtml(m.title || "Decision memo")}</h3>
      ${decision ? `<p class="memo-asked">${escapeHtml(decision)}</p>` : ""}
      <div class="memo-tags">
        <span class="pick-pill">Recommended ${escapeHtml(m.recommended_branch_id || "?")}</span>
        ${desk ? `<span class="desk-tag mono">${escapeHtml(desk)} desk</span>` : ""}
      </div>
      <dl class="memo-facts">
        <dt>Kill shots</dt><dd>${linkifyBranches(humanizeDetail(m.kill_shots || "None on the recommended line."))}</dd>
        <dt>Open risks</dt><dd>${escapeHtml(m.open_risks || "—")}</dd>
        <dt>Dissent</dt><dd>${linkifyBranches(m.dissent || "—")}</dd>
      </dl>`;
    $("baseline-out").innerHTML = `<p>${escapeHtml(data.baseline || "No baseline")}</p>`;
    $("hard-rules").innerHTML =
      (data.verifier_registry || [])
        .map((v) => `<li><strong>${escapeHtml(checkLabel(v.name))}</strong> <span class="rule-id mono">${escapeHtml(v.name)}</span><br><span class="rule-blurb">${escapeHtml(v.blurb)}</span></li>`)
        .join("") || "<li class='empty'>None</li>";
    $("reco-banner").hidden = false;
    $("reco-title").textContent = m.title || "Survivor";
    $("reco-body").textContent = m.date_line || m.prose || "";
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
    setLinkedText("plan-analysis", m.analysis || "");
    const watch = $("plan-watch");
    if (m.watch_for) {
      watch.hidden = false;
      watch.textContent = `Watch for: ${m.watch_for}`;
    } else watch.hidden = true;
    $("plan-steps").innerHTML = steps
      .map(
        (s) =>
          `<li class="plan-step ${s.when === "Avoid" ? "avoid" : ""}"><span class="plan-when mono">${escapeHtml(s.when)}</span><div><strong>${escapeHtml(s.title)}</strong><p>${linkifyBranches(s.detail)}</p></div></li>`
      )
      .join("");
  }

  function renderTimeline(data) {
    const events = data.events || [];
    const LABEL = { seed: "SEED", blue: "BLUE", red: "RED", arbiter: "ARBITER", walker: "JAC", prune: "PRUNE", halt: "HALT" };
    $("timeline").innerHTML = events
      .map((ev, i) => {
        let msg = String(ev.message || "");
        const killed = /\[KILL\]/.test(msg) || /KILL —/.test(msg);
        // Strip the id prefix (the chip shows it) and the verifier's shouty formatting.
        msg = humanizeDetail(msg.replace(/^b\d+:\s*/, "").replace(/\s*\[KILL\]\s*/, " "));
        return `<li data-kind="${escapeHtml(ev.kind)}" data-index="${i}" class="${killed ? "killed" : ""}">
          <div class="tl-head">
            <span class="tl-kind ${escapeHtml(ev.kind)}">${escapeHtml(LABEL[ev.kind] || ev.kind)}</span>
            ${ev.branch_id ? `<span class="tl-id mono">${escapeHtml(ev.branch_id)}</span>` : ""}
            ${killed ? `<span class="outcome dead">killed</span>` : ""}
          </div>
          <div class="tl-msg">${escapeHtml(msg.trim())}</div>
        </li>`;
      })
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

  function showOutcomePanel(data, chatId) {
    const panel = $("outcome-panel");
    if (!panel) return;
    if (!state.profile || !chatId) {
      panel.hidden = true;
      return;
    }
    panel.hidden = false;
    const move = data.memo?.answer?.do || data.memo?.title || data.memo?.date_line || "this recommendation";
    $("outcome-prompt").textContent = `Saved under ${state.profile.name}. Sim said: ${move}`;
    if ($("outcome-note")) $("outcome-note").value = "";
    $("outcome-status").textContent = "Tell us what you actually did — next decisions will use this.";
    ["outcome-yes", "outcome-no"].forEach((id) => {
      if ($(id)) $(id).disabled = false;
    });
  }

  async function saveRunAsChat(data) {
    activeChatId = null;
    const panel = $("outcome-panel");
    if (panel) panel.hidden = true;

    const profile = await ensureProfileSynced();
    if (!profile || (!profile.id && !profile.name)) {
      if ($("status")) {
        $("status").textContent = ( $("status").textContent || "" ) + " · Sign in a business to save this decision.";
      }
      return null;
    }

    const m = data.memo || {};
    const a = m.answer || {};
    try {
      const res = await fetch("/api/chats", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          business_id: profile.id || "",
          name: profile.name || "",
          chat: {
            plan: state.plan || a.decision || m.decision || "Decision",
            areas: state.modules || [],
            recommended: a.do || m.title || "",
            recommended_branch_id: m.recommended_branch_id || "",
            date_line: m.date_line || "",
            memo_title: m.title || "",
            one_liner: a.one_liner || m.prose || "",
            fixture_id: state.fixtureId || "custom",
          },
        }),
      });
      const out = await res.json();
      if (!res.ok || out.error) throw new Error(out.error || "Could not save chat");
      if (out.profile) setProfile(out.profile);
      activeChatId = out.chat && out.chat.id;
      showOutcomePanel(data, activeChatId);
      if ($("status")) {
        $("status").textContent = `${data.memo?.date_line || "Done"} · saved to ${profile.name}`;
      }
      return out.chat;
    } catch (err) {
      if ($("status")) $("status").textContent = `Run ok — chat save failed: ${err.message || err}`;
      return null;
    }
  }

  async function submitOutcome(wentThrough, chatId = null, noteOverride = null) {
    const profile = state.profile || (await ensureProfileSynced());
    const cid = chatId || activeChatId;
    if (!profile || !cid) {
      if ($("outcome-status")) $("outcome-status").textContent = "Sign in with a business first so this can be saved.";
      if ($("business-status")) $("business-status").textContent = "Select a business first, then mark Yes / No on a saved decision.";
      return;
    }
    const note =
      noteOverride != null
        ? noteOverride
        : (($("outcome-note") && $("outcome-note").value.trim()) || "");
    if ($("outcome-status")) $("outcome-status").textContent = "Saving…";
    if ($("business-status")) $("business-status").textContent = "Saving follow-through…";
    try {
      const res = await fetch("/api/chats/outcome", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          business_id: profile.id || "",
          name: profile.name || "",
          chat_id: cid,
          went_through: wentThrough,
          note,
        }),
      });
      const out = await res.json();
      if (!res.ok || out.error) throw new Error(out.error || "Save failed");
      if (out.profile) setProfile(out.profile);
      let label = "Follow-through cleared — pending again.";
      if (wentThrough === true) label = "Went through — saved";
      else if (wentThrough === false) label = "Did not go through — saved";
      if ($("outcome-status")) {
        $("outcome-status").textContent = `${label}. Next chats for ${profile.name} will use this.`;
      }
      if ($("business-status")) {
        $("business-status").textContent = `${label} for ${profile.name}.`;
      }
      if (wentThrough !== null) {
        ["outcome-yes", "outcome-no"].forEach((id) => {
          if ($(id)) $(id).disabled = true;
        });
      } else {
        ["outcome-yes", "outcome-no"].forEach((id) => {
          if ($(id)) $(id).disabled = false;
        });
      }
      if (cid === activeChatId && wentThrough !== null && $("outcome-panel")) {
        // keep panel visible with confirmation
      }
    } catch (err) {
      if ($("outcome-status")) $("outcome-status").textContent = `Error: ${err.message || err}`;
      if ($("business-status")) $("business-status").textContent = `Follow-through error: ${err.message || err}`;
    }
  }

  $("outcome-yes")?.addEventListener("click", () => submitOutcome(true));
  $("outcome-no")?.addEventListener("click", () => submitOutcome(false));
  $("outcome-skip")?.addEventListener("click", () => {
    const panel = $("outcome-panel");
    if (panel) panel.hidden = true;
    if ($("outcome-status")) $("outcome-status").textContent = "";
  });

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
    const banner = $("demo-banner");
    if (banner) {
      const offline = state.fixtureId === "interlock" || data.jac_runtime;
      banner.hidden = false;
      banner.textContent =
        state.fixtureId === "interlock"
          ? "Offline golden run · Jac walkers · deterministic verifiers"
          : data.jac_runtime
            ? `Jac runtime · ${data.jac_runtime}`
            : "Live simulation · Jac walkers · deterministic verifiers";
    }
    renderKillCallout(data);
    renderMemo(data);
    renderTimeline(data);
    renderOspMap();
    // Show the full tree immediately (Obsidian-style map), then optional replay.
    const last = Math.max(0, n - 1);
    setEventIndex(last, { pulse: false });
    const pick = data.memo?.recommended_branch_id;
    if (pick) selectBranch(pick);
    else {
      const seed = (data.branches || []).find((b) => !b.parent_id);
      if (seed) selectBranch(seed.id);
    }
    saveRunAsChat(data);
  }

  function renderKillCallout(data) {
    const box = $("kill-callout");
    if (!box) return;
    const dead = (data.branches || []).find((b) => b.alive === false && b.kill_reason);
    if (!dead) {
      box.hidden = true;
      return;
    }
    box.hidden = false;
    $("kill-callout-title").textContent = `${dead.id} killed · ${dead.last_action || dead.move || dead.label || "branch"}`;
    $("kill-callout-body").textContent = humanizeDetail(dead.kill_reason);
    box.onclick = () => selectBranch(dead.id);
  }

  // ---- Live run progress (SSE over fetch, so we can still POST a body) ----
  let progressTimer = null;

  function progressReset(expected) {
    const box = $("run-progress");
    if (!box) return;
    box.hidden = false;
    $("progress-feed").innerHTML = "";
    $("progress-fill").style.width = "0%";
    $("progress-fill").classList.remove("waiting");
    $("progress-count").textContent = `0 / ${expected || "?"}`;
    $("progress-now").textContent = "Seeding company state…";
    const t0 = Date.now();
    clearInterval(progressTimer);
    progressTimer = setInterval(() => {
      const s = Math.floor((Date.now() - t0) / 1000);
      $("progress-clock").textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }, 1000);
  }

  function progressStop() {
    clearInterval(progressTimer);
    progressTimer = null;
  }

  function progressFeed(text, cls) {
    const feed = $("progress-feed");
    if (!feed) return;
    const li = document.createElement("li");
    if (cls) li.className = cls;
    li.textContent = text;
    feed.appendChild(li);
    feed.scrollTop = feed.scrollHeight;
  }

  function progressAdvance(done, expected) {
    // Hold short of 100% until the run actually returns.
    const pct = expected ? Math.min(95, Math.round((done / expected) * 100)) : 10;
    $("progress-fill").style.width = `${pct}%`;
    $("progress-count").textContent = `${done} / ${expected}`;
  }

  async function runStreaming(payload, onDone, onError) {
    const res = await fetch("/api/run/stream", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!res.ok || !res.body) throw new Error(`Run failed (${res.status})`);
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = "";
    let expected = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      const frames = buf.split("\n\n");
      buf = frames.pop() || "";
      for (const frame of frames) {
        let name = "", data = "";
        for (const line of frame.split("\n")) {
          if (line.startsWith("event: ")) name = line.slice(7).trim();
          else if (line.startsWith("data: ")) data += line.slice(6);
        }
        if (!name || !data) continue;
        let d;
        try { d = JSON.parse(data); } catch { continue; }
        if (name === "start") {
          expected = d.expected_steps || 0;
          progressReset(expected);
        } else if (name === "step") {
          $("progress-fill").classList.remove("waiting");
          $("progress-now").textContent = d.message;
        } else if (name === "event") {
          expected = d.expected || expected;
          progressAdvance(d.done, expected);
          const killed = /\[KILL\]|KILL —/.test(d.message);
          progressFeed(humanizeDetail(d.message.replace(/\s*\[KILL\]\s*/, " ")), killed ? "kill" : d.kind);
        } else if (name === "wait") {
          $("progress-fill").classList.add("waiting");
          $("progress-now").textContent = d.message;
          progressFeed(d.message, "wait");
        } else if (name === "done") {
          $("progress-fill").style.width = "100%";
          $("progress-now").textContent = "Done.";
          progressStop();
          return onDone(d);
        } else if (name === "error") {
          progressStop();
          return onError(new Error(d.error || "Run failed"));
        }
      }
    }
    progressStop();
    throw new Error("Stream ended before the run finished");
  }

  $("run").addEventListener("click", async () => {
    const btn = $("run");
    btn.disabled = true;
    $("status").textContent = "Forking futures — each move is a live model call.";
    stopPlay();
    try {
      await ensureProfileSynced();
      const payload = {
        fixture_id: state.fixtureId || "custom",
        proposal: withPriorHistory(state.proposal),
        company: state.company || {},
        areas: state.modules || [],
        modules: state.modules || [],
        baseline: $("baseline").checked,
        rounds: Number($("depth").value) || 3,
      };
      await runStreaming(
        payload,
        (data) => {
          bindRun(data);
          $("status").textContent = data.memo?.answer?.do || data.memo?.date_line || "Done.";
          setTimeout(() => { const b = $("run-progress"); if (b) b.hidden = true; }, 1200);
        },
        (err) => { throw err; }
      );
    } catch (err) {
      progressStop();
      const box = $("run-progress");
      if (box) box.hidden = true;
      const msg = String(err.message || err);
      $("status").textContent =
        msg.includes("Failed to fetch") || msg.includes("NetworkError")
          ? "Can't reach the server on :8765 — restart: python3 serve.py"
          : `Error: ${msg}`;
    } finally {
      btn.disabled = false;
    }
  });

  restoreProfile();
  showView("landing");
})();
