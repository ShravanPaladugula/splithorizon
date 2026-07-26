# Typed drafts — LLM proposes claims/moves NEVER figures.

import json;
import os;
import time;

glob LLM_RETRY_SLEEP: float = 1.0;

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

sem blue_propose_llm = "You are Blue for THIS founder's plan only. Propose ONE concrete move that directly serves THAT plan — never a stock 'hire two engineers' or 'start a raise' unless the plan literally says that. If they said hire 10, propose variants around THAT count (full / half / contractors / hold). Output: label (<=6 words, imperative, specific), claim (why it wins on survival), module (finance|management|launch|publicity), effect_tag='custom', and bounded effects: burn_delta_pct (-40..80), mrr_delta_pct (-50..60), headcount_delta (-3..5), milestone_shift_days (-45..90). Effects must match the move. Avoid repeating moves already in the branch summary.";
def blue_propose_llm(branch_summary: str, question: str, prior_attacks: str) -> MoveDraft by llm(temperature=0.3);

sem red_attack_llm = "You are Red. Attack the CURRENT move with a failure mode specific to THIS plan's metrics (ramp/productivity for hiring, CAC for ads, utilization for equipment, ship blockers for launch — not a generic fundraising rant). Output claim, severity (low|medium|high), check_hint='alive_at_milestone', stress_tag='custom', burn_delta_pct (0..30), mrr_delta_pct (-40..0), milestone_shift_days (0..45).";
def red_attack_llm(branch_summary: str, move: str) -> AttackDraft by llm(temperature=0.4);

sem classify_plan_llm = "Classify a startup founder's stated plan into consult desks from exactly {finance, management, launch, publicity}. Pick 1-3: finance = raise/burn/cash/pricing/MRR/runway; management = hiring/headcount/contractors/infra/org; launch = shipping/releasing/go-live/product milestone; publicity = ads/campaigns/influencers/marketing/GTM buzz. Most plans that cost money should include finance. restated = one sentence restating the plan as an A-vs-B decision.";
def classify_plan_llm(plan: str) -> PlanClass by llm(temperature=0.1);

sem intake_followups_llm = "You are intake for a startup survival simulator. Given the founder's plan and what is already known, write up to 3 SHORT follow-up questions that measure WHETHER THIS SPECIFIC PLAN works — adaptive metrics (e.g. hire plan → loaded cost + ramp + what slips if you hold; ads → spend + CAC + payback weeks; launch → blockers + ship risk; product bet → activation/retention signal). NEVER ask generic 'how much cash in 90 days' or 'what does burn do' unless the plan is literally about fundraising. Never re-ask known facts. Each: id = snake_case key, prompt = one plain-English sentence, qtype = 'number' or 'text', placeholder = short example.";
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
    # Offline drafts unless explicitly live. Missing litellm / Gemini quota
    # must never block the war room.
    return os.environ.get("SPLITHORIZON_LIVE", "") != "1";
}

def llm_enabled() -> bool {
    if prefer_cache() {
        return False;
    }
    try {
        import litellm;
        return True;
    } except Exception {
        return False;
    }
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
    if not llm_enabled() {
        return PlanClass(modules=[], restated="");
    }
    try {
        return classify_plan_llm(plan);
    } except Exception as e {
        print(f"[SplitHorizon] classify_plan fallback: {e}");
        return PlanClass(modules=[], restated="");
    }
}

