# Session + Blue/Red/Brancher/Verifier/Arbiter — survival scoring only

include schema;
include drafts;
include verifiers;
include fixtures;

import json;
import copy;

glob MAX_ROUNDS: int = 5;
glob MAX_BRANCHES: int = 24;

obj Session {
    has fixture_id: str = "";
    has proposal: str = "";
    has title: str = "";
    has domain: str = "";
    has question: str = "";
    has rounds: int = 3;
    has branch_count: int = 0;
    has branches: list = [];
    has edges: list = [];
    has findings: list = [];
    has attacks: list = [];
    has evidence_log: list = [];
    has tool_log: list = [];
    has scorecards: list = [];
    has memo: dict = {};
    has baseline: str = "";
    has events: list = [];
    has company: dict = {};
    has verifier_registry: list = [];
    has areas: list = [];
    has decision: str = "";
}

def new_branch_id(session: Session) -> str {
    session.branch_count += 1;
    return f"b{session.branch_count}";
}

def alive_leaves(session: Session) -> list {
    parents_with_alive_children: set = set();
    id_to_branch: dict = {};
    for b in session.branches {
        id_to_branch[b["id"]] = b;
    }
    for e in session.edges {
        if e.get("type") == "leads_to" {
            child = id_to_branch.get(e["from"], {});
            if child and child.get("alive", True) {
                parents_with_alive_children.add(e["to"]);
            }
        }
    }
    leaves: list = [];
    for b in session.branches {
        if b.get("alive", True) and b["id"] not in parents_with_alive_children {
            leaves.append(b);
        }
    }
    return leaves;
}

def branch_by_id(session: Session, bid: str) -> dict {
    for b in session.branches {
        if b["id"] == bid {
            return b;
        }
    }
    return {};
}

def log_event(session: Session, kind: str, message: str, branch_id: str = "") {
    session.events.append({"kind": kind, "message": message, "branch_id": branch_id});
    print(f"[{kind}] {message}");
}

def log_step(message: str) {
    # Printed BEFORE a blocking model call so the UI can show what is in flight.
    # Deliberately not part of session.events — this is progress, not history.
    print(f"[step] {message}");
}

def state_from_branch(b: dict) -> dict {
    return {
        "cash": float(b.get("cash", 0.0)),
        "monthly_burn": float(b.get("monthly_burn", 0.0)),
        "mrr": float(b.get("mrr", 0.0)),
        "growth_rate": float(b.get("growth_rate", 0.0)),
        "headcount": int(b.get("headcount", 0)),
        "milestone": str(b.get("milestone", "")),
        "milestone_date": str(b.get("milestone_date", "")),
        "milestone_anchor": str(b.get("milestone_anchor", b.get("milestone_date", ""))),
        "as_of": str(b.get("as_of", ""))
    };
}

def write_state_to_branch(b: dict, state: dict, bundle: VerifyBundle, cost_delta: float = 0.0) {
    b["cash"] = float(state["cash"]);
    b["monthly_burn"] = float(state["monthly_burn"]);
    b["mrr"] = float(state["mrr"]);
    b["growth_rate"] = float(state.get("growth_rate", 0.0));
    b["headcount"] = int(state["headcount"]);
    b["milestone"] = str(state["milestone"]);
    b["milestone_date"] = str(state["milestone_date"]);
    b["milestone_anchor"] = str(state.get("milestone_anchor", state["milestone_date"]));
    b["as_of"] = str(state["as_of"]);
    b["cash_out_date"] = bundle.cash_out_date;
    b["runway_months"] = bundle.runway_months;
    b["milestone_hit"] = bundle.milestone_hit;
    b["cost_delta"] = float(b.get("cost_delta", 0.0)) + cost_delta;
    b["alive"] = bundle.ok;
    if not bundle.ok {
        b["kill_reason"] = bundle.kill_reason;
    }
}

def append_evidence(session: Session, branch_id: str, bundle: VerifyBundle) {
    for e in bundle.evidence {
        session.evidence_log.append({
            "branch_id": branch_id,
            "check": e.check,
            "value": e.value,
            "passed": e.passed,
            "module": e.module,
            "detail": e.detail
        });
        session.tool_log.append({
            "branch_id": branch_id,
            "tool": e.check,
            "ok": e.passed,
            "detail": e.detail,
            "metrics": {"value": e.value, "module": e.module}
        });
    }
}

