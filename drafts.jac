# Typed drafts + by llm() surface + deterministic fixture cache fallbacks

import json;
import os;

obj EntityDraft {
    has kind: str;
    has name: str;
    has capacity: float = 0.0;
    has status: str = "ok";
}

obj ConstraintDraft {
    has rule: str;
    has description: str;
    has hard: bool = True;
    has limit_value: float = 0.0;
    has unit: str = "";
}

obj GoalDraft {
    has description: str;
    has metric: str;
    has target_value: float = 1.0;
    has weight: float = 1.0;
}

obj WorldDraft {
    has title: str;
    has entities: list[EntityDraft];
    has constraints: list[ConstraintDraft];
    has goals: list[GoalDraft];
    has budget: float = 0.0;
    has domain: str = "general";
}

obj ActionDraft {
    has who: str;
    has what: str;
    has when_label: str = "T+0";
    has cost: float = 0.0;
    has rationale: str = "";
    has needs_tools: list[str] = [];
}

obj StressorDraft {
    has description: str;
    has severity: float = 0.7;
    has likelihood: float = 0.6;
    has target_ref: str = "";
    has tag: str = "generic";
    has rationale: str = "";
    has needs_tools: list[str] = [];
}

obj MemoProse {
    has title: str;
    has recommended_reason: str;
    has kill_shots: str;
    has open_risks: str;
    has dissent: str;
}

# --- by llm() typed surface (live path) ---

sem extract_world_llm = "Extract actors, assets, hard/soft constraints, goals, and budget from a decision proposal. Be concrete.";
def extract_world_llm(text: str) -> WorldDraft by llm(temperature=0.1);

sem blue_propose_llm = "Propose one concrete Blue-team action that improves goal coverage under constraints. Prefer patching known Red kill shots.";
def blue_propose_llm(branch_summary: str, goals: str, prior_attacks: str) -> ActionDraft by llm(temperature=0.3);

sem red_attack_llm = "Propose one adversarial stressor that falsifies the Blue plan. Prefer hard constraint breaks that tools can verify.";
def red_attack_llm(branch_summary: str, actions: str) -> StressorDraft by llm(temperature=0.4);

sem arbiter_narrate_llm = "Write a decision memo: recommended branch, kill shots avoided, open risks, and dissent from dead branches.";
def arbiter_narrate_llm(scorecards: str, findings: str) -> MemoProse by llm(temperature=0.2);

sem baseline_plan_llm = "One-shot confident plan with no red-team. Be decisive and slightly overconfident — this is the foil.";
def baseline_plan_llm(text: str) -> str by llm(temperature=0.5);

glob CACHE_DIR: str = "cache";

def _cache_path(fixture_id: str) -> str {
    return f"{CACHE_DIR}/{fixture_id}.json";
}

def load_fixture_cache(fixture_id: str) -> dict {
    path = _cache_path(fixture_id);
    if not os.path.exists(path) {
        return {};
    }
    with open(path, "r") as f {
        return json.load(f);
    }
}

def entity_from_dict(d: dict) -> EntityDraft {
    return EntityDraft(
        kind=str(d.get("kind", "actor")),
        name=str(d.get("name", "unknown")),
        capacity=float(d.get("capacity", 0.0)),
        status=str(d.get("status", "ok"))
    );
}

def constraint_from_dict(d: dict) -> ConstraintDraft {
    return ConstraintDraft(
        rule=str(d.get("rule", "budget")),
        hard=bool(d.get("hard", True)),
        description=str(d.get("description", "")),
        limit_value=float(d.get("limit_value", 0.0)),
        unit=str(d.get("unit", ""))
    );
}

def goal_from_dict(d: dict) -> GoalDraft {
    return GoalDraft(
        description=str(d.get("description", "")),
        metric=str(d.get("metric", "success")),
        target_value=float(d.get("target_value", 1.0)),
        weight=float(d.get("weight", 1.0))
    );
}

def world_from_cache(data: dict) -> WorldDraft {
    ents: list[EntityDraft] = [];
    for e in data.get("entities", []) {
        ents.append(entity_from_dict(e));
    }
    cons: list[ConstraintDraft] = [];
    for c in data.get("constraints", []) {
        cons.append(constraint_from_dict(c));
    }
    goals: list[GoalDraft] = [];
    for g in data.get("goals", []) {
        goals.append(goal_from_dict(g));
    }
    return WorldDraft(
        title=str(data.get("title", "Untitled")),
        entities=ents,
        constraints=cons,
        goals=goals,
        budget=float(data.get("budget", 0.0)),
        domain=str(data.get("domain", "general"))
    );
}

def action_from_dict(d: dict) -> ActionDraft {
    tools: list[str] = [];
    for t in d.get("needs_tools", []) {
        tools.append(str(t));
    }
    return ActionDraft(
        who=str(d.get("who", "Blue")),
        what=str(d.get("what", "hold")),
        when_label=str(d.get("when_label", "T+0")),
        cost=float(d.get("cost", 0.0)),
        rationale=str(d.get("rationale", "")),
        needs_tools=tools
    );
}

