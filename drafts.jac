# Typed drafts — LLM proposes claims/moves NEVER figures.

import json;
import os;
import time;

glob LLM_RETRY_SLEEP: float = 15.0;

obj MoveDraft {
    has move: str = "noop";
    has claim: str = "";
    has effect_tag: str = "noop";
    has module: str = "hire";
    has label: str = "";
    has burn_delta_pct: float = 0.0;
    has mrr_delta_pct: float = 0.0;
    has headcount_delta: int = 0;
    has milestone_shift_days: int = 0;
}

obj AttackDraft {
    has claim: str = "";
    has severity: str = "high";
    has check_hint: str = "alive_at_milestone";
    has stress_tag: str = "burn_spike";
    has burn_delta_pct: float = 0.0;
    has mrr_delta_pct: float = 0.0;
    has milestone_shift_days: int = 0;
}

obj PlanClass {
    has modules: list[str] = [];
    has restated: str = "";
}

obj MemoProse {
    has title: str;
    has recommended_reason: str;
    has kill_shots: str;
    has open_risks: str;
    has dissent: str;
    has date_line: str = "";
}

sem blue_propose_llm = "You defend the founder's plan (the question). Propose ONE concrete move this round that directly serves THAT plan — never a generic hiring/launch move unless the plan is about hiring/launching. Output: label (<=6 words, imperative, specific to the plan), claim (one sentence why this move wins on survival), module (hire|launch|runway — closest fit), effect_tag='custom', and bounded state effects the deterministic verifier will apply: burn_delta_pct (% change to monthly burn, -40..80), mrr_delta_pct (% change to MRR, -50..60), headcount_delta (-3..5), milestone_shift_days (-45..90, negative = milestone lands sooner). Effects must be plausible for the move. Avoid repeating a move already reflected in the branch summary.";
def blue_propose_llm(branch_summary: str, question: str, prior_attacks: str) -> MoveDraft by llm(temperature=0.3);

sem red_attack_llm = "You attack the branch's plan. Propose ONE realistic failure mode SPECIFIC to the plan and move described (not a generic burn spike). Output: claim (one concrete sentence), severity (low|medium|high), check_hint='alive_at_milestone', stress_tag='custom', and bounded stress the deterministic verifier will apply: burn_delta_pct (0..30 % increase to monthly burn), mrr_delta_pct (-40..0 % hit to MRR), milestone_shift_days (0..45 days of delay).";
def red_attack_llm(branch_summary: str, move: str) -> AttackDraft by llm(temperature=0.4);

sem classify_plan_llm = "Classify a startup founder's stated plan into the decision modules it touches, from exactly {hire, launch, runway}. Pick 1-3: hire = adding/cutting people or contractors; launch = shipping/releasing/going to market/marketing pushes/expansion; runway = anything implicating cash, burn, spend, pricing, or fundraising. Most plans that cost money should include runway. restated = one sentence restating the plan as an A-vs-B decision.";
def classify_plan_llm(plan: str) -> PlanClass by llm(temperature=0.1);

sem arbiter_narrate_llm = "Memo punchline is a DATE comparison. No confidence percentages.";
def arbiter_narrate_llm(scorecards: str, findings: str) -> MemoProse by llm(temperature=0.2);

sem baseline_plan_llm = "One-shot confident advice with no red-team — the chatbot foil.";
def baseline_plan_llm(text: str) -> str by llm(temperature=0.5);

obj PlanNarration {
    has analysis: str = "";
    has watch_for: str = "";
}

sem plan_narrate_llm = "Write a decision analysis for a startup founder. analysis: 3-5 sentences on WHY the recommended plan wins on survival dates, referencing the given dates/steps only — NEVER invent numbers. watch_for: 1-2 sentences on the earliest signal the plan is going wrong.";
def plan_narrate_llm(memo_summary: str, plan_steps: str) -> PlanNarration by llm(temperature=0.3);

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

def prefer_cache() -> bool {
    return os.environ.get("SPLITHORIZON_LIVE", "") != "1";
}

def move_from_dict(d: dict) -> MoveDraft {
    return MoveDraft(
        move=str(d.get("move", d.get("effect_tag", "noop"))),
        claim=str(d.get("claim", "")),
        effect_tag=str(d.get("effect_tag", d.get("move", "noop"))),
        module=str(d.get("module", "hire")),
        label=str(d.get("label", "")),
        burn_delta_pct=float(d.get("burn_delta_pct", 0.0)),
        mrr_delta_pct=float(d.get("mrr_delta_pct", 0.0)),
        headcount_delta=int(d.get("headcount_delta", 0)),
        milestone_shift_days=int(d.get("milestone_shift_days", 0))
    );
}

def classify_plan(plan: str) -> PlanClass {
    if prefer_cache() {
        return PlanClass(modules=[], restated="");
    }
    try {
        return classify_plan_llm(plan);
    } except Exception as e {
        print(f"[SplitHorizon] classify_plan fallback: {e}");
        return PlanClass(modules=[], restated="");
    }
}