def seed_session(proposal: str, fixture_id: str, rounds: int, company_overrides: dict = {}, areas: list = []) -> Session {
    session = Session(fixture_id=fixture_id, proposal=proposal, rounds=rounds);
    session.areas = normalize_draft_areas(areas) if areas else [];
    if not session.areas { session.areas = ["finance"]; }
    fx = get_fixture(fixture_id) if fixture_id else get_fixture("interlock");
    company = seed_company_state(company_overrides);
    session.company = company;
    if fixture_id == "custom" {
        desk = ", ".join(session.areas) if session.areas else "custom";
        session.title = f"Your decision — {desk} desk";
        session.domain = desk;
    } else {
        session.title = str(fx.get("name", "SplitHorizon"));
        session.domain = str(fx.get("module", "interlock"));
        if not session.areas {
            session.areas = ["management", "launch"];
        }
    }
    session.question = proposal if proposal else str(fx.get("proposal", ""));
    # Agents get the decision as one clean sentence — never the raw DECISION:/desk blob,
    # which they otherwise echo back as a move label.
    session.decision = extract_decision_line(session.question);
    session.verifier_registry = list_verifier_registry();

    seed_state = {
        "cash": float(company["cash"]),
        "monthly_burn": float(company["monthly_burn"]),
        "mrr": float(company["mrr"]),
        "growth_rate": float(company["growth_rate"]),
        "headcount": int(company["headcount"]),
        "milestone": str(company["milestone"]),
        "milestone_date": str(company["milestone_date"]),
        "as_of": str(company["as_of"])
    };
    seed_bundle = verify_state(seed_state);

    root_id = new_branch_id(session);
    seed_branch = {
        "id": root_id,
        "parent_id": "",
        "round": 0,
        "label": f"Seed: {company.get('name', 'Company')}",
        "move": "seed",
        "alive": True,
        "kill_reason": "",
        "summary": (
            f"Cash ${company['cash']:,.0f} · burn ${company['monthly_burn']:,.0f}/mo · "
            + f"MRR ${company['mrr']:,.0f} · hc {company['headcount']} · "
            + f"ms {company['milestone_date']} · cash-out {pretty_date(seed_bundle.cash_out_date)}"
        ),
        "side_created": "seed",
        "last_action": "",
        "last_stressor": "",
        "cost_delta": 0.0,
        "cash": seed_state["cash"],
        "monthly_burn": seed_state["monthly_burn"],
        "mrr": seed_state["mrr"],
        "growth_rate": seed_state["growth_rate"],
        "headcount": seed_state["headcount"],
        "milestone": seed_state["milestone"],
        "milestone_date": seed_state["milestone_date"],
        "milestone_anchor": seed_state["milestone_date"],
        "as_of": seed_state["as_of"],
        "cash_out_date": seed_bundle.cash_out_date,
        "runway_months": seed_bundle.runway_months,
        "milestone_hit": seed_bundle.milestone_hit
    };
    session.branches.append(seed_branch);
    log_event(
        session, "seed",
        f"Loaded {company.get('name')} — cash-out {pretty_date(seed_bundle.cash_out_date)}, milestone {pretty_date(seed_state['milestone_date'])}",
        root_id
    );

    bnode = root ++> Branch(
        branch_id=root_id, parent_id="", round_no=0, label=seed_branch["label"], move="seed",
        alive=True, summary=seed_branch["summary"], side_created="seed",
        cash=float(seed_state["cash"]), monthly_burn=float(seed_state["monthly_burn"]),
        mrr=float(seed_state["mrr"]), growth_rate=float(seed_state["growth_rate"]),
        headcount=int(seed_state["headcount"]), milestone=str(seed_state["milestone"]),
        milestone_date=str(seed_state["milestone_date"]), as_of=str(seed_state["as_of"]),
        cash_out_date=seed_bundle.cash_out_date, runway_months=seed_bundle.runway_months,
        milestone_hit=seed_bundle.milestone_hit
    );
    root ++> CompanyState(
        cash=float(seed_state["cash"]), monthly_burn=float(seed_state["monthly_burn"]),
        mrr=float(seed_state["mrr"]), growth_rate=float(seed_state["growth_rate"]),
        headcount=int(seed_state["headcount"]), milestone=str(seed_state["milestone"]),
        milestone_date=str(seed_state["milestone_date"]), as_of=str(seed_state["as_of"])
    );
    root ++> Tool(name="VerifyState", schema_desc="runway/hire/launch arithmetic");
    root ++> Tool(name="CashOutDate", schema_desc="deterministic cash-out date");
    bnode;
    return session;
}

