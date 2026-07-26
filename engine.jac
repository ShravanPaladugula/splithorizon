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

def state_from_branch(b: dict) -> dict {
    return {
        "cash": float(b.get("cash", 0.0)),
        "monthly_burn": float(b.get("monthly_burn", 0.0)),
        "mrr": float(b.get("mrr", 0.0)),
        "growth_rate": float(b.get("growth_rate", 0.0)),
        "headcount": int(b.get("headcount", 0)),
        "milestone": str(b.get("milestone", "")),
        "milestone_date": str(b.get("milestone_date", "")),
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
    session.areas = areas if areas else [];
    # Capex / buy plans always include finance desk arithmetic even if UI only toggled management.
    if is_equipment_plan(proposal) {
        cleaned = normalize_draft_areas(session.areas);
        if "finance" not in cleaned {
            cleaned = ["finance"] + cleaned;
        }
        session.areas = cleaned if cleaned else ["finance"];
    }
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

def blue_turn(session: Session, parent: dict, round_no: int) -> dict {
    prior_parts: list = [];
    for a in session.attacks {
        prior_parts.append(str(a.get("claim", "")));
    }
    moves_seen: list = [];
    for f in session.findings {
        if f.get("side") == "blue" {
            moves_seen.append(str(f.get("claim", ""))[:60]);
        }
    }
    prior = "; ".join(prior_parts[-3:]);
    if moves_seen {
        prior = prior + " || Moves ALREADY on the tree (propose something DIFFERENT): " + "; ".join(moves_seen[-5:]);
    }
    draft = blue_propose(parent.get("summary", ""), session.question, prior, session.fixture_id, round_no, len(moves_seen), session.areas);
    tag = draft.effect_tag if draft.effect_tag else draft.move;
    is_custom = bool(draft.label) and (tag == "custom" or tag not in EFFECT_CATALOG);
    label = draft.label if is_custom else effect_label(tag);
    desk = str(draft.module) if draft.module else "blue";
    child = fork_branch(session, parent, f"R{round_no} {desk}: {label[:36]}", "blue", round_no, tag);
    child["last_action"] = label;
    child["desk"] = desk;
    child["summary"] = f"{desk} Blue: {draft.claim} [{label if is_custom else tag}]";

    prior_burn = float(parent.get("monthly_burn", 0.0));
    if is_custom and draft.headcount_delta == 0 {
        # The $30k/mo hire burn-step check only applies to hiring moves —
        # a deliberate spend (ads, infra) is judged by alive_at_milestone instead.
        prior_burn = -1.0;
    }
    if is_custom {
        cash_spend = 0.0;
        burn_add = 0.0;
        ll = label.lower();
        plan_cash = float(session.company.get("plan_cash", 0.0)) if session.company else 0.0;
        plan_burn = float(session.company.get("plan_burn_delta", 0.0)) if session.company else 0.0;
        if plan_cash <= 0.0 { plan_cash = 2000.0; }
        if ("buy both" in ll) or ("buy the full" in ll) {
            cash_spend = plan_cash;
            burn_add = plan_burn;
        } elif ("buy one" in ll) {
            cash_spend = plan_cash * 0.5;
            burn_add = plan_burn * 0.5;
        } elif ("lease" in ll) {
            cash_spend = plan_cash * 0.15;
            burn_add = max(plan_burn, plan_cash * 0.04);
        }
        applied = apply_move_draft(
            state_from_branch(parent),
            draft.burn_delta_pct, draft.mrr_delta_pct,
            draft.headcount_delta, draft.milestone_shift_days, label,
            cash_spend, burn_add
        );
    } else {
        applied = apply_effect(state_from_branch(parent), tag);
    }
    new_state = applied["state"];
    cost_delta = float(applied["cost_delta"]);
    bundle = verify_state(new_state, prior_burn);
    write_state_to_branch(child, new_state, bundle, cost_delta);
    append_evidence(session, child["id"], bundle);

    session.findings.append({
        "id": f"f{len(session.findings)+1}",
        "side": "blue",
        "claim": draft.claim or label,
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
    draft = red_attack(session.question, parent.get("summary", ""), parent.get("move", ""), session.fixture_id, round_no, session.areas);
    desk = str(parent.get("desk", ""));
    if not desk {
        desk = str(session.areas[0]) if session.areas else "red";
    }
    child = fork_branch(session, parent, f"R{round_no} {desk} Red: {draft.claim[:32]}", "red", round_no, draft.stress_tag);
    child["last_stressor"] = draft.claim;
    child["desk"] = desk;
    child["summary"] = f"{desk} Red: {draft.claim} [{draft.stress_tag}]";

    session.attacks.append({
        "id": f"a{len(session.attacks)+1}",
        "claim": draft.claim,
        "severity": draft.severity,
        "check_hint": draft.check_hint,
        "stress_tag": draft.stress_tag,
        "branch_id": child["id"],
        "round": round_no
    });
    session.edges.append({"type": "attacks", "from": child["id"], "to": parent["id"], "via": draft.stress_tag});

    # Red stress is adversity, not a hiring decision — never trip the hire burn-step check.
    prior_burn = -1.0;
    is_custom_attack = draft.stress_tag == "custom" or draft.stress_tag not in STRESS_CATALOG;
    if is_custom_attack and (draft.burn_delta_pct != 0.0 or draft.mrr_delta_pct != 0.0 or draft.milestone_shift_days != 0) {
        stressed = apply_stress_draft(state_from_branch(parent), draft.burn_delta_pct, draft.mrr_delta_pct, draft.milestone_shift_days);
    } else {
        stressed = apply_stress(state_from_branch(parent), draft.stress_tag);
    }
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

def desk_playbook_steps(desk: str, move_label: str, question: str, best: dict, company: dict) -> list {
    # Concrete "how to execute" steps — not just "Execute: label".
    cash_out = pretty_date(str(best.get("cash_out_date", "")));
    ms = pretty_date(str(best.get("milestone_date", "")));
    ms_name = str(best.get("milestone", company.get("milestone", "milestone")));
    burn = float(best.get("monthly_burn", company.get("monthly_burn", 0.0)));
    mrr = float(best.get("mrr", company.get("mrr", 0.0)));
    label = str(move_label or "the recommended move");
    low = (str(question) + " " + label).lower();
    steps: list = [];

    if desk == "publicity" or ("ad" in low) or ("campaign" in low) or ("influencer" in low) {
        pilot = ("pilot" in low) or ("organic" in low) or ("smaller" in low);
        if pilot {
            steps.append({"when": "This week", "title": "Cap paid spend to a pilot, not the full ask", "detail": f"Fund {label} only. Write the weekly budget on one line and freeze anything above it until CAC is proven."});
            steps.append({"when": "Day 14", "title": "Kill / scale gate on CAC + payback", "detail": f"If paid acquisition is not on a path to pay back before {ms} ({ms_name}), kill the campaign — do not 'give it one more month'."});
        } else {
            steps.append({"when": "This week", "title": "Commit the full acquisition budget in one motion", "detail": f"Execute {label}. Lock channel mix and creative before spend starts so burn does not creep."});
            steps.append({"when": "Weekly", "title": "Track signup → paid conversion vs burn", "detail": f"Cash-out on this line is {cash_out}. If weekly net burn stays near ${burn:,.0f} without MRR lift, cut channel spend immediately."});
        }
        steps.append({"when": "Ongoing", "title": "Protect the milestone narrative publicly", "detail": f"{ms_name} on {ms} is the deadline the campaign must serve — marketing that does not move that date is noise."});
    } elif ("buy" in low) or ("printer" in low) or ("equipment" in low) or ("purchase" in low) or ("lease" in low) or ("capex" in low) {
        if ("do not buy" in low) or ("wait" in low) {
            steps.append({"when": "This week", "title": "Do not buy — max current capacity", "detail": f"Execute {label}. Queue jobs, raise utilization, and write the utilization proof that would unlock a later purchase."});
            steps.append({"when": "Day 30", "title": "Re-run buy decision with utilization data", "detail": f"Only reopen the purchase if jobs are spilling and {ms_name} still clears before cash-out {cash_out}."});
        } elif ("one" in low) or ("lease" in low) {
            steps.append({"when": "This week", "title": f"Execute: {label}", "detail": f"Cap cash outlay; do not buy the full set yet. Tie the purchase to a named capacity unlock before {ms}."});
            steps.append({"when": "Day 30", "title": "Utilization gate before second unit", "detail": "If the first unit is idle >30% of available hours, stop — do not buy #2."});
        } else {
            steps.append({"when": "This week", "title": f"Buy the gear: {label}", "detail": f"Pay from cash, book install date, and assign who fills the new capacity. Cash-out on this line: {cash_out}."});
            steps.append({"when": "Day 21", "title": "Capacity → revenue check", "detail": f"New printers must pull jobs that move {ms_name} ({ms}). Idle gear is just a cash hole."});
        }
        steps.append({"when": ms, "title": f"Capacity vs {ms_name}", "detail": f"Gear only wins if {ms_name} still lands while cash-out stays at {cash_out}."});
    } elif desk == "management" or ("hire" in low) or ("engineer" in low) or ("infra" in low) or ("fire" in low) or ("layoff" in low) {
        if ("fire" in low) or ("layoff" in low) {
            steps.append({"when": "This week", "title": f"Execute: {label}", "detail": f"Name the seats, cut fully loaded cost, freeze backfills. Cash-out on this path: {cash_out}."});
            steps.append({"when": "Day 14", "title": "Delivery triage after the cut", "detail": f"Re-scope {ms_name} so {ms} still lands with the smaller team — or slip the date explicitly."});
        } elif ("hold" in low) {
            steps.append({"when": "This week", "title": "Hold headcount; re-scope the milestone", "detail": f"Do not open reqs. Re-cut {ms_name} scope so {ms} is still credible without new burn."});
        } elif ("infra" in low) {
            steps.append({"when": "This week", "title": "Buy infra/tools instead of headcount", "detail": f"Execute {label}. Cap the tools budget; do not let infra spend become a stealth hire."});
        } else {
            steps.append({"when": "This week", "title": "Open the hire with a fully loaded cost sheet", "detail": f"Execute {label}. Put salary + benefits + ramp on one page against cash-out {cash_out}."});
            steps.append({"when": "Day 30", "title": "Ramp checkpoint", "detail": "If the hire is not shipping against the milestone within 30 days, convert to contractor or freeze the second seat."});
        }
        steps.append({"when": pretty_date(str(best.get("milestone_date", ""))), "title": f"Org capacity vs {ms_name}", "detail": f"Headcount only wins if {ms_name} still lands before cash-out {cash_out}."});
    } elif desk == "launch" or ("ship" in low) or ("release" in low) {
        if ("slip" in low) or ("delay" in low) {
            steps.append({"when": "This week", "title": "Publish the slipped ship date and cut scope", "detail": f"Execute {label}. Name the new date; kill non-critical scope so burn does not fund theater."});
        } elif ("staged" in low) or ("soft" in low) {
            steps.append({"when": "This week", "title": "Soft-launch to a capped cohort", "detail": f"Execute {label}. Limit seats/customers; measure activation before a public push."});
        } else {
            steps.append({"when": "This week", "title": "Lock full launch checklist to the milestone date", "detail": f"Execute {label}. Owners for eng, GTM, and support — no silent slip past {ms}."});
        }
        steps.append({"when": "Weekly", "title": "Blocker board", "detail": f"Any blocker that threatens {ms} must show a cash-out impact. Current cash-out on this line: {cash_out}."});
    } else {
        # finance default
        if ("cut" in low) or ("burn" in low) or ("extend" in low) {
            steps.append({"when": "This week", "title": "Cut discretionary burn on a named list", "detail": f"Execute {label}. List every cut with $/mo. Target leaving cash-out past {ms}."});
        } elif ("price" in low) {
            steps.append({"when": "This week", "title": "Ship the price change with a churn kill-switch", "detail": f"Execute {label}. If churn > your rollback threshold in 30 days, reverse. Current MRR ${mrr:,.0f}."});
        } elif ("raise" in low) {
            steps.append({"when": "This week", "title": "Open the raise with a cash-out deadline", "detail": f"Execute {label}. Term-sheet target must land well before cash-out {cash_out}."});
        } else {
            steps.append({"when": "This week", "title": f"Execute the finance move: {label}", "detail": f"Tie every dollar to cash-out {cash_out} vs milestone {ms}."});
        }
        steps.append({"when": "Monthly", "title": "Board-ready runway check", "detail": f"Net burn ~${burn:,.0f}/mo. If runway months drop below your raise lead time, cut or raise — do not wait."});
    }
    return steps;
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

def build_decision_intel(session: Session, best_id: str, best_full: dict, survivors: list, dead: list, date_line: str, margin_days: int, kill_txt: str) -> dict {
    decision = extract_decision_line(session.proposal if session.proposal else session.question);
    desk = primary_desk(session, best_full);
    move = str(best_full.get("last_action", best_full.get("label", "hold current state"))) if best_full else "hold";
    cash_out = format_cash_out(best_full);
    ms_date = pretty_date(str(best_full.get("milestone_date", ""))) if best_full else "—";
    ms_name = str(best_full.get("milestone", "milestone")) if best_full else "milestone";
    runway = format_runway(best_full);
    hit = bool(best_full.get("milestone_hit", False)) if best_full else False;
    cf_plus = float(best_full.get("runway_months", 0.0)) >= 900.0 if best_full else False;
    dlow = decision.lower();

    # Clear single answer (the thing founders actually need)
    dont = "";
    if dead {
        d0 = dead[0];
        dont = f"Do NOT: {str(d0.get('last_action', d0.get('label', d0['id'])))[:48]} — {str(d0.get('kill_reason', ''))[:100]}";
    }
    if ("fire" in dlow) or ("layoff" in dlow) {
        if ("fire" in move.lower()) {
            do_line = f"YES — {move}. Cut the seats, freeze backfills, and keep burn down through {ms_name}.";
        } elif ("hold" in move.lower()) or ("lean" in move.lower()) or ("no layoff" in move.lower()) {
            do_line = f"Prefer lean over a messy layoff theater: {move}. If you still fire, fire for burn — not vibes — and do not rehire.";
        } else {
            do_line = f"On firing: the surviving path is «{move}». Do not hire into the hole you just cut.";
        }
    } elif ("buy" in dlow) or ("printer" in dlow) or ("equipment" in dlow) or ("purchase" in dlow) {
        if ("do not buy" in move.lower()) or ("wait" in move.lower()) {
            do_line = f"NO — do not buy yet. Surviving path: {move}.";
        } elif ("one" in move.lower()) or ("lease" in move.lower()) {
            do_line = f"PARTIAL YES — {move}. Do not jump to the full purchase until utilization proves out.";
        } else {
            do_line = f"YES — {move}. Fund the gear only if capacity unlocks revenue before {ms_name}.";
        }
    } else {
        do_line = f"DO: {move}.";
    }
    if cf_plus and hit {
        because = f"{ms_name} ({ms_date}) clears because you are cash-flow positive on this path ({runway}).";
    } elif hit and margin_days > 0 {
        because = f"{ms_name} ({ms_date}) lands before cash-out ({cash_out}) with {margin_days} days margin · {runway} runway.";
    } elif hit {
        because = f"{move} still hits {ms_name} before cash-out ({cash_out}), but margin is thin.";
    } elif best_full {
        because = f"Least-bad survivor: cash-out {cash_out} vs {ms_name} {ms_date} — treat as rescue, not green light.";
    } else {
        because = "No branch survived hard arithmetic — do not execute the plan as stated.";
    }
    one_liner = f"ANSWER: {do_line} {because}";
    if dont {
        one_liner = one_liner + f" {dont}";
    }
    answer = {
        "one_liner": one_liner,
        "do": do_line,
        "dont": dont if dont else "No single killed foil — compare the tree.",
        "because": because,
        "dates": f"Recommended: {cash_out} · Milestone: {ms_name} on {ms_date} · Runway: {runway}",
        "decision": decision,
        "move": move,
        "desk": desk
    };

    # Verdict prose — what the decision IS
    prose = one_liner;
    if best_full and hit and (margin_days > 0 or cf_plus) {
        prose = (
            f"On «{decision}», take this path: {move}. "
            + because
        );
    } elif best_full and hit {
        prose = (
            f"On «{decision}», {move} is the only line that still hits {ms_name} before cash-out {cash_out}. "
            + "Margin is thin — execute exactly, do not add spend."
        );
    } elif best_full {
        prose = (
            f"On «{decision}», {move} is the least-bad survivor (cash-out {cash_out}), "
            + f"but {ms_name} ({ms_date}) is not safely cleared. Treat this as a rescue plan, not a green light."
        );
    } else {
        prose = f"On «{decision}», no branch survived hard arithmetic. Do not execute the plan as stated — cut scope or spend first.";
    }

    analysis_bits: list = [];
    analysis_bits.append(f"Decision under test: {decision}.");
    analysis_bits.append(f"Desk: {desk}. Recommended branch {best_id} → {move}.");
    if best_full {
        analysis_bits.append(
            f"Arithmetic: cash-out {cash_out} vs milestone {ms_date}"
            + (f" (margin {margin_days} days, milestone HIT)." if hit and margin_days > 0 and not cf_plus else (" (cash-flow positive, milestone HIT)." if hit and cf_plus else (" (milestone HIT, thin margin)." if hit else " (milestone MISS on this line)."))
            )
        );
    }
    if len(survivors) >= 2 {
        runner = survivors[1];
        analysis_bits.append(
            f"Runner-up {runner.get('branch_id')} ({str(runner.get('action') or runner.get('label', ''))[:40]}) "
            + f"cash-out {pretty_date(str(runner.get('cash_out_date', '')))} — worse on runway + milestone rank."
        );
    }
    if dead {
        d0 = dead[0];
        analysis_bits.append(
            f"Killed alternative: {str(d0.get('last_action', d0.get('label', d0['id'])))[:48]} — {str(d0.get('kill_reason', ''))[:140]}"
        );
        if len(dead) > 1 {
            analysis_bits.append(f"{len(dead)} forks failed verifier checks (dates, not opinions).");
        }
    }
    analysis = " ".join(analysis_bits);

    # Action plan: desk playbook + avoids + calendar gates
    steps = desk_playbook_steps(desk, move, decision, best_full if best_full else {}, session.company);
    seen_avoid: set = set();
    move_low = move.lower();
    for d in dead {
        if len(seen_avoid) >= 3 { break; }
        title_key = str(d.get("last_action", d.get("label", d["id"])))[:48];
        # Never "avoid" the same move we just recommended.
        if title_key.lower() == move_low or (move_low and move_low in title_key.lower()) {
            continue;
        }
        if d.get("kill_reason") and title_key not in seen_avoid {
            seen_avoid.add(title_key);
            steps.append({
                "when": "Avoid",
                "title": f"Do not: {title_key}",
                "detail": f"{str(d.get('kill_reason', ''))[:160]} — that path loses the date race."
            });
        }
    }
    best_cash_out = str(best_full.get("cash_out_date", "")) if best_full else "";
    best_ms_date = str(best_full.get("milestone_date", "")) if best_full else "";
    if best_full and float(best_full.get("runway_months", 99.0)) < 9.0 and best_cash_out {
        raise_by = add_days(best_cash_out, -90);
        steps.append({
            "when": pretty_date(raise_by),
            "title": "Start raise conversations or cut burn",
            "detail": f"Lead time: begin ~3 months before cash-out {pretty_date(best_cash_out)}. Waiting until empty is how startups die."
        });
    }
    if best_ms_date {
        co_txt = cash_out if cf_plus else pretty_date(best_cash_out);
        steps.append({
            "when": pretty_date(best_ms_date),
            "title": f"Hard gate: {ms_name}",
            "detail": (
                f"Must land while the recommended path stays solvent — {co_txt}; margin {margin_days} days."
                if margin_days > 0 or cf_plus
                else f"Cash-out {pretty_date(best_cash_out)} is not safely after this milestone — only proceed if the milestone unlocks cash immediately."
            )
        });
    }

    # Watch-fors from Red attacks + desk
    watch_bits: list = [];
    for a in session.attacks[-3:] {
        watch_bits.append(str(a.get("claim", ""))[:110]);
    }
    if desk == "publicity" {
        watch_for = "Kill signal: CAC up or conversion flat for 2 weeks while burn stays elevated. " + (" Red warned: " + " | ".join(watch_bits) if watch_bits else "");
    } elif ("buy" in dlow) or ("printer" in dlow) or ("equipment" in dlow) {
        watch_for = "Kill signal: printers idle or jobs not filling new capacity within 30 days. " + (" Red warned: " + " | ".join(watch_bits) if watch_bits else "");
    } elif desk == "management" {
        watch_for = "Kill signal: hire burn up with no milestone velocity in 30 days. " + (" Red warned: " + " | ".join(watch_bits) if watch_bits else "");
    } elif desk == "launch" {
        watch_for = "Kill signal: ship date slips twice or critical path has no owner. " + (" Red warned: " + " | ".join(watch_bits) if watch_bits else "");
    } else {
        watch_for = "Kill signal: runway months drop or raise timeline slips while burn holds. " + (" Red warned: " + " | ".join(watch_bits) if watch_bits else "");
    }

    open_risks = f"Unmitigated Red pressure on the recommended line; re-run if spend or dates change. Desk={desk}.";
    if not kill_txt or "No hard kill" in kill_txt {
        # Prefer concrete dead-branch kills
        kill_parts: list = [];
        for d in dead[:3] {
            if d.get("kill_reason") {
                kill_parts.append(f"{str(d.get('last_action', d['id']))[:40]}: {str(d.get('kill_reason'))[:100]}");
            }
        }
        kill_out = "; ".join(kill_parts) if kill_parts else "No hard kill shots on the recommended line — watch the Red claims anyway.";
    } else {
        kill_out = kill_txt;
    }

    title = f"Verdict: {move}" if move else "Decision memo";
    return {
        "title": title,
        "prose": prose,
        "analysis": analysis,
        "watch_for": watch_for.strip(),
        "action_plan": steps,
        "kill_shots": kill_out,
        "open_risks": open_risks,
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
    prose = arbiter_narrate(json.dumps(session.scorecards)[:2000], json.dumps(session.findings)[:2000], session.fixture_id);
    if prose.date_line and session.fixture_id != "custom" {
        # Custom runs: the deterministic cash-out comparison is the headline.
        date_line = prose.date_line;
    }

    dead: list = [];
    for b in session.branches {
        if not b.get("alive", True) {
            dead.append(b);
        }
    }
    dissent = prose.dissent if prose.dissent else "Competing forks lost on cash-out vs milestone.";
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

    # ---- Decision analysis + plan of action (desk playbooks + verified dates) ----
    intel = build_decision_intel(session, best_id, best_full, survivors, dead, date_line, margin_days, kill_txt);

    # Prefer engineered intel for custom; allow cached/LLM prose only when it has content.
    analysis = intel["analysis"];
    watch_for = intel["watch_for"];
    steps = intel["action_plan"];
    memo_prose = prose.recommended_reason if prose.recommended_reason else intel["prose"];
    memo_title = prose.title if (prose.title and prose.title != "Decision memo" and session.fixture_id != "custom") else intel["title"];
    memo_kills = kill_txt if (kill_txt and "No hard kill" not in kill_txt) else intel["kill_shots"];
    if prose.kill_shots and session.fixture_id != "custom" and not str(prose.kill_shots).strip().startswith("[") {
        memo_kills = prose.kill_shots;
    }
    memo_risks = prose.open_risks if prose.open_risks else intel["open_risks"];

    # Optional LLM polish — only if it returns non-empty (custom returns empty offline).
    steps_txt_parts: list = [];
    for st in steps {
        steps_txt_parts.append(f"[{st['when']}] {st['title']} — {st['detail']}");
    }
    narration = plan_narrate(date_line + " | " + analysis, "\n".join(steps_txt_parts), session.fixture_id);
    if narration.analysis {
        analysis = narration.analysis;
    }
    if narration.watch_for {
        watch_for = narration.watch_for;
    }

    session.memo = {
        "recommended_branch_id": best_id,
        "title": memo_title,
        "prose": memo_prose,
        "kill_shots": memo_kills,
        "open_risks": memo_risks,
        "dissent": dissent,
        "date_line": date_line,
        "decomposition": decomp,
        "analysis": analysis,
        "watch_for": watch_for,
        "action_plan": steps,
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
        session.baseline = baseline_plan(proposal if proposal else session.question, fixture_id);
    }
    n = min(rounds, MAX_ROUNDS);
    for r in range(1, n + 1) {
        leaves = alive_leaves(session);
        if not leaves {
            log_event(session, "halt", "No alive leaves — stopping early");
            break;
        }
        blue_children: list = [];
        # Custom (live) runs explore wider: round 1 forks TWO rival strategies
        # off the seed. Cached fixtures keep the authored shape.
        is_custom_run = session.fixture_id == "custom";
        n_forks = 2 if (r == 1 and is_custom_run) else 1;
        leaf_cap = 4 if is_custom_run else 3;
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
        red_cap = 4 if is_custom_run else 3;
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