def stressor_from_dict(d: dict) -> StressorDraft {
    tools: list[str] = [];
    for t in d.get("needs_tools", []) {
        tools.append(str(t));
    }
    return StressorDraft(
        description=str(d.get("description", "")),
        severity=float(d.get("severity", 0.7)),
        likelihood=float(d.get("likelihood", 0.6)),
        target_ref=str(d.get("target_ref", "")),
        tag=str(d.get("tag", "generic")),
        rationale=str(d.get("rationale", "")),
        needs_tools=tools
    );
}

def memo_from_dict(d: dict) -> MemoProse {
    return MemoProse(
        title=str(d.get("title", "Decision Memo")),
        recommended_reason=str(d.get("recommended_reason", "")),
        kill_shots=str(d.get("kill_shots", "")),
        open_risks=str(d.get("open_risks", "")),
        dissent=str(d.get("dissent", ""))
    );
}

def prefer_cache() -> bool {
    # Offline / demo-safe unless SPLITHORIZON_LIVE=1
    return os.environ.get("SPLITHORIZON_LIVE", "") != "1";
}

def extract_world(text: str, fixture_id: str) -> WorldDraft {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    if cache and "world" in cache {
        return world_from_cache(cache["world"]);
    }
    if prefer_cache() and fixture_id {
        # Should not happen if fixtures shipped correctly
        return WorldDraft(title="Empty", entities=[], constraints=[], goals=[], budget=0.0, domain="general");
    }
    try {
        return extract_world_llm(text);
    } except Exception as e {
        print(f"[SplitHorizon] extract_world LLM fallback: {e}");
        return WorldDraft(
            title="Parsed proposal",
            entities=[EntityDraft(kind="actor", name="DecisionMaker", capacity=1.0)],
            constraints=[ConstraintDraft(rule="budget", hard=True, description="Stay within budget", limit_value=100000.0, unit="USD")],
            goals=[GoalDraft(description="Achieve stated objective", metric="success", target_value=1.0, weight=1.0)],
            budget=100000.0,
            domain="general"
        );
    }
}

def blue_propose(branch_summary: str, goals: str, prior_attacks: str, fixture_id: str, round_no: int) -> ActionDraft {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    key = f"blue_r{round_no}";
    if cache and key in cache {
        return action_from_dict(cache[key]);
    }
    if prefer_cache() and fixture_id {
        return ActionDraft(who="Blue", what="Hold current posture", cost=0.0, rationale="cache miss hold");
    }
    try {
        return blue_propose_llm(branch_summary, goals, prior_attacks);
    } except Exception as e {
        print(f"[SplitHorizon] blue_propose LLM fallback: {e}");
        return ActionDraft(who="Blue", what="Conservative patch: add buffer and verify constraints", cost=5000.0, rationale=str(e), needs_tools=["BudgetCalc", "ConstraintCheck"]);
    }
}

def red_attack(branch_summary: str, actions: str, fixture_id: str, round_no: int) -> StressorDraft {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    key = f"red_r{round_no}";
    if cache and key in cache {
        return stressor_from_dict(cache[key]);
    }
    if prefer_cache() and fixture_id {
        return StressorDraft(description="Generic disruption", severity=0.6, tag="generic", needs_tools=["ScenarioInject"]);
    }
    try {
        return red_attack_llm(branch_summary, actions);
    } except Exception as e {
        print(f"[SplitHorizon] red_attack LLM fallback: {e}");
        return StressorDraft(description="Adversarial surge that exceeds capacity", severity=0.8, likelihood=0.7, tag="capacity_surge", needs_tools=["ScenarioInject", "ConstraintCheck"]);
    }
}

def arbiter_narrate(scorecards: str, findings: str, fixture_id: str) -> MemoProse {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    if cache and "memo" in cache {
        return memo_from_dict(cache["memo"]);
    }
    if prefer_cache() and fixture_id {
        return MemoProse(title="Cached Memo", recommended_reason="Best surviving branch", kill_shots="See findings", open_risks="Residual uncertainty", dissent="Dead branches disagreed");
    }
    try {
        return arbiter_narrate_llm(scorecards, findings);
    } except Exception as e {
        print(f"[SplitHorizon] arbiter LLM fallback: {e}");
        return MemoProse(
            title="Arbiter Decision Memo",
            recommended_reason="Highest rank among alive branches",
            kill_shots=findings[:500],
            open_risks="Uncertainty remains on unverified edges",
            dissent="Red findings on killed branches remain as dissent trail"
        );
    }
}

def baseline_plan(text: str, fixture_id: str) -> str {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    if cache and "baseline" in cache {
        return str(cache["baseline"]);
    }
    if prefer_cache() and fixture_id {
        return "Baseline unavailable in cache.";
    }
    try {
        return baseline_plan_llm(text);
    } except Exception as e {
        return f"One-shot baseline failed ({e}). Naive plan: proceed immediately with the proposal as stated, ignore adversarial forks.";
    }
}