def fork_branch(session: Session, parent: dict, label: str, side: str, round_no: int, move: str) -> dict {
    child_id = new_branch_id(session);
    child = copy.deepcopy(parent);
    child["id"] = child_id;
    child["parent_id"] = parent["id"];
    child["round"] = round_no;
    child["label"] = label;
    child["side_created"] = side;
    child["move"] = move;
    child["kill_reason"] = "";
    child["alive"] = True;
    session.branches.append(child);
    session.edges.append({"type": "leads_to", "from": child_id, "to": parent["id"], "via": side});
    session.edges.append({"type": "derives_from", "from": child_id, "to": parent["id"], "via": move});
    return child;
}

def osp_put_branch(b: dict) {
    # Materialize every future as a real Jac Branch node (OSP, not JSON-only).
    root ++> Branch(
        branch_id=str(b.get("id", "")),
        parent_id=str(b.get("parent_id", "")),
        round_no=int(b.get("round", 0)),
        label=str(b.get("label", "")),
        move=str(b.get("move", "")),
        alive=bool(b.get("alive", True)),
        kill_reason=str(b.get("kill_reason", "")),
        summary=str(b.get("summary", "")),
        side_created=str(b.get("side_created", "blue")),
        cash=float(b.get("cash", 0.0)),
        monthly_burn=float(b.get("monthly_burn", 0.0)),
        mrr=float(b.get("mrr", 0.0)),
        growth_rate=float(b.get("growth_rate", 0.0)),
        headcount=int(b.get("headcount", 0)),
        milestone=str(b.get("milestone", "")),
        milestone_date=str(b.get("milestone_date", "")),
        as_of=str(b.get("as_of", "")),
        cash_out_date=str(b.get("cash_out_date", "")),
        runway_months=float(b.get("runway_months", 0.0)),
        milestone_hit=bool(b.get("milestone_hit", False))
    );
}

def osp_put_attack(a: dict) {
    root ++> Attack(
        attack_id=str(a.get("id", "")),
        claim=str(a.get("claim", "")),
        severity=str(a.get("severity", "medium")),
        check_hint=str(a.get("check_hint", "alive_at_milestone")),
        round_no=int(a.get("round", 0))
    );
}

def osp_put_evidence(branch_id: str, bundle: VerifyBundle) {
    i = 0;
    for e in bundle.evidence {
        i += 1;
        root ++> Evidence(
            evidence_id=f"{branch_id}-e{i}",
            check=e.check,
            value=e.value,
            passed=e.passed,
            module=e.module
        );
    }
}

def osp_put_memo(memo: dict) {
    root ++> Memo(
        recommended_branch_id=str(memo.get("recommended_branch_id", "")),
        title=str(memo.get("title", "")),
        prose=str(memo.get("prose", "")),
        kill_shots=str(memo.get("kill_shots", "")),
        open_risks=str(memo.get("open_risks", "")),
        dissent=str(memo.get("dissent", "")),
        date_line=str(memo.get("date_line", ""))
    );
}

def prune_if_needed(session: Session) {
    if len(session.branches) <= MAX_BRANCHES {
        return;
    }
    scored: list = [];
    for b in session.branches {
        if b.get("alive", True) {
            scored.append({"rank": float(b.get("runway_months", 0.0)), "id": b["id"]});
        }
    }
    scored.sort(key=lambda (s: dict) -> float { return s["rank"]; });
    alive_n = 0;
    for b in session.branches {
        if b.get("alive", True) {
            alive_n += 1;
        }
    }
    while alive_n > MAX_BRANCHES and scored {
        item = scored.pop(0);
        b = branch_by_id(session, item["id"]);
        if b and b.get("alive", True) and b.get("side_created") != "seed" {
            b["alive"] = False;
            b["kill_reason"] = "pruned: branch cap";
            log_event(session, "prune", f"Pruned {item['id']}", item["id"]);
            alive_n -= 1;
        }
    }
}

def desk_for_round(session: Session, round_no: int, offset: int = 0) -> str {
    if not session.areas { return "finance"; }
    idx = (round_no - 1 + offset) % len(session.areas);
    return str(session.areas[idx]);
}