def fallback_intake_followups(plan: str) -> IntakeQSet {
    # Offline / rate-limit path — still force plan-specific questions so intake
    # never collapses to "shape choice → war room".
    t = str(plan).lower();
    qs: list = [];
    if ("ad" in t) or ("ads" in t) or ("advertis" in t) or ("instagram" in t) or ("tiktok" in t) or ("influencer" in t) or ("campaign" in t) {
        qs = [
            IntakeQ(id="spend_usd", prompt="How much cash will you put into this campaign in the first 30 days (USD)?", qtype="number", placeholder="e.g. 30000"),
            IntakeQ(id="channel", prompt="Which channel carries most of that spend?", qtype="text", placeholder="e.g. Instagram / Google / influencers"),
            IntakeQ(id="payback_weeks", prompt="In how many weeks do you need paid acquisition to pay back, or you kill it?", qtype="number", placeholder="e.g. 8")
        ];
    } elif ("hire" in t) or ("hiring" in t) or ("engineer" in t) or ("contractor" in t) or ("headcount" in t) or ("recruit" in t) {
        qs = [
            IntakeQ(id="loaded_cost", prompt="Fully loaded monthly cost of the hire(s) you're tempted to make (USD / month)?", qtype="number", placeholder="e.g. 28000"),
            IntakeQ(id="ramp_months", prompt="How many months until that hire is productive?", qtype="number", placeholder="e.g. 3"),
            IntakeQ(id="slip_if_hold", prompt="What slips on the milestone if you hold hiring instead?", qtype="text", placeholder="e.g. mobile app slips 6 weeks")
        ];
    } elif ("raise" in t) or ("fundrais" in t) or ("bridge" in t) or ("dilution" in t) or ("series" in t) {
        qs = [
            IntakeQ(id="raise_target", prompt="How much are you trying to raise (USD)?", qtype="number", placeholder="e.g. 1500000"),
            IntakeQ(id="close_months", prompt="Months until you expect a term sheet (0 if already circling)?", qtype="number", placeholder="e.g. 4"),
            IntakeQ(id="runway_need", prompt="How many months of runway do you need after close?", qtype="number", placeholder="e.g. 18")
        ];
    } elif ("office" in t) or ("relocat" in t) or ("lease" in t) or ("rent" in t) {
        qs = [
            IntakeQ(id="move_cost", prompt="One-time move / buildout cost (USD)?", qtype="number", placeholder="e.g. 80000"),
            IntakeQ(id="rent_delta", prompt="Monthly rent delta vs today (USD / month)?", qtype="number", placeholder="e.g. 12000"),
            IntakeQ(id="move_date", prompt="When would you actually move?", qtype="text", placeholder="e.g. 2026-09-01")
        ];
    } elif ("price" in t) or ("pricing" in t) or ("discount" in t) or ("packag" in t) {
        qs = [
            IntakeQ(id="price_change_pct", prompt="What % price change are you considering (negative = cut)?", qtype="number", placeholder="e.g. 20"),
            IntakeQ(id="customers_touched", prompt="How many current customers does this touch?", qtype="number", placeholder="e.g. 40"),
            IntakeQ(id="churn_fear_pct", prompt="What churn % would make you roll it back?", qtype="number", placeholder="e.g. 8")
        ];
    } elif ("launch" in t) or ("ship" in t) or ("release" in t) or ("go-live" in t) or ("golive" in t) {
        qs = [
            IntakeQ(id="launch_cash", prompt="One-time launch / GTM cash outlay (USD)?", qtype="number", placeholder="e.g. 25000"),
            IntakeQ(id="launch_burn_bump", prompt="Extra monthly burn around launch (USD / month)?", qtype="number", placeholder="e.g. 8000"),
            IntakeQ(id="launch_risk", prompt="What is the single biggest thing that can slip the date?", qtype="text", placeholder="e.g. SOC2 / App Store review")
        ];
    } else {
        qs = [
            IntakeQ(id="leading_metric", prompt="What single leading metric proves this plan is working?", qtype="text", placeholder="e.g. weekly active creators / activation rate"),
            IntakeQ(id="weeks_to_signal", prompt="In how many weeks must that metric move, or you stop?", qtype="number", placeholder="e.g. 6"),
            IntakeQ(id="kill_criteria", prompt="What result would make you kill this plan immediately?", qtype="text", placeholder="e.g. metric flat for 3 weeks")
        ];
    }
    return IntakeQSet(questions=qs);
}

