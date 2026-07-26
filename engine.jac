# Session + Blue/Red/Brancher/Verifier/Arbiter — survival scoring only

include schema;
include drafts;
include verifiers;
include fixtures;

import json;
import copy;

glob MAX_ROUNDS: int = 3;
glob MAX_BRANCHES: int = 12;

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

def seed_session(proposal: str, fixture_id: str, rounds: int) -> Session {
    session = Session(fixture_id=fixture_id, proposal=proposal, rounds=rounds);
    fx = get_fixture(fixture_id) if fixture_id else get_fixture("interlock");
    company = seed_company_state();
    session.company = company;
    session.title = str(fx.get("name", "SplitHorizon"));
    session.domain = str(fx.get("module", "interlock"));
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
    prior = "; ".join(prior_parts[-3:]);
    draft = blue_propose(parent.get("summary", ""), session.question, prior, session.fixture_id, round_no);
    tag = draft.effect_tag if draft.effect_tag else draft.move;
    label = effect_label(tag);
    child = fork_branch(session, parent, f"R{round_no} Blue: {label[:42]}", "blue", round_no, tag);
    child["last_action"] = label;
    child["summary"] = f"Blue: {draft.claim} [{tag}]";

    prior_burn = float(parent.get("monthly_burn", 0.0));
    applied = apply_effect(state_from_branch(parent), tag);
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
        log_event(session, "blue", f"{child['id']}: {tag} [KILL] {child.get('kill_reason', '')}", child["id"]);
    } else {
        log_event(session, "blue", f"{child['id']}: {tag} → cash-out {pretty_date(bundle.cash_out_date)}", child["id"]);
    }
    return child;
}

def red_turn(session: Session, parent: dict, round_no: int) -> dict {
    draft = red_attack(parent.get("summary", ""), parent.get("move", ""), session.fixture_id, round_no);
    child = fork_branch(session, parent, f"R{round_no} Red: {draft.claim[:42]}", "red", round_no, draft.stress_tag);
    child["last_stressor"] = draft.claim;
    child["summary"] = f"Red: {draft.claim} [{draft.stress_tag}]";

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

    prior_burn = float(parent.get("monthly_burn", 0.0));
    stressed = apply_stress(state_from_branch(parent), draft.stress_tag);
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
    date_line = "";
    if len(survivors) >= 2 {
        a = survivors[0];
        b = survivors[1];
        date_line = (
            f"{str(a.get('label', 'Plan A'))[:40]} cash-out {pretty_date(str(a.get('cash_out_date', '')))}. "
            + f"{str(b.get('label', 'Plan B'))[:40]} cash-out {pretty_date(str(b.get('cash_out_date', '')))}."
        );
    } elif survivors {
        a = survivors[0];
        dead_foil = "";
        for br in session.branches {
            if not br.get("alive", True) and br.get("cash_out_date") {
                dead_foil = (
                    f"Killed plan runs out {pretty_date(str(br.get('cash_out_date', '')))} "
                    + f"(before milestone {pretty_date(str(br.get('milestone_date', '')))})."
                );
                break;
            }
        }
        date_line = f"Survivor cash-out {pretty_date(str(a.get('cash_out_date', '')))}. " + (dead_foil if dead_foil else "");
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
    if prose.date_line {
        date_line = prose.date_line;
    }

    dead: list = [];
    for b in session.branches {
        if not b.get("alive", True) {
            dead.append(b);
        }
    }
    dissent = prose.dissent;
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

    session.memo = {
        "recommended_branch_id": best_id,
        "title": prose.title,
        "prose": prose.recommended_reason,
        "kill_shots": prose.kill_shots or kill_txt,
        "open_risks": prose.open_risks,
        "dissent": dissent,
        "date_line": date_line,
        "decomposition": decomp,
        "baseline_foil": session.baseline
    };
    log_event(session, "arbiter", f"Recommended {best_id}: {date_line}", best_id);
}

def run_protocol(proposal: str, fixture_id: str = "interlock", rounds: int = 3, run_baseline: bool = True) -> dict {
    session = seed_session(proposal, fixture_id, rounds);
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
        for leaf in leaves[:3] {
            blue_children.append(blue_turn(session, leaf, r));
            prune_if_needed(session);
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
        for bp in red_parents[:3] {
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