def blue_turn(session: Session, parent: dict, round_no: int) -> dict {
    tried: list = [];
    for f in session.findings {
        if f.get("side") == "blue" {
            tried.append(str(f.get("label", f.get("claim", "")))[:60]);
        }
    }
    desk = desk_for_round(session, round_no, len(tried));
    log_step(f"Blue is drafting a {desk} move off {parent['id']} (round {round_no})");
    draft = blue_propose(session.decision, session.company, desk, tried, round_no);
    if draft.desk {
        cleaned = normalize_draft_areas([draft.desk]);
        if cleaned { desk = cleaned[0]; }
    }
    label = str(draft.label).strip() if draft.label else "Unnamed move";
    child = fork_branch(session, parent, f"R{round_no} {desk}: {label[:36]}", "blue", round_no, "custom");
    child["last_action"] = label;
    child["desk"] = desk;
    child["claim"] = draft.claim;
    child["summary"] = f"{desk} Blue: {draft.claim} [{label}]";

    # The $30k/mo hire burn-step check only applies to hiring moves — a deliberate
    # spend (ads, gear) is judged by alive_at_milestone instead.
    prior_burn = float(parent.get("monthly_burn", 0.0)) if draft.headcount_delta != 0 else -1.0;
    applied = apply_move_draft(
        state_from_branch(parent),
        draft.burn_delta_pct, draft.mrr_delta_pct,
        draft.headcount_delta, draft.milestone_shift_days, label,
        draft.cash_spend_usd, 0.0
    );
    new_state = applied["state"];
    cost_delta = float(applied["cost_delta"]);
    bundle = verify_state(new_state, prior_burn);
    write_state_to_branch(child, new_state, bundle, cost_delta);
    append_evidence(session, child["id"], bundle);

    session.findings.append({
        "id": f"f{len(session.findings)+1}",
        "side": "blue",
        "claim": draft.claim or label,
        "label": label,
        "desk": desk,
        "branch_id": child["id"],
        "evidence": bundle.kill_reason or f"cash-out {pretty_date(bundle.cash_out_date)}"
    });
    if not child.get("alive", True) {
        log_event(session, "blue", f"{child['id']}: {label} [KILL] {child.get('kill_reason', '')}", child["id"]);
    } else {
        log_event(session, "blue", f"{child['id']}: {label} → cash-out {pretty_date(bundle.cash_out_date)}", child["id"]);
    }
    osp_put_branch(child);
    osp_put_evidence(child["id"], bundle);
    return child;
}

def red_turn(session: Session, parent: dict, round_no: int) -> dict {
    desk = str(parent.get("desk", ""));
    if not desk {
        desk = desk_for_round(session, round_no);
    }
    log_step(f"Red is attacking {parent['id']} — {str(parent.get('last_action', ''))[:40]}");
    draft = red_attack(
        session.decision, session.company,
        str(parent.get("last_action", "")), str(parent.get("claim", parent.get("summary", ""))),
        desk
    );
    child = fork_branch(session, parent, f"R{round_no} {desk} Red: {draft.claim[:32]}", "red", round_no, "stress");
    child["last_stressor"] = draft.claim;
    child["desk"] = desk;
    child["summary"] = f"{desk} Red: {draft.claim}";

    session.attacks.append({
        "id": f"a{len(session.attacks)+1}",
        "claim": draft.claim,
        "severity": draft.severity,
        "check_hint": "alive_at_milestone",
        "desk": desk,
        "branch_id": child["id"],
        "round": round_no
    });
    session.edges.append({"type": "attacks", "from": child["id"], "to": parent["id"], "via": "stress"});

    # Red stress is adversity, not a hiring decision — never trip the hire burn-step check.
    prior_burn = -1.0;
    stressed = apply_stress_draft(
        state_from_branch(parent),
        draft.burn_delta_pct, draft.mrr_delta_pct, draft.milestone_shift_days
    );
    bundle = verify_state(stressed, prior_burn);
    write_state_to_branch(child, stressed, bundle, 0.0);
    append_evidence(session, child["id"], bundle);
    session.edges.append({"type": "verified_by", "from": child["id"], "to": "VerifyState", "via": "alive_at_milestone"});

    killed = not child.get("alive", True);
    session.findings.append({
        "id": f"f{len(session.findings)+1}",
        "side": "red",
        "claim": draft.claim,
        "branch_id": child["id"],
        "evidence": child.get("kill_reason") or f"cash-out {pretty_date(bundle.cash_out_date)}",
        "kill": killed
    });
    msg = f"{child['id']}: {draft.claim}";
    if killed {
        msg = msg + " [KILL]";
    } else {
        msg = msg + f" → cash-out {pretty_date(bundle.cash_out_date)}";
    }
    log_event(session, "red", msg, child["id"]);
    osp_put_branch(child);
    osp_put_attack(session.attacks[-1]);
    osp_put_evidence(child["id"], bundle);
    return child;
}