def intake_followups(plan: str, known: str) -> IntakeQSet {
    if not llm_enabled() {
        return fallback_intake_followups(plan);
    }
    try {
        qset = intake_followups_llm(plan, known);
        if not qset.questions {
            return fallback_intake_followups(plan);
        }
        return qset;
    } except Exception as e {
        print(f"[SplitHorizon] intake_followups fallback: {e}");
        return fallback_intake_followups(plan);
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

def normalize_draft_areas(raw: list) -> list {
    allowed = ["finance", "management", "launch", "publicity"];
    out: list = [];
    for m in raw {
        a = str(m).lower().strip();
        if a in ["hire", "hiring"] { a = "management"; }
        elif a in ["runway", "money"] { a = "finance"; }
        elif a in ["marketing", "ads", "pr"] { a = "publicity"; }
        if a in allowed and a not in out {
            out.append(a);
        }
    }
    return out;
}

def infer_areas_from_plan(question: str) -> list {
    t = _q_lower(question);
    mods: list = [];
    if ("hire" in t) or ("engineer" in t) or ("headcount" in t) or ("contractor" in t) or ("infra" in t) or ("office" in t) or ("fire" in t) or ("layoff" in t) {
        mods.append("management");
    }
    if ("launch" in t) or ("ship" in t) or ("release" in t) or ("go-live" in t) or ("golive" in t) or ("mvp" in t) {
        mods.append("launch");
    }
    if ("ad" in t) or ("marketing" in t) or ("influencer" in t) or ("campaign" in t) or ("publicity" in t) or ("gtm" in t) {
        mods.append("publicity");
    }
    if ("raise" in t) or ("fundrais" in t) or ("burn" in t) or ("runway" in t) or ("price" in t) or ("mrr" in t) or ("cash" in t) or ("spend" in t) or ("buy" in t) or ("purchase" in t) or ("printer" in t) or ("equipment" in t) or ("capex" in t) or ("machine" in t) {
        mods.append("finance");
    }
    if not mods {
        mods = ["finance"];
    }
    return mods;
}

def pick_area(areas: list, question: str, round_no: int, variety: int = 0) -> str {
    cleaned = normalize_draft_areas(areas) if areas else [];
    if not cleaned {
        cleaned = infer_areas_from_plan(question);
    }
    idx = (round_no - 1 + variety) % len(cleaned);
    return cleaned[idx];
}

def is_equipment_plan(question: str) -> bool {
    t = _q_lower(question);
    return ("buy" in t) or ("purchase" in t) or ("printer" in t) or ("equipment" in t) or ("machine" in t) or ("capex" in t) or ("gear" in t) or ("hardware" in t) or ("tooling" in t);
}

def parse_hire_count(question: str) -> int {
    # Pull an explicit headcount from the plan ("hire 10 engineers") — default 2.
    import re;
    t = str(question).lower();
    m = re.search(r"(?:hire|hiring|add|recruit)\s+(\d{1,3})", t);
    if m {
        n = int(m.group(1));
        if n < 1 { return 1; }
        if n > 50 { return 50; }
        return n;
    }
    m2 = re.search(r"(\d{1,3})\s+(?:product\s+)?(?:engineers?|devs?|designers?|people|hires?|seats?)", t);
    if m2 {
        n = int(m2.group(1));
        if n < 1 { return 1; }
        if n > 50 { return 50; }
        return n;
    }
    return 2;
}

def hire_burn_pct_for(n: int) -> float {
    # Rough fully-loaded burn shock as % of current burn — capped.
    pct = float(n) * 12.0;
    if pct < 8.0 { return 8.0; }
    if pct > 80.0 { return 80.0; }
    return pct;
}

def is_hire_plan(question: str) -> bool {
    t = _q_lower(question);
    return ("hire" in t) or ("hiring" in t) or ("engineer" in t) or ("headcount" in t) or ("contractor" in t) or ("recruit" in t) or ("staff" in t);
}

def area_blue_fallback(area: str, question: str, round_no: int) -> MoveDraft {
    # Desk-specialized Blue agents — moves adapt to the stated plan.
    a = str(area);
    opts: list = [];
    if is_equipment_plan(question) {
        opts = [
            MoveDraft(move="custom", claim="Buy the full equipment set now to unlock capacity before the milestone", effect_tag="custom", module="finance", label="Buy both now", burn_delta_pct=8.0, mrr_delta_pct=18.0, headcount_delta=0, milestone_shift_days=-7),
            MoveDraft(move="custom", claim="Buy one unit first; prove utilization before the second purchase", effect_tag="custom", module="finance", label="Buy one first", burn_delta_pct=4.0, mrr_delta_pct=9.0, headcount_delta=0, milestone_shift_days=0),
            MoveDraft(move="custom", claim="Lease / finance the gear to protect cash while adding capacity", effect_tag="custom", module="finance", label="Lease instead of buy", burn_delta_pct=12.0, mrr_delta_pct=12.0, headcount_delta=0, milestone_shift_days=-3),
            MoveDraft(move="custom", claim="Do not buy — max out current capacity and delay capex", effect_tag="custom", module="finance", label="Do not buy — wait", burn_delta_pct=-5.0, mrr_delta_pct=2.0, headcount_delta=0, milestone_shift_days=14)
        ];
        idx = (round_no - 1) % len(opts);
        return opts[idx];
    }
    if is_hire_plan(question) or a == "management" {
        tq = str(question).lower();
        if ("fire" in tq) or ("layoff" in tq) or ("let go" in tq) or ("cut headcount" in tq) or ("reduce staff" in tq) {
            opts = [
                MoveDraft(move="custom", claim="Cut two seats now to protect cash-out past the milestone", effect_tag="custom", module="management", label="Fire two employees", burn_delta_pct=-35.0, mrr_delta_pct=0.0, headcount_delta=-2, milestone_shift_days=7),
                MoveDraft(move="custom", claim="Cut one seat and freeze backfills — smaller cut, less delivery risk", effect_tag="custom", module="management", label="Fire one + freeze", burn_delta_pct=-18.0, mrr_delta_pct=0.0, headcount_delta=-1, milestone_shift_days=3),
                MoveDraft(move="custom", claim="Do not fire; re-scope the milestone instead", effect_tag="custom", module="management", label="No layoff — re-scope", burn_delta_pct=0.0, mrr_delta_pct=0.0, headcount_delta=0, milestone_shift_days=14)
            ];
        } else {
            n = parse_hire_count(question);
            half = n // 2 if n > 1 else 1;
            if half < 1 { half = 1; }
            full_pct = hire_burn_pct_for(n);
            half_pct = hire_burn_pct_for(half);
            hc_full = n if n <= 5 else 5;
            hc_half = half if half <= 5 else 3;
            opts = [
                MoveDraft(move="custom", claim=f"Hire all {n} seats now so the milestone still has capacity", effect_tag="custom", module="management", label=f"Hire all {n}", burn_delta_pct=full_pct, mrr_delta_pct=4.0, headcount_delta=hc_full, milestone_shift_days=-7),
                MoveDraft(move="custom", claim=f"Hire {half} first; prove ramp before opening the rest of the {n}", effect_tag="custom", module="management", label=f"Hire {half} first", burn_delta_pct=half_pct, mrr_delta_pct=2.0, headcount_delta=hc_half, milestone_shift_days=0),
                MoveDraft(move="custom", claim="Use contractors / tools instead of full-time seats this cycle", effect_tag="custom", module="management", label="Contractors instead", burn_delta_pct=half_pct * 0.7, mrr_delta_pct=1.0, headcount_delta=0, milestone_shift_days=3),
                MoveDraft(move="custom", claim="Hold hiring and re-scope the milestone without new seats", effect_tag="custom", module="management", label="Hold — no new seats", burn_delta_pct=-5.0, mrr_delta_pct=0.0, headcount_delta=0, milestone_shift_days=21)
            ];
        }
        idx = (round_no - 1) % len(opts);
        return opts[idx];
    }
    if a == "finance" {
        opts = [
            MoveDraft(move="custom", claim="Fund the plan from a raise so cash-out stays past the milestone", effect_tag="custom", module="finance", label="Fund via raise", burn_delta_pct=5.0, mrr_delta_pct=0.0, headcount_delta=0, milestone_shift_days=7),
            MoveDraft(move="custom", claim="Run a tight budget — only the minimum cash the plan needs", effect_tag="custom", module="finance", label="Tight budget only", burn_delta_pct=-12.0, mrr_delta_pct=0.0, headcount_delta=0, milestone_shift_days=5),
            MoveDraft(move="custom", claim="Fund the plan from pricing / MRR lift instead of new spend", effect_tag="custom", module="finance", label="Fund from pricing", burn_delta_pct=0.0, mrr_delta_pct=22.0, headcount_delta=0, milestone_shift_days=0)
        ];
    } elif a == "launch" {
        opts = [
            MoveDraft(move="custom", claim="Ship the full public launch on the milestone date", effect_tag="custom", module="launch", label="Full ship", burn_delta_pct=15.0, mrr_delta_pct=10.0, headcount_delta=0, milestone_shift_days=0),
            MoveDraft(move="custom", claim="Soft-launch to a limited cohort first to de-risk", effect_tag="custom", module="launch", label="Staged soft launch", burn_delta_pct=8.0, mrr_delta_pct=5.0, headcount_delta=0, milestone_shift_days=10),
            MoveDraft(move="custom", claim="Slip the ship date to protect cash-out if blockers remain", effect_tag="custom", module="launch", label="Slip the date", burn_delta_pct=0.0, mrr_delta_pct=0.0, headcount_delta=0, milestone_shift_days=21)
        ];
    } else {
        # publicity
        opts = [
            MoveDraft(move="custom", claim="Commit paid acquisition to hit signup goals before the milestone", effect_tag="custom", module="publicity", label="Full paid push", burn_delta_pct=40.0, mrr_delta_pct=14.0, headcount_delta=0, milestone_shift_days=0),
            MoveDraft(move="custom", claim="Pilot a smaller campaign first to validate CAC before scaling", effect_tag="custom", module="publicity", label="Pilot campaign", burn_delta_pct=16.0, mrr_delta_pct=5.0, headcount_delta=0, milestone_shift_days=7),
            MoveDraft(move="custom", claim="Shift to organic/creator channels to protect runway", effect_tag="custom", module="publicity", label="Organic / creators", burn_delta_pct=-6.0, mrr_delta_pct=4.0, headcount_delta=0, milestone_shift_days=14)
        ];
    }
    idx = (round_no - 1) % len(opts);
    return opts[idx];
}

def area_red_fallback(area: str, question: str, move: str, round_no: int) -> AttackDraft {
    a = str(area);
    t = _q_lower(question + " " + move);
    if is_equipment_plan(t) {
        return AttackDraft(claim="Equipment Red: utilization misses — gear sits idle while payments pull cash-out forward", severity="high", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=15.0, mrr_delta_pct=-12.0, milestone_shift_days=14);
    }
    if is_hire_plan(t) or a == "management" {
        return AttackDraft(claim="Management Red: ramp misses — new seats cost for months before productivity moves the milestone", severity="high", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=12.0, mrr_delta_pct=-4.0, milestone_shift_days=21);
    }
    if ("ad" in t) or ("campaign" in t) or ("cac" in t) or a == "publicity" {
        return AttackDraft(claim="Publicity Red: CAC spikes and conversion misses — spend burns before MRR lands", severity="high", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=12.0, mrr_delta_pct=-20.0, milestone_shift_days=14);
    }
    if ("launch" in t) or ("ship" in t) or a == "launch" {
        return AttackDraft(claim="Launch Red: ship blockers slip the date while burn keeps running", severity="high", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=6.0, mrr_delta_pct=-8.0, milestone_shift_days=21);
    }
    if a == "finance" {
        return AttackDraft(claim="Finance Red: funding or pricing lift lands late — cash-out crosses ahead of the milestone", severity="high", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=8.0, mrr_delta_pct=-12.0, milestone_shift_days=14);
    }
    return AttackDraft(claim="Red: the plan's leading metric misses while cost still lands — cash-out moves earlier than the milestone", severity="high", check_hint="alive_at_milestone", stress_tag="custom", burn_delta_pct=10.0, mrr_delta_pct=-10.0, milestone_shift_days=14);
}

def scenario_blue_fallback(question: str, round_no: int) -> MoveDraft {
    area = pick_area([], question, round_no, 0);
    return area_blue_fallback(area, question, round_no);
}

def scenario_red_fallback(question: str, move: str, round_no: int) -> AttackDraft {
    area = pick_area([], question + " " + move, round_no, 0);
    return area_red_fallback(area, question, move, round_no);
}

def is_cached_fixture(fixture_id: str) -> bool {
    return fixture_id in ["interlock", "hire", "launch", "runway"];
}

def blue_propose(branch_summary: str, question: str, prior_attacks: str, fixture_id: str, round_no: int, variety: int = 0, areas: list = []) -> MoveDraft {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    key = f"blue_r{round_no}";
    if cache and key in cache and variety == 0 {
        return move_from_dict(cache[key]);
    }
    pick = round_no + variety;
    if fixture_id == "custom" or not is_cached_fixture(fixture_id) {
        area = pick_area(areas, question, round_no, variety);
        return area_blue_fallback(area, question, pick);
    }
    if prefer_cache() {
        area = pick_area(areas, question, round_no, variety);
        return area_blue_fallback(area, question, pick);
    }
    try {
        return blue_propose_llm(branch_summary, question, prior_attacks);
    } except Exception as e {
        print(f"[SplitHorizon] blue_propose fallback: {e}");
        area = pick_area(areas, question, round_no, variety);
        return area_blue_fallback(area, question, pick);
    }
}

def red_attack(question: str, branch_summary: str, move: str, fixture_id: str, round_no: int, areas: list = []) -> AttackDraft {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    key = f"red_r{round_no}";
    if cache and key in cache {
        return attack_from_dict(cache[key]);
    }
    context = str(question) + " " + str(branch_summary) + " " + str(move);
    if fixture_id == "custom" or not is_cached_fixture(fixture_id) {
        area = pick_area(areas, context, round_no, 0);
        return area_red_fallback(area, question, move, round_no);
    }
    if prefer_cache() {
        area = pick_area(areas, context, round_no, 0);
        return area_red_fallback(area, question, move, round_no);
    }
    try {
        return red_attack_llm(branch_summary, move);
    } except Exception as e {
        print(f"[SplitHorizon] red_attack fallback: {e}");
        area = pick_area(areas, context, round_no, 0);
        return area_red_fallback(area, question, move, round_no);
    }
}

def arbiter_narrate(scorecards: str, findings: str, fixture_id: str) -> MemoProse {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    if cache and "memo" in cache {
        return memo_from_dict(cache["memo"]);
    }
    # Custom + offline: empty shells — engine builds decision-specific intel.
    if prefer_cache() or fixture_id == "custom" or not is_cached_fixture(fixture_id) {
        return MemoProse(title="Decision memo", recommended_reason="", kill_shots="", open_risks="", dissent="", date_line="");
    }
    try {
        return arbiter_narrate_llm(scorecards, findings);
    } except Exception as e {
        print(f"[SplitHorizon] arbiter fallback: {e}");
        return MemoProse(title="Arbiter Decision Memo", recommended_reason="Longest cash-out among alive branches", kill_shots=findings[:500], open_risks="Uncertainty remains", dissent="Red findings", date_line="");
    }
}

def plan_narrate(memo_summary: str, plan_steps: str, fixture_id: str) -> PlanNarration {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    if cache and "plan_narration" in cache {
        d = cache["plan_narration"];
        return PlanNarration(analysis=str(d.get("analysis", "")), watch_for=str(d.get("watch_for", "")));
    }
    if prefer_cache() or fixture_id == "custom" or not is_cached_fixture(fixture_id) {
        # Empty — engine.jac builds plan/analysis from verified dates + desk playbooks.
        return PlanNarration(analysis="", watch_for="");
    }
    try {
        return plan_narrate_llm(memo_summary, plan_steps);
    } except Exception as e {
        print(f"[SplitHorizon] plan_narrate fallback: {e}");
        return PlanNarration(analysis="", watch_for="");
    }
}

def baseline_plan(text: str, fixture_id: str) -> str {
    cache = load_fixture_cache(fixture_id) if fixture_id else {};
    if cache and "baseline" in cache {
        return str(cache["baseline"]);
    }
    if prefer_cache() or fixture_id == "custom" or not is_cached_fixture(fixture_id) {
        return "Chatbot foil: just do it — spend/hire now and hope the milestone lands. (No red-team, no cash-out date.)";
    }
    try {
        return baseline_plan_llm(text);
    } except Exception as e {
        return f"One-shot baseline failed ({e}). Naive: execute the plan immediately without checking cash-out.";
    }
}