def attack_from_dict(d: dict) -> AttackDraft {
    return AttackDraft(
        claim=str(d.get("claim", "")),
        severity=str(d.get("severity", "medium")),
        check_hint=str(d.get("check_hint", "runway")),
        stress_tag=str(d.get("stress_tag", "generic")),
        burn_delta_pct=float(d.get("burn_delta_pct", 0.0)),
        mrr_delta_pct=float(d.get("mrr_delta_pct", 0.0)),
        milestone_shift_days=int(d.get("milestone_shift_days", 0))
    );
}

def memo_from_dict(d: dict) -> MemoProse {
    return MemoProse(
        title=str(d.get("title", "Decision Memo")),
        recommended_reason=str(d.get("recommended_reason", "")),
        kill_shots=str(d.get("kill_shots", "")),
        open_risks=str(d.get("open_risks", "")),
        dissent=str(d.get("dissent", "")),
        date_line=str(d.get("date_line", ""))
    );
}

def blue_propose(branch_summary: str, question: str, prior_attacks: str, fixture_id: str, round_no: int) -> MoveDraft {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    key = f"blue_r{round_no}";
    if cache and key in cache {
        return move_from_dict(cache[key]);
    }
    if prefer_cache() and fixture_id {
        return MoveDraft(move="noop", claim="cache miss hold", effect_tag="noop", module="runway");
    }
    try {
        return blue_propose_llm(branch_summary, question, prior_attacks);
    } except Exception as e {
        print(f"[SplitHorizon] blue_propose retry after: {e}");
        time.sleep(LLM_RETRY_SLEEP);
        try {
            return blue_propose_llm(branch_summary, question, prior_attacks);
        } except Exception as e2 {
            print(f"[SplitHorizon] blue_propose fallback: {e2}");
            return MoveDraft(move="cut_burn", claim="Trim discretionary burn while the plan's risk is unresolved", effect_tag="cut_burn", module="runway");
        }
    }
}

def red_attack(branch_summary: str, move: str, fixture_id: str, round_no: int) -> AttackDraft {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    key = f"red_r{round_no}";
    if cache and key in cache {
        return attack_from_dict(cache[key]);
    }
    if prefer_cache() and fixture_id {
        return AttackDraft(claim="Generic burn stress", severity="medium", stress_tag="generic");
    }
    try {
        return red_attack_llm(branch_summary, move);
    } except Exception as e {
        print(f"[SplitHorizon] red_attack retry after: {e}");
        time.sleep(LLM_RETRY_SLEEP);
        try {
            return red_attack_llm(branch_summary, move);
        } except Exception as e2 {
            print(f"[SplitHorizon] red_attack fallback: {e2}");
            return AttackDraft(claim="Burn accelerates before milestone", severity="high", check_hint="alive_at_milestone", stress_tag="burn_spike");
        }
    }
}

def arbiter_narrate(scorecards: str, findings: str, fixture_id: str) -> MemoProse {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    if cache and "memo" in cache {
        return memo_from_dict(cache["memo"]);
    }
    if prefer_cache() and fixture_id {
        return MemoProse(title="Cached Memo", recommended_reason="Best surviving branch by cash-out", kill_shots="See findings", open_risks="Residual uncertainty", dissent="Dead branches", date_line="");
    }
    try {
        return arbiter_narrate_llm(scorecards, findings);
    } except Exception as e0 {
        print(f"[SplitHorizon] arbiter retry after: {e0}");
        time.sleep(LLM_RETRY_SLEEP);
        try {
            return arbiter_narrate_llm(scorecards, findings);
        } except Exception as e {
            print(f"[SplitHorizon] arbiter fallback: {e}");
            return MemoProse(title="Arbiter Decision Memo", recommended_reason="Longest cash-out among alive branches", kill_shots=findings[:500], open_risks="Uncertainty remains", dissent="Red findings", date_line="");
        }
    }
}

def plan_narrate(memo_summary: str, plan_steps: str, fixture_id: str) -> PlanNarration {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    if cache and "plan_narration" in cache {
        d = cache["plan_narration"];
        return PlanNarration(analysis=str(d.get("analysis", "")), watch_for=str(d.get("watch_for", "")));
    }
    if prefer_cache() and fixture_id {
        return PlanNarration(analysis="", watch_for="");
    }
    try {
        return plan_narrate_llm(memo_summary, plan_steps);
    } except Exception as e0 {
        print(f"[SplitHorizon] plan_narrate retry after: {e0}");
        time.sleep(LLM_RETRY_SLEEP);
        try {
            return plan_narrate_llm(memo_summary, plan_steps);
        } except Exception as e {
            print(f"[SplitHorizon] plan_narrate fallback: {e}");
            return PlanNarration(analysis="", watch_for="");
        }
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
        return f"One-shot baseline failed ({e}). Naive: hire two engineers immediately.";
    }
}