def score_branch(session: Session, b: dict) {
    if not b.get("alive", True) {
        rank = -1.0;
    } else {
        hit_bonus = 2.0 if b.get("milestone_hit") else 0.0;
        rank = float(b.get("runway_months", 0.0)) + hit_bonus;
        if b.get("side_created") == "blue" {
            rank += 0.05;
        }
    }
    unmitigated = 0;
    for a in session.attacks {
        if a.get("branch_id") == b["id"] {
            unmitigated += 1;
        }
    }
    failed_ev = 0;
    for e in session.evidence_log {
        if e.get("branch_id") == b["id"] and not e.get("passed", True) {
            failed_ev += 1;
        }
    }
    card = {
        "branch_id": b["id"],
        "action": str(b.get("last_action", "") or b.get("last_stressor", "") or b.get("label", ""))[:48],
        "runway_months": b.get("runway_months", 0.0),
        "cash_out_date": b.get("cash_out_date", ""),
        "milestone_hit": b.get("milestone_hit", False),
        "milestone_date": b.get("milestone_date", ""),
        "cost_delta": b.get("cost_delta", 0.0),
        "unmitigated_attacks": unmitigated,
        "failed_checks": failed_ev,
        "rank_score": rank,
        "alive": b.get("alive", True),
        "label": b.get("label", ""),
        "narrative": b.get("summary", "")
    };
    kept: list = [];
    for s in session.scorecards {
        if s["branch_id"] != b["id"] {
            kept.append(s);
        }
    }
    session.scorecards = kept;
    session.scorecards.append(card);
}

def score_all(session: Session) {
    for b in session.branches {
        score_branch(session, b);
    }
}

def extract_decision_line(text: str) -> str {
    raw = str(text or "").strip();
    for line in raw.split("\n") {
        t = line.strip();
        low = t.lower();
        if low.startswith("decision:") {
            return t[9:].strip() if len(t) > 9 else t;
        }
    }
    # First non-empty non-meta line
    for line in raw.split("\n") {
        t = line.strip();
        if not t { continue; }
        low = t.lower();
        if low.startswith("consult desks:") or low.startswith("business:") or low.startswith("milestone:") {
            continue;
        }
        if low.startswith("management move:") or low.startswith("launch move:") or low.startswith("finance move:") or low.startswith("publicity move:") {
            continue;
        }
        if low.startswith("plan specifics:") or low.startswith("tempted") {
            continue;
        }
        return t[:220];
    }
    return raw[:220] if raw else "your stated plan";
}

def primary_desk(session: Session, best: dict) -> str {
    d = str(best.get("desk", "")) if best else "";
    if d { return d; }
    if session.areas {
        return str(session.areas[0]);
    }
    return "finance";
}

def format_cash_out(best: dict) -> str {
    if not best { return "—"; }
    rw = float(best.get("runway_months", 0.0));
    if rw >= 900.0 {
        return "cash-flow positive (MRR covers burn)";
    }
    return pretty_date(str(best.get("cash_out_date", "")));
}

def format_runway(best: dict) -> str {
    if not best { return "—"; }
    rw = float(best.get("runway_months", 0.0));
    if rw >= 900.0 {
        return "cash-flow positive";
    }
    return f"{rw:.1f} months";
}

def branch_facts_line(session: Session, b: dict, tag: str) -> str {
    # One verified branch, rendered for the arbiter. Every figure here came from verifiers.jac.
    rw = float(b.get("runway_months", 0.0));
    runway = "cash-flow positive" if rw >= 900.0 else f"{rw:.1f} mo runway";
    co = "no cash-out while MRR covers burn" if rw >= 900.0 else f"cash-out {pretty_date(str(b.get('cash_out_date', '')))}";
    # Margin is computed here so the arbiter never has to do arithmetic of its own.
    margin = "";
    bc = str(b.get("cash_out_date", ""));
    bm = str(b.get("milestone_date", ""));
    if bc and bm and rw < 900.0 {
        gap = days_between(bm, bc);
        margin = f" · margin {gap} days ({'milestone clears' if gap >= 0 else 'cash dies first'})";
    }
    line = (
        f"  [{b['id']}] {tag} · desk={str(b.get('desk', 'n/a'))} · move=\"{str(b.get('last_action', b.get('label', '')))}\""
        + f" · {co} · milestone {pretty_date(str(b.get('milestone_date', '')))}{margin}"
        + f" · {runway} · burn ${float(b.get('monthly_burn', 0.0)):,.0f}/mo"
        + f" · MRR ${float(b.get('mrr', 0.0)):,.0f}/mo · headcount {int(b.get('headcount', 0))}"
    );
    if b.get("kill_reason") {
        line = line + f" · KILLED: {str(b.get('kill_reason'))}";
    }
    if b.get("last_stressor") and str(b.get("side_created")) == "red" {
        line = line + f" · red pressure: {str(b.get('last_stressor'))[:140]}";
    }
    return line;
}

