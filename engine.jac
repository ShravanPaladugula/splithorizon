# Session state + turn scheduler + Blue/Red/Apply/Inject/Score/Arbiter protocol
# Graph mutations are recorded both on OSP nodes and in a serializable session dict for the UI.

include schema;
include drafts;
include tools;

import json;
import copy;

glob MAX_ROUNDS: int = 3;
glob MAX_BRANCHES: int = 12;

obj Session {
    has fixture_id: str = "";
    has proposal: str = "";
    has title: str = "";
    has domain: str = "";
    has budget: float = 0.0;
    has rounds: int = 3;
    has branch_count: int = 0;
    has branches: list[dict] = [];
    has edges: list[dict] = [];
    has findings: list[dict] = [];
    has tool_log: list[dict] = [];
    has scorecards: list[dict] = [];
    has memo: dict = {};
    has baseline: str = "";
    has events: list[dict] = [];
    has hard_rules: list[dict] = [];
    has goals_text: str = "";
    has capacity_limit: float = 1.0;
}

def new_branch_id(session: Session) -> str {
    session.branch_count += 1;
    return f"b{session.branch_count}";
}

def alive_leaves(session: Session) -> list[dict] {
    # A schedule leaf is alive and has no *alive* children (dead Red forks don't block Blue patches)
    parents_with_alive_children: set = set();
    id_to_branch: dict = {};
    for b in session.branches {
        id_to_branch[b["id"]] = b;
    }
    for e in session.edges {
        if e.get("type") == "forked_from" {
            child = id_to_branch.get(e["from"], {});
            parent_id = e["to"];
            if child and child.get("alive", True) {
                parents_with_alive_children.add(parent_id);
            }
        }
    }
    leaves: list[dict] = [];
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

def seed_session(proposal: str, fixture_id: str, rounds: int) -> Session {
    session = Session(fixture_id=fixture_id, proposal=proposal, rounds=rounds);
    world = extract_world(proposal, fixture_id);
    session.title = world.title;
    session.domain = world.domain;
    session.budget = world.budget;
    session.goals_text = "; ".join([g.description for g in world.goals]);
    hard_rules: list[dict] = [];
    for c in world.constraints {
        hard_rules.append({
            "rule": c.rule,
            "hard": c.hard,
            "description": c.description,
            "limit_value": c.limit_value,
            "unit": c.unit
        });
    }
    session.hard_rules = hard_rules;
    # capacity limit: prefer explicit capacity constraint, else asset capacity
    cap = 1.0;
    for c in world.constraints {
        if c.rule == "capacity" and c.limit_value > 0 {
            cap = c.limit_value;
        }
    }
    if cap == 1.0 {
        for e in world.entities {
            if e.kind == "asset" and e.capacity > 0 {
                cap = e.capacity;
            }
        }
    }
    session.capacity_limit = cap;

    root_id = new_branch_id(session);
    seed_branch = {
        "id": root_id,
        "parent_id": "",
        "round": 0,
        "label": f"Seed: {world.title}",
        "alive": True,
        "spent": 0.0,
        "residual_risk": 0.55,
        "goal_coverage": 0.2,
        "uncertainty": 0.6,
        "kill_reason": "",
        "summary": f"Seeded world with {len(world.entities)} entities, {len(world.constraints)} constraints",
        "side_created": "seed",
        "capacity_used": 0.0,
        "equity_score": 1.0,
        "sla_hours_left": 24.0,
        "last_action": "",
        "last_stressor": "",
        "flags": {}
    };
    session.branches.append(seed_branch);
    log_event(session, "seed", f"Seeded branch {root_id}: {world.title}", root_id);

    # Spawn OSP graph (Jac-native memory): Branch + Tool nodes walkers can visit
    bnode = root ++> Branch(
        branch_id=root_id,
        parent_id="",
        round_no=0,
        label=seed_branch["label"],
        alive=True,
        summary=seed_branch["summary"],
        side_created="seed"
    );
    root ++> Tool(name="BudgetCalc", schema_desc="spent + cost vs budget");
    root ++> Tool(name="ConstraintCheck", schema_desc="hard rule evaluator");
    root ++> Tool(name="ScenarioInject", schema_desc="canned stressor templates");
    for e in world.entities {
        eid = e.name.lower().replace(" ", "_");
        bnode +>: in_branch(note="entity") :+> WorldEntity(
            entity_id=eid,
            kind=e.kind,
            name=e.name,
            capacity=e.capacity,
            status=e.status
        );
    }
    return session;
}

def run_tool_visit(session: Session, branch_id: str, tool_name: str, ctx: dict) -> ToolResult {
    result = dispatch_tool(tool_name, ctx);
    entry = {
        "branch_id": branch_id,
        "tool": tool_name,
        "ok": result.ok,
        "detail": result.detail,
        "metrics": json.loads(result.metrics_json)
    };
    session.tool_log.append(entry);
    log_event(session, "tool", f"{tool_name} on {branch_id}: {result.detail}", branch_id);
    return result;
}

def fork_branch(session: Session, parent: dict, label: str, side: str, round_no: int) -> dict {
    child_id = new_branch_id(session);
    child = copy.deepcopy(parent);
    child["id"] = child_id;
    child["parent_id"] = parent["id"];
    child["round"] = round_no;
    child["label"] = label;
    child["side_created"] = side;
    child["kill_reason"] = "";
    session.branches.append(child);
    session.edges.append({"type": "forked_from", "from": child_id, "to": parent["id"], "via": side});
    return child;
}

def prune_if_needed(session: Session) {
    if len(session.branches) <= MAX_BRANCHES {
        return;
    }
    scored: list[dict] = [];
    for b in session.branches {
        if b.get("alive", True) {
            rank = float(b.get("goal_coverage", 0.0)) - float(b.get("residual_risk", 0.5)) - float(b.get("spent", 0.0)) / max(session.budget, 1.0);
            scored.append({"rank": rank, "id": b["id"]});
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
        bid = item["id"];
        b = branch_by_id(session, bid);
        if b and b.get("alive", True) and b.get("side_created") != "seed" {
            b["alive"] = False;
            b["kill_reason"] = "pruned: branch cap";
            log_event(session, "prune", f"Pruned {bid}", bid);
            alive_n -= 1;
        }
    }
}

def blue_turn(session: Session, parent: dict, round_no: int) -> dict {
    prior = "; ".join([f["claim"] for f in session.findings if f.get("side") == "red"][-3:]);
    draft = blue_propose(parent.get("summary", ""), session.goals_text, prior, session.fixture_id, round_no);
    child = fork_branch(session, parent, f"R{round_no} Blue: {draft.what[:48]}", "blue", round_no);
    child["last_action"] = draft.what;
    child["summary"] = f"Blue action: {draft.what} (cost={draft.cost:.0f}). {draft.rationale}";
    flags = dict(child.get("flags", {}));
    what_l = draft.what.lower();
    if "divert" in what_l or "ridge" in what_l or "hold" in what_l or "priority" in what_l or "dual-control" in what_l {
        flags["fog_choke_no_overwatch"] = False;
        flags["fraud_clear_above_threshold"] = False;
        child["capacity_used"] = min(float(child.get("capacity_used", 0.0)), 0.7);
        child["equity_score"] = max(float(child.get("equity_score", 1.0)), 0.75);
    }
    child["flags"] = flags;

    # Tool visits — BudgetCalc then ConstraintCheck
    tools_needed = draft.needs_tools if draft.needs_tools else ["BudgetCalc", "ConstraintCheck"];
    budget_ok = True;
    for tname in tools_needed {
        if tname == "BudgetCalc" {
            res = run_tool_visit(session, child["id"], "BudgetCalc", {
                "spent": child.get("spent", 0.0),
                "action_cost": draft.cost,
                "budget_limit": session.budget
            });
            budget_ok = res.ok;
            if res.ok {
                child["spent"] = float(child.get("spent", 0.0)) + draft.cost;
            }
        } elif tname == "ConstraintCheck" {
            res = run_tool_visit(session, child["id"], "ConstraintCheck", {
                "hard_rules_json": json.dumps(session.hard_rules),
                "spent": child.get("spent", 0.0) + (0.0 if budget_ok else draft.cost),
                "budget_limit": session.budget,
                "capacity_used": child.get("capacity_used", 0.0),
                "capacity_limit": 1.0,
                "sla_hours_left": child.get("sla_hours_left", 24.0),
                "equity_score": child.get("equity_score", 1.0),
                "flags_json": json.dumps(flags)
            });
            if not res.ok {
                child["alive"] = False;
                child["kill_reason"] = res.detail;
            }
        } elif tname == "ScenarioInject" {
            run_tool_visit(session, child["id"], "ScenarioInject", {"tag": session.domain});
        }
    }
    if budget_ok {
        child["spent"] = float(parent.get("spent", 0.0)) + draft.cost;
        # Blue patches improve coverage / reduce risk slightly
        child["goal_coverage"] = min(1.0, float(parent.get("goal_coverage", 0.2)) + 0.25);
        child["residual_risk"] = max(0.05, float(parent.get("residual_risk", 0.55)) - 0.15);
        child["uncertainty"] = max(0.1, float(parent.get("uncertainty", 0.5)) - 0.05);
    } else {
        # apply cost anyway for honesty, mark dead if over hard budget
        child["spent"] = float(parent.get("spent", 0.0)) + draft.cost;
        child["alive"] = False;
        child["kill_reason"] = "Blue action broke budget (BudgetCalc)";
    }

    session.findings.append({
        "id": f"f{len(session.findings)+1}",
        "side": "blue",
        "claim": draft.rationale or draft.what,
        "branch_id": child["id"],
        "evidence": "BudgetCalc/ConstraintCheck"
    });
    log_event(session, "blue", f"{child['id']}: {draft.what}", child["id"]);
    return child;
}

def red_turn(session: Session, parent: dict, round_no: int) -> dict {
    actions = parent.get("last_action", parent.get("summary", ""));
    draft = red_attack(parent.get("summary", ""), actions, session.fixture_id, round_no);
    child = fork_branch(session, parent, f"R{round_no} Red: {draft.description[:48]}", "red", round_no);
    child["last_stressor"] = draft.description;
    child["summary"] = f"Red stressor: {draft.description}. {draft.rationale}";

    inj = run_tool_visit(session, child["id"], "ScenarioInject", {"tag": draft.tag});
    metrics = json.loads(inj.metrics_json);
    child["spent"] = float(child.get("spent", 0.0)) + float(metrics.get("cost_delta", 0.0));
    # Capacity used as fraction of limit (0..1+), not raw tons
    child["capacity_used"] = float(child.get("capacity_used", 0.0)) + float(metrics.get("capacity_hit", 0.0));
    if "risk_delta" in metrics {
        child["residual_risk"] = min(1.0, float(child.get("residual_risk", 0.5)) + float(metrics["risk_delta"]));
    } else {
        child["residual_risk"] = min(1.0, float(child.get("residual_risk", 0.5)) + draft.severity * 0.3);
    }
    child["goal_coverage"] = max(0.0, float(child.get("goal_coverage", 0.2)) - 0.2);
    child["uncertainty"] = min(0.95, float(child.get("uncertainty", 0.5)) + 0.1);

    action_l = str(parent.get("last_action", "")).lower();
    flags: dict = dict(parent.get("flags", {}));
    # Logistics: naive Highway push under fog delay without divert/patch => must_not
    if draft.tag == "logistics_delay" {
        naive = ("highway 9" in action_l or "push highway" in action_l) and ("divert" not in action_l) and ("patch" not in action_l) and ("ridge" not in action_l);
        if naive or flags.get("fog_choke_no_overwatch") {
            flags["fog_choke_no_overwatch"] = True;
            child["capacity_used"] = max(float(child.get("capacity_used", 0.0)), 1.05);
        }
    }
    if draft.tag == "fraud_spike" {
        child["sla_hours_left"] = float(child.get("sla_hours_left", 24.0)) - 10.0;
        if "clear" in action_l and "hold" not in action_l {
            flags["fraud_clear_above_threshold"] = True;
            child["residual_risk"] = max(float(child.get("residual_risk", 0.5)), 0.88);
        }
    }
    if draft.tag == "capacity_surge" {
        child["equity_score"] = max(0.0, float(child.get("equity_score", 1.0)) - 0.45);
        if "first-come" in action_l or "first come" in action_l or "fcfs" in action_l or "fill all" in action_l {
            child["equity_score"] = min(float(child.get("equity_score", 1.0)), 0.55);
            child["capacity_used"] = max(float(child.get("capacity_used", 0.0)), 1.1);
        }
    }
    child["flags"] = flags;

    check = run_tool_visit(session, child["id"], "ConstraintCheck", {
        "hard_rules_json": json.dumps(session.hard_rules),
        "spent": child.get("spent", 0.0),
        "budget_limit": session.budget,
        "capacity_used": child.get("capacity_used", 0.0),
        "capacity_limit": 1.0 if session.domain in ["logistics", "shelter", "fintech"] else session.capacity_limit,
        "sla_hours_left": child.get("sla_hours_left", 24.0),
        "equity_score": child.get("equity_score", 1.0),
        "flags_json": json.dumps(flags)
    });

    killed = False;
    if not check.ok {
        child["alive"] = False;
        child["kill_reason"] = check.detail;
        killed = True;
    }
    if float(child.get("capacity_used", 0.0)) > 1.0 and session.domain != "fintech" {
        child["alive"] = False;
        child["kill_reason"] = child.get("kill_reason") or f"Capacity exceeded: {child.get('capacity_used'):.2f} > 1.0";
        killed = True;
    }

    session.findings.append({
        "id": f"f{len(session.findings)+1}",
        "side": "red",
        "claim": draft.rationale or draft.description,
        "branch_id": child["id"],
        "evidence": check.detail,
        "kill": killed
    });
    log_event(session, "red", f"{child['id']}: {draft.description}" + (" [KILL]" if killed else ""), child["id"]);
    return child;
}

def score_branch(session: Session, b: dict) {
    if not b.get("alive", True) {
        rank = -1.0;
    } else {
        cost_pen = float(b.get("spent", 0.0)) / max(session.budget, 1.0);
        # Prefer deeper patched survivors: round bonus + coverage - risk
        round_bonus = 0.08 * float(b.get("round", 0));
        side_bonus = 0.12 if b.get("side_created") == "blue" else (0.0 if b.get("side_created") == "red" else 0.02);
        rank = (
            float(b.get("goal_coverage", 0.0))
            + round_bonus
            + side_bonus
            - 0.55 * float(b.get("residual_risk", 0.5))
            - 0.15 * cost_pen
            - 0.1 * float(b.get("uncertainty", 0.5))
        );
    }
    card = {
        "branch_id": b["id"],
        "residual_risk": b.get("residual_risk", 0.5),
        "goal_coverage": b.get("goal_coverage", 0.0),
        "cost": b.get("spent", 0.0),
        "uncertainty": b.get("uncertainty", 0.5),
        "rank_score": rank,
        "alive": b.get("alive", True),
        "label": b.get("label", ""),
        "narrative": b.get("summary", "")
    };
    kept: list[dict] = [];
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
    # Prefer alive LEAVES (counterfactual endpoints), not early ancestors
    leaves = alive_leaves(session);
    leaf_ids = set([b["id"] for b in leaves]);
    alive_cards: list[dict] = [];
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
    if alive_cards {
        best = alive_cards[0];
        best_id = best["branch_id"];
        # If the surviving leaf is a non-killing Red probe, prefer its Blue parent for the memo
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
                best = {"branch_id": best_id, "label": parent.get("label", "")};
            }
        }
    } else {
        all_cards = list(session.scorecards);
        all_cards.sort(key=lambda (s: dict) -> float { return s["rank_score"]; }, reverse=True);
        best = all_cards[0] if all_cards else {"branch_id": "none", "label": "none"};
        best_id = best["branch_id"];
    }
    kills = [f for f in session.findings if f.get("side") == "red" and f.get("kill")];
    kill_txt = "; ".join([f["claim"] for f in kills]) if kills else "No hard kill shots landed on the recommended line.";
    findings_txt = json.dumps(session.findings)[:2000];
    score_txt = json.dumps(session.scorecards)[:2000];
    prose = arbiter_narrate(score_txt, findings_txt, session.fixture_id);
    dead = [b for b in session.branches if not b.get("alive", True)];
    dissent = prose.dissent;
    if dead {
        dissent = dissent + " | Dead branches: " + ", ".join([d["id"] + "(" + d.get("kill_reason", "")[:40] + ")" for d in dead[:5]]);
    }
    session.memo = {
        "recommended_branch_id": best_id,
        "title": prose.title,
        "prose": prose.recommended_reason,
        "kill_shots": prose.kill_shots or kill_txt,
        "open_risks": prose.open_risks,
        "dissent": dissent,
        "baseline_foil": session.baseline
    };
    log_event(session, "arbiter", f"Recommended {best_id}: {prose.title}", best_id);
}

