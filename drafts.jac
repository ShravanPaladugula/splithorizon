# Typed drafts — LLM proposes claims/moves NEVER figures.

import json;
import os;
import time;

glob LLM_RETRY_SLEEP: float = 8.0;

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

obj IntakeQ {
    has id: str = "";
    has prompt: str = "";
    has qtype: str = "text";
    has placeholder: str = "";
}

obj IntakeQSet {
    has questions: list[IntakeQ] = [];
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

sem intake_followups_llm = "You are intake for a startup survival simulator. Given the founder's plan and what is already known about the company, write up to 3 SHORT follow-up questions whose answers would materially change how the plan plays out (costs, timelines, dependencies, current traction specific to THIS plan — e.g. for an ads plan ask CAC or conversion; for an office move ask relocation cost). Never re-ask anything in the known facts. Each: id = snake_case key, prompt = one plain-English sentence, qtype = 'number' or 'text', placeholder = short example value.";
def intake_followups_llm(plan: str, known: str) -> IntakeQSet by llm(temperature=0.2);

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

def intake_followups(plan: str, known: str) -> IntakeQSet {
    if prefer_cache() {
        return IntakeQSet(questions=[]);
    }
    try {
        return intake_followups_llm(plan, known);
    } except Exception as e {
        print(f"[SplitHorizon] intake_followups retry after: {e}");
        time.sleep(LLM_RETRY_SLEEP);
        try {
            return intake_followups_llm(plan, known);
        } except Exception as e2 {
            print(f"[SplitHorizon] intake_followups fallback: {e2}");
            return IntakeQSet(questions=[]);
        }
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

def _q_lower(s: str) -> str {
    return str(s).lower();
}

def scenario_blue_fallback(question: str, round_no: int) -> MoveDraft {
    # Plan-specific fallbacks when LLM is offline/rate-limited — NEVER default to hiring.
    t = _q_lower(question);
    opts: list = [];
    if ("ad" in t) or ("marketing" in t) or ("influencer" in t) or ("campaign" in t) or ("cac" in t) {
        opts = [
            MoveDraft(move="custom", claim="Commit the full acquisition spend to hit the signup goal before the milestone", effect_tag="custom", module="launch", label="Run full acquisition spend", burn_delta_pct=45.0, mrr_delta_pct=12.0, headcount_delta=0, milestone_shift_days=0),
            MoveDraft(move="custom", claim="Pilot a smaller spend first to validate conversion before scaling", effect_tag="custom", module="launch", label="Pilot smaller spend first", burn_delta_pct=18.0, mrr_delta_pct=5.0, headcount_delta=0, milestone_shift_days=7),
            MoveDraft(move="custom", claim="Shift to organic/referral channels to protect runway", effect_tag="custom", module="runway", label="Pivot to organic channels", burn_delta_pct=-8.0, mrr_delta_pct=3.0, headcount_delta=0, milestone_shift_days=14)
        ];
    } elif ("price" in t) or ("pricing" in t) or ("raise price" in t) or ("enterprise" in t and "price" in t) {
        opts = [
            MoveDraft(move="custom", claim="Raise prices now and accept some churn for higher ARPU", effect_tag="custom", module="runway", label="Raise prices now", burn_delta_pct=0.0, mrr_delta_pct=25.0, headcount_delta=0, milestone_shift_days=0),
            MoveDraft(move="custom", claim="Grandfather existing customers; new logo pricing only", effect_tag="custom", module="launch", label="New-logo pricing only", burn_delta_pct=2.0, mrr_delta_pct=12.0, headcount_delta=0, milestone_shift_days=5),
            MoveDraft(move="custom", claim="Hold price and compete on packaging instead", effect_tag="custom", module="runway", label="Hold price, repackage", burn_delta_pct=5.0, mrr_delta_pct=4.0, headcount_delta=0, milestone_shift_days=10)
        ];
    } elif ("office" in t) or ("relocat" in t) or ("second location" in t) or ("expand to" in t) {
        opts = [
            MoveDraft(move="custom", claim="Open the second office now to unlock hiring and customers", effect_tag="custom", module="runway", label="Open second office now", burn_delta_pct=35.0, mrr_delta_pct=8.0, headcount_delta=2, milestone_shift_days=0),
            MoveDraft(move="custom", claim="Start with a small hub and hybrid travel instead of a full office", effect_tag="custom", module="runway", label="Small hub + hybrid", burn_delta_pct=12.0, mrr_delta_pct=3.0, headcount_delta=0, milestone_shift_days=10),
            MoveDraft(move="custom", claim="Stay remote and redeploy rent budget into GTM", effect_tag="custom", module="runway", label="Stay remote, fund GTM", burn_delta_pct=-5.0, mrr_delta_pct=6.0, headcount_delta=0, milestone_shift_days=0)
        ];
    } elif ("client" in t) or ("customer" in t) or ("sales" in t) or ("outbound" in t) or ("pipeline" in t) {
        opts = [
            MoveDraft(move="custom", claim="Stand up a focused outbound motion to land the next customers", effect_tag="custom", module="launch", label="Stand up outbound sales", burn_delta_pct=22.0, mrr_delta_pct=15.0, headcount_delta=1, milestone_shift_days=-5),
            MoveDraft(move="custom", claim="Founder-led sales only until conversion is proven", effect_tag="custom", module="launch", label="Founder-led sales only", burn_delta_pct=5.0, mrr_delta_pct=8.0, headcount_delta=0, milestone_shift_days=7),
            MoveDraft(move="custom", claim="Partner/channel motion instead of direct sales headcount", effect_tag="custom", module="launch", label="Partner channel motion", burn_delta_pct=10.0, mrr_delta_pct=10.0, headcount_delta=0, milestone_shift_days=14)
        ];
    } elif ("hire" in t) or ("engineer" in t) or ("headcount" in t) or ("contractor" in t) {
        opts = [
            MoveDraft(move="hire_2_eng", claim="Hire two engineers to protect the milestone", effect_tag="hire_2_eng", module="hire", label="Hire two engineers"),
            MoveDraft(move="hire_1_eng_contractor", claim="One engineer plus contractor to limit burn", effect_tag="hire_1_eng_contractor", module="hire", label="One eng + contractor"),
            MoveDraft(move="hire_0_hold", claim="Hold hiring and slip the milestone if needed", effect_tag="hire_0_hold", module="hire", label="Hold hiring")
        ];
    } elif ("raise" in t) or ("fundrais" in t) or ("burn" in t) or ("runway" in t) {
        opts = [
            MoveDraft(move="raise_soon", claim="Start the raise immediately", effect_tag="raise_soon", module="runway", label="Start raising"),
            MoveDraft(move="cut_burn", claim="Cut discretionary burn to extend runway first", effect_tag="cut_burn", module="runway", label="Cut discretionary burn"),
            MoveDraft(move="custom", claim="Bridge: light cut plus soft raise conversations", effect_tag="custom", module="runway", label="Bridge cut + soft raise", burn_delta_pct=-8.0, mrr_delta_pct=0.0, headcount_delta=0, milestone_shift_days=5)
        ];
    } else {
        opts = [
            MoveDraft(move="custom", claim="Execute the stated plan at full intensity", effect_tag="custom", module="runway", label="Execute plan fully", burn_delta_pct=20.0, mrr_delta_pct=8.0, headcount_delta=0, milestone_shift_days=0),
            MoveDraft(move="custom", claim="Stage a smaller version of the plan to protect cash-out", effect_tag="custom", module="runway", label="Stage a smaller version", burn_delta_pct=8.0, mrr_delta_pct=3.0, headcount_delta=0, milestone_shift_days=10),
            MoveDraft(move="custom", claim="Defer the plan and preserve runway until the milestone is safer", effect_tag="custom", module="runway", label="Defer, preserve runway", burn_delta_pct=-6.0, mrr_delta_pct=0.0, headcount_delta=0, milestone_shift_days=21)
        ];
    }
    idx = (round_no - 1) % len(opts);
    return opts[idx];
}

def scenario_red_fallback(question: str, move: str, round_no: int) -> AttackDraft {
    t = _q_lower(question + " " + move);
    if ("ad" in t) or ("marketing" in t) or ("influencer" in t) or ("campaign" in t) {
        return AttackDraft(claim="Acquisition spend fails to convert; CAC spikes and MRR does not land before the milestone", severity="high", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=12.0, mrr_delta_pct=-20.0, milestone_shift_days=14);
    }
    if ("price" in t) or ("pricing" in t) {
        return AttackDraft(claim="Price hike triggers churn and stalled expansion revenue before the milestone", severity="high", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=5.0, mrr_delta_pct=-25.0, milestone_shift_days=10);
    }
    if ("office" in t) or ("relocat" in t) {
        return AttackDraft(claim="Office build-out overruns and distracts the team, delaying the milestone", severity="medium", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=18.0, mrr_delta_pct=-5.0, milestone_shift_days=21);
    }
    if ("client" in t) or ("sales" in t) or ("outbound" in t) {
        return AttackDraft(claim="Sales cycle slips; pipeline does not convert before cash pressure hits", severity="high", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=10.0, mrr_delta_pct=-15.0, milestone_shift_days=20);
    }
    if ("hire" in t) or ("engineer" in t) {
        return AttackDraft(claim="Onboarding freeze: new hires raise burn before they move the milestone", severity="high", check_hint="alive_at_milestone", stress_tag="onboarding_freeze", burn_delta_pct=8.0, mrr_delta_pct=0.0, milestone_shift_days=21);
    }
    return AttackDraft(claim="The plan's costs land before its upside; cash-out moves ahead of the milestone", severity="high", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=10.0, mrr_delta_pct=-10.0, milestone_shift_days=14);
}

def is_cached_fixture(fixture_id: str) -> bool {
    return fixture_id in ["interlock", "hire", "launch", "runway"];
}

def blue_propose(branch_summary: str, question: str, prior_attacks: str, fixture_id: str, round_no: int, variety: int = 0) -> MoveDraft {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    key = f"blue_r{round_no}";
    if cache and key in cache and variety == 0 {
        return move_from_dict(cache[key]);
    }
    # Custom / unknown fixtures: always try LLM when live; else scenario-aware fallback.
    pick = round_no + variety;
    if fixture_id == "custom" or not is_cached_fixture(fixture_id) {
        if not prefer_cache() {
            try {
                return blue_propose_llm(branch_summary, question, prior_attacks);
            } except Exception as e {
                print(f"[SplitHorizon] blue_propose retry after: {e}");
                time.sleep(LLM_RETRY_SLEEP);
                try {
                    return blue_propose_llm(branch_summary, question, prior_attacks);
                } except Exception as e2 {
                    print(f"[SplitHorizon] blue_propose scenario fallback: {e2}");
                }
            }
        }
        return scenario_blue_fallback(question, pick);
    }
    if prefer_cache() {
        return scenario_blue_fallback(question, pick);
    }
    try {
        return blue_propose_llm(branch_summary, question, prior_attacks);
    } except Exception as e {
        print(f"[SplitHorizon] blue_propose fallback: {e}");
        return scenario_blue_fallback(question, pick);
    }
}

def red_attack(question: str, branch_summary: str, move: str, fixture_id: str, round_no: int) -> AttackDraft {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    key = f"red_r{round_no}";
    if cache and key in cache {
        return attack_from_dict(cache[key]);
    }
    context = str(question) + " " + str(branch_summary) + " " + str(move);
    if fixture_id == "custom" or not is_cached_fixture(fixture_id) {
        if not prefer_cache() {
            try {
                return red_attack_llm(branch_summary, move);
            } except Exception as e {
                print(f"[SplitHorizon] red_attack retry after: {e}");
                time.sleep(LLM_RETRY_SLEEP);
                try {
                    return red_attack_llm(branch_summary, move);
                } except Exception as e2 {
                    print(f"[SplitHorizon] red_attack scenario fallback: {e2}");
                }
            }
        }
        return scenario_red_fallback(context, move, round_no);
    }
    if prefer_cache() {
        return scenario_red_fallback(context, move, round_no);
    }
    try {
        return red_attack_llm(branch_summary, move);
    } except Exception as e {
        print(f"[SplitHorizon] red_attack fallback: {e}");
        return scenario_red_fallback(context, move, round_no);
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