def build_facts(session: Session, best_id: str, best_full: dict, survivors: list, dead: list, margin_days: int) -> str {
    # The ONLY numbers the arbiter is allowed to cite. Assembled from verified branch state.
    parts: list = [];
    c = session.company;
    parts.append(f"COMPANY: {c.get('name', 'the company')} · cash ${float(c.get('cash', 0.0)):,.0f} · burn ${float(c.get('monthly_burn', 0.0)):,.0f}/mo · MRR ${float(c.get('mrr', 0.0)):,.0f}/mo · headcount {int(c.get('headcount', 0))}");
    parts.append(f"MILESTONE: {c.get('milestone', 'milestone')} on {pretty_date(str(c.get('milestone_date', '')))}");
    parts.append(f"DESKS CONSULTED: {', '.join(session.areas)}");
    parts.append("");

    if best_full {
        parts.append(f"RECOMMENDED BRANCH: {best_id}");
        parts.append(branch_facts_line(session, best_full, "RECOMMENDED"));
        if bool(best_full.get("milestone_hit", False)) {
            if margin_days > 0 {
                parts.append(f"  -> milestone LANDS before cash-out, margin {margin_days} days");
            } else {
                parts.append("  -> milestone lands, but margin is thin");
            }
        } else {
            parts.append("  -> milestone does NOT clear cash-out on this line; least-bad survivor only");
        }
    } else {
        parts.append("RECOMMENDED BRANCH: none — every branch failed hard arithmetic");
    }
    parts.append("");

    parts.append(f"SURVIVING BRANCHES ({len(survivors)}):");
    if survivors {
        for s in survivors[:6] {
            b = branch_by_id(session, str(s.get("branch_id", "")));
            if b {
                parts.append(branch_facts_line(session, b, "survivor"));
            }
        }
    } else {
        parts.append("  none");
    }
    parts.append("");

    parts.append(f"KILLED BRANCHES ({len(dead)}):");
    if dead {
        for d in dead[:6] {
            parts.append(branch_facts_line(session, d, "killed"));
        }
    } else {
        parts.append("  none — nothing failed a hard check this run");
    }
    parts.append("");

    parts.append("BLUE PROPOSED:");
    for f in session.findings {
        if str(f.get("side", "")) == "blue" {
            parts.append(f"  [{f.get('branch_id')}] \"{str(f.get('label', ''))}\" — {str(f.get('claim', ''))[:160]}");
        }
    }
    parts.append("");
    parts.append("RED ATTACKED:");
    for a in session.attacks {
        parts.append(f"  [{a.get('branch_id')}] ({a.get('severity', 'medium')}) {str(a.get('claim', ''))[:180]}");
    }
    parts.append("");
    parts.append("FAILED CHECKS (deterministic verifiers):");
    seen = 0;
    for e in session.evidence_log {
        if not e.get("passed", True) and seen < 8 {
            seen += 1;
            parts.append(f"  [{e.get('branch_id')}] {e.get('check')} = {e.get('value')} — {str(e.get('detail', ''))[:150]}");
        }
    }
    if seen == 0 {
        parts.append("  none");
    }
    return "\n".join(parts);
}

