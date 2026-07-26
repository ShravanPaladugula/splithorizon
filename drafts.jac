# Typed drafts — LLM proposes claims/moves NEVER figures.

import json;
import os;

obj MoveDraft {
    has move: str = "noop";
    has claim: str = "";
    has effect_tag: str = "noop";
    has module: str = "hire";
}

obj AttackDraft {
    has claim: str = "";
    has severity: str = "high";
    has check_hint: str = "alive_at_milestone";
    has stress_tag: str = "burn_spike";
}

obj MemoProse {
    has title: str;
    has recommended_reason: str;
    has kill_shots: str;
    has open_risks: str;
    has dissent: str;
    has date_line: str = "";
}

sem blue_propose_llm = "Propose one Blue move as effect_tag from {hire_2_eng, hire_1_eng_contractor, hire_0_hold, launch_full_oct, launch_staged, raise_soon, cut_burn, noop}. NEVER invent numbers.";
def blue_propose_llm(branch_summary: str, question: str, prior_attacks: str) -> MoveDraft by llm(temperature=0.3);

sem red_attack_llm = "Propose one Red attack qualitatively. stress_tag from {onboarding_freeze, burn_spike, launch_slip, revenue_miss, generic}. NEVER invent numbers.";
def red_attack_llm(branch_summary: str, move: str) -> AttackDraft by llm(temperature=0.4);

sem arbiter_narrate_llm = "Memo punchline is a DATE comparison. No confidence percentages.";
def arbiter_narrate_llm(scorecards: str, findings: str) -> MemoProse by llm(temperature=0.2);

sem baseline_plan_llm = "One-shot confident advice with no red-team — the chatbot foil.";
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

def prefer_cache() -> bool {
    return os.environ.get("SPLITHORIZON_LIVE", "") != "1";
}

def move_from_dict(d: dict) -> MoveDraft {
    return MoveDraft(
        move=str(d.get("move", d.get("effect_tag", "noop"))),
        claim=str(d.get("claim", "")),
        effect_tag=str(d.get("effect_tag", d.get("move", "noop"))),
        module=str(d.get("module", "hire"))
    );
}

def attack_from_dict(d: dict) -> AttackDraft {
    return AttackDraft(
        claim=str(d.get("claim", "")),
        severity=str(d.get("severity", "medium")),
        check_hint=str(d.get("check_hint", "runway")),
        stress_tag=str(d.get("stress_tag", "generic"))
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
        print(f"[SplitHorizon] blue_propose fallback: {e}");
        return MoveDraft(move="hire_1_eng_contractor", claim="Conservative hire mix", effect_tag="hire_1_eng_contractor", module="hire");
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
        print(f"[SplitHorizon] red_attack fallback: {e}");
        return AttackDraft(claim="Burn accelerates before milestone", severity="high", check_hint="alive_at_milestone", stress_tag="burn_spike");
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
    } except Exception as e {
        print(f"[SplitHorizon] arbiter fallback: {e}");
        return MemoProse(title="Arbiter Decision Memo", recommended_reason="Longest cash-out among alive branches", kill_shots=findings[:500], open_risks="Uncertainty remains", dissent="Red findings", date_line="");
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