def run_protocol(proposal: str, fixture_id: str = "", rounds: int = 3, run_baseline: bool = True) -> dict {
    session = seed_session(proposal, fixture_id, rounds);
    if run_baseline {
        session.baseline = baseline_plan(proposal, fixture_id);
    }
    n = min(rounds, MAX_ROUNDS);
    for r in range(1, n + 1) {
        leaves = alive_leaves(session);
        if not leaves {
            log_event(session, "halt", "No alive leaves — stopping early");
            break;
        }
        # Cap concurrent leaves processed per round to control branching
        blue_children: list[dict] = [];
        for leaf in leaves[:4] {
            blue_children.append(blue_turn(session, leaf, r));
            prune_if_needed(session);
        }
        red_parents = [c for c in blue_children if c.get("alive", True)];
        if not red_parents {
            # Still red-team the dead blue forks once to show kill shots
            red_parents = blue_children[:1];
        }
        for bp in red_parents[:4] {
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
        "title": session.title,
        "domain": session.domain,
        "budget": session.budget,
        "branches": session.branches,
        "edges": session.edges,
        "findings": session.findings,
        "tool_log": session.tool_log,
        "scorecards": session.scorecards,
        "memo": session.memo,
        "baseline": session.baseline,
        "events": session.events,
        "hard_rules": session.hard_rules
    };
}