def build_answer(session: Session, best_id: str, best_full: dict, survivors: list, dead: list, margin_days: int) -> dict {
    decision = session.decision if session.decision else extract_decision_line(session.question);
    facts = build_facts(session, best_id, best_full, survivors, dead, margin_days);
    log_step("Arbiter is writing the verdict from verified dates");
    ans = decide(decision, session.company, facts);

    desk = primary_desk(session, best_full);
    move = str(best_full.get("last_action", best_full.get("label", ""))) if best_full else "";
    cash_out = format_cash_out(best_full);
    runway = format_runway(best_full);
    ms_name = str(best_full.get("milestone", session.company.get("milestone", "milestone"))) if best_full else str(session.company.get("milestone", "milestone"));
    ms_date = pretty_date(str(best_full.get("milestone_date", ""))) if best_full else "—";

    steps: list = [];
    for s in ans.steps {
        if str(s.title).strip() {
            steps.append({"when": str(s.when), "title": str(s.title), "detail": str(s.detail)});
        }
    }

    # Dates are never model output — they are restated here straight from the verifier.
    answer = {
        "one_liner": f"{ans.headline} {ans.because}".strip(),
        "do": str(ans.headline),
        "dont": str(ans.dont) if str(ans.dont).strip() else "No alternative was killed this run — compare the tree.",
        "because": str(ans.because),
        "dates": f"Recommended: {cash_out} · Milestone: {ms_name} on {ms_date} · Runway: {runway}",
        "decision": decision,
        "move": move,
        "desk": desk,
        "blue": " · ".join([f"{str(f.get('label', ''))}: {str(f.get('evidence', ''))[:70]}" for f in session.findings if str(f.get("side", "")) == "blue"][:3]),
        "red": " · ".join([str(a.get("claim", ""))[:110] for a in session.attacks][:3]),
        "detail": str(ans.analysis),
        "survivors": len(survivors),
        "kills": len(dead),
        "margin_days": margin_days,
        "milestone_hit": bool(best_full.get("milestone_hit", False)) if best_full else False
    };

    kill_bits: list = [];
    for d in dead[:3] {
        if d.get("kill_reason") {
            kill_bits.append(f"{str(d.get('last_action', d['id']))[:40]}: {str(d.get('kill_reason'))[:110]}");
        }
    }

    return {
        "title": str(ans.title) if str(ans.title).strip() else f"Verdict: {move}",
        "prose": str(ans.headline) + (" " + str(ans.because) if ans.because else ""),
        "analysis": str(ans.analysis),
        "watch_for": str(ans.watch_for),
        "action_plan": steps,
        "kill_shots": "; ".join(kill_bits) if kill_bits else "No branch failed a hard check this run.",
        "open_risks": f"Unmitigated Red pressure on the recommended line; re-run if spend or dates change. Desk={desk}.",
        "answer": answer
    };
}

def arbiter(session: Session) {
    score_all(session);
    leaves = alive_leaves(session);
    leaf_ids: set = set();
    for b in leaves {
        leaf_ids.add(b["id"]);
    }
    alive_cards: list = [];
    for s in session.scorecards {
        if s.get("alive", True) and s["branch_id"] in leaf_ids {
            alive_cards.append(s);
        }
    }
    if not alive_cards {
        for s in session.scorecards {
            if s.get("alive", True) {
                alive_cards.append(s);
            }
        }
    }
    alive_cards.sort(key=lambda (s: dict) -> float { return s["rank_score"]; }, reverse=True);

    best_id = "none";
    if alive_cards {
        best_id = alive_cards[0]["branch_id"];
        best_branch = branch_by_id(session, best_id);
        if best_branch.get("side_created") == "red" {
            parent = branch_by_id(session, str(best_branch.get("parent_id", "")));
            killed_here = False;
            for f in session.findings {
                if f.get("branch_id") == best_id and f.get("kill") {
                    killed_here = True;
                }
            }
            if parent and parent.get("alive", True) and parent.get("side_created") == "blue" and not killed_here {
                best_id = parent["id"];
            }
        }
    }

    best_full = branch_by_id(session, best_id) if best_id != "none" else {};
    survivors: list = [];
    for s in alive_cards {
        survivors.append(s);
    }

    # Date line always matches the RECOMMENDED branch (not a random survivor foil).
    date_line = "";
    if best_full {
        move_l = str(best_full.get("last_action", best_full.get("label", "recommended")));
        co = format_cash_out(best_full);
        ms = pretty_date(str(best_full.get("milestone_date", "")));
        dead_foil = "";
        for br in session.branches {
            if not br.get("alive", True) and br.get("kill_reason") {
                dead_foil = (
                    f"Killed alternative «{str(br.get('last_action', br.get('label', br['id'])))[:36]}» "
                    + f"runs out {pretty_date(str(br.get('cash_out_date', '')))}."
                );
                break;
            }
        }
        date_line = f"Recommended «{move_l}»: {co} vs milestone {ms}. " + (dead_foil if dead_foil else "");
    } else {
        date_line = "No surviving plans — every branch failed hard arithmetic.";
    }

    kills: list = [];
    for f in session.findings {
        if f.get("side") == "red" and f.get("kill") {
            kills.append(f);
        }
    }
    kill_claims: list = [];
    for f in kills {
        kill_claims.append(str(f.get("claim", "")));
    }
    kill_txt = "; ".join(kill_claims) if kill_claims else "No hard kill shots on the recommended line.";

    dead: list = [];
    for b in session.branches {
        if not b.get("alive", True) {
            dead.append(b);
        }
    }
    dissent = "Competing forks lost on cash-out vs milestone.";
    if dead {
        bits: list = [];
        for d in dead[:4] {
            bits.append(d["id"] + " cash-out " + pretty_date(str(d.get("cash_out_date", ""))));
        }
        dissent = dissent + " | Dead: " + ", ".join(bits);
    }

    decomp = {
        "survival_months": best_full.get("runway_months", 0.0) if best_full else 0.0,
        "milestone_hit": best_full.get("milestone_hit", False) if best_full else False,
        "cash_out_date": best_full.get("cash_out_date", "") if best_full else "",
        "milestone_date": best_full.get("milestone_date", "") if best_full else "",
        "cost_delta": best_full.get("cost_delta", 0.0) if best_full else 0.0,
        "unmitigated_attacks": 0,
        "failed_checks": 0
    };
    for s in session.scorecards {
        if s["branch_id"] == best_id {
            decomp["unmitigated_attacks"] = s.get("unmitigated_attacks", 0);
            decomp["failed_checks"] = s.get("failed_checks", 0);
        }
    }

    margin_days = 0;
    if best_full {
        bc = str(best_full.get("cash_out_date", ""));
        bm = str(best_full.get("milestone_date", ""));
        if bc and bm {
            margin_days = days_between(bm, bc);
        }
    }

    # ---- The arbiter writes the answer from verified facts (drafts.decide) ----
    intel = build_answer(session, best_id, best_full, survivors, dead, margin_days);

    session.memo = {
        "recommended_branch_id": best_id,
        "title": intel["title"],
        "prose": intel["prose"],
        "kill_shots": kill_txt if (kill_txt and "No hard kill" not in kill_txt) else intel["kill_shots"],
        "open_risks": intel["open_risks"],
        "dissent": dissent,
        "date_line": date_line,
        "decomposition": decomp,
        "analysis": intel["analysis"],
        "watch_for": intel["watch_for"],
        "action_plan": intel["action_plan"],
        "baseline_foil": session.baseline,
        "decision": extract_decision_line(session.proposal if session.proposal else session.question),
        "desk": primary_desk(session, best_full),
        "answer": intel.get("answer", {})
    };
    log_event(session, "arbiter", f"Recommended {best_id}: {date_line}", best_id);
    osp_put_memo(session.memo);
}

def run_protocol(proposal: str, fixture_id: str = "interlock", rounds: int = 3, run_baseline: bool = True, company_overrides: dict = {}, areas: list = []) -> dict {
    session = seed_session(proposal, fixture_id, rounds, company_overrides, areas);
    if run_baseline {
        log_step("Generating the chatbot foil");
        session.baseline = baseline_plan(proposal if proposal else session.question);
    }
    n = min(rounds, MAX_ROUNDS);
    for r in range(1, n + 1) {
        leaves = alive_leaves(session);
        if not leaves {
            log_event(session, "halt", "No alive leaves — stopping early");
            break;
        }
        blue_children: list = [];
        # Every draft is a live model call against a per-minute token budget, so the tree
        # stays narrow: two rival strategies off the seed, then one child per live leaf.
        # Fewer, better-argued branches also make the tree readable.
        n_forks = 2 if r == 1 else 1;
        leaf_cap = 2;
        for leaf in leaves[:leaf_cap] {
            for _ in range(n_forks) {
                blue_children.append(blue_turn(session, leaf, r));
                prune_if_needed(session);
            }
        }
        red_parents: list = [];
        for c in blue_children {
            if c.get("alive", True) {
                red_parents.append(c);
            }
        }
        if not red_parents {
            red_parents = blue_children[:1];
        }
        red_cap = 2;
        for bp in red_parents[:red_cap] {
            red_turn(session, bp, r);
            prune_if_needed(session);
        }
        score_all(session);
    }
    arbiter(session);
    return session_to_dict(session);
}

def session_to_dict(session: Session) -> dict {
    return {
        "fixture_id": session.fixture_id,
        "proposal": session.proposal,
        "question": session.question,
        "title": session.title,
        "domain": session.domain,
        "areas": session.areas,
        "modules": session.areas,
        "company": session.company,
        "branches": session.branches,
        "edges": session.edges,
        "findings": session.findings,
        "attacks": session.attacks,
        "evidence_log": session.evidence_log,
        "tool_log": session.tool_log,
        "scorecards": session.scorecards,
        "memo": session.memo,
        "baseline": session.baseline,
        "events": session.events,
        "verifier_registry": session.verifier_registry
    };
}
