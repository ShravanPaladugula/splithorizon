# Agents — every one of these is a live LLM call. No canned moves, no template prose.
#
# Division of labour that makes the product honest:
#   the model reads the founder's actual plan and proposes WHAT to do and HOW BIG;
#   verifiers.jac owns every date and every dollar that lands in a score.
# If the model is unreachable we raise. We never substitute invented content —
# fabricated advice that looks real is worse than an error.

import from jaclang.byllm.lib { Model }

import json;
import os;
import time;

# Two tiers, because Groq's free tier bills a per-model token/day budget:
#   llm      - high volume (a dozen Blue/Red drafts per run), small structured outputs
#   llm_lead - one call per run, writes the answer the founder actually reads
# Each Groq model carries its own tokens/day budget, so splitting the work also
# doubles the daily headroom. llama-3.1-8b is deliberately NOT used: it cannot hold
# a strict JSON schema, which is the whole contract here.
glob LLM_MODEL: str = os.environ.get("SPLITHORIZON_MODEL", "groq/openai/gpt-oss-20b");
glob LLM_LEAD_MODEL: str = os.environ.get("SPLITHORIZON_LEAD_MODEL", "groq/openai/gpt-oss-120b");
glob llm = Model(model_name=LLM_MODEL);
glob llm_lead = Model(model_name=LLM_LEAD_MODEL);

glob LLM_ATTEMPTS: int = 3;
glob LLM_BACKOFF: float = 1.5;

# ---------------------------------------------------------------- typed drafts

obj MoveDraft {
    has label: str = "";
    has claim: str = "";
    has desk: str = "finance";
    has burn_delta_pct: float = 0.0;
    has mrr_delta_pct: float = 0.0;
    has cash_spend_usd: float = 0.0;
    has headcount_delta: int = 0;
    has milestone_shift_days: int = 0;
}

obj AttackDraft {
    has claim: str = "";
    has severity: str = "high";
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

obj PlanStep {
    has when: str = "";
    has title: str = "";
    has detail: str = "";
}

obj DecisionAnswer {
    has headline: str = "";
    has because: str = "";
    has dont: str = "";
    has analysis: str = "";
    has watch_for: str = "";
    has title: str = "";
    has steps: list[PlanStep] = [];
}

# ------------------------------------------------------------------- the agents

sem blue_propose_llm = """
BLUE argues FOR a way of running the founder's OWN plan. Propose ONE variation of THAT plan —
full scope, partial, cheaper substitute, staged, or don't do it. 'Hire 10 engineers' means
options around THAT hire, never 'start a raise'. Must differ materially from already_tried
(different scope or mechanism, not a reworded twin).
label: imperative, <=6 words, names the action. claim: one sentence, why it survives the
cash-out race. desk: finance|management|launch|publicity.
burn_delta_pct -40..80 (monthly burn). mrr_delta_pct -50..60. cash_spend_usd: one-time cash,
0 if none, derived from the founder's own figures, never above cash. headcount_delta -3..5,
non-zero ONLY for hiring/firing. milestone_shift_days -45..90, negative = sooner.
Effects must match the move: holding spend cannot raise burn; a hire raises burn and headcount.
""";
def blue_propose_llm(plan: str, company: str, desk: str, already_tried: str, round_no: int) -> MoveDraft by llm(temperature=0.55);

sem red_attack_llm = """
RED attacks the exact move Blue just made. Name the concrete failure mode for THIS move —
ramp/backfill for hires, CAC and payback for ads, utilization for equipment, blockers for
launches, churn for pricing. Never a generic 'raise money' or 'market is competitive' rant.
claim: one sentence, the failure and how it shows in the numbers. severity: low|medium|high.
burn_delta_pct 0..30, mrr_delta_pct -40..0, milestone_shift_days 0..45.
Proportionate magnitude: a plausible bad quarter, not the apocalypse.
""";
def red_attack_llm(plan: str, company: str, move_label: str, move_claim: str, desk: str) -> AttackDraft by llm(temperature=0.7);

sem classify_plan_llm = """
Classify a founder's stated plan into consult desks from exactly {finance, management, launch, publicity}.
  finance    = raise, burn, cash, pricing, MRR, runway, any purchase or capex
  management = hiring, headcount, contractors, org, infrastructure
  launch     = shipping, releasing, go-live, a product milestone
  publicity  = ads, campaigns, influencers, marketing, GTM
Pick 1-3, most relevant first. Anything that costs real money should include finance.
restated = one sentence recasting the plan as an A-vs-B decision.
""";
def classify_plan_llm(plan: str) -> PlanClass by llm(temperature=0.1);

sem intake_followups_llm = """
You are intake for a startup survival simulator. The sim already knows cash, burn, MRR,
headcount, and the milestone date — NEVER ask for those again, and never ask a generic
'how much runway do you have' question.

Given PLAN and KNOWN, write up to 3 short questions that pin down the numbers THIS SPECIFIC
plan turns on — the ones that decide whether it works:
  a hire      -> fully loaded monthly cost, months to productive, what slips if you hold
  paid ads    -> spend, target CAC, weeks to payback
  equipment   -> purchase price, expected utilization, what capacity it unlocks
  a launch    -> one-time GTM cash, the blocker most likely to slip the date
  pricing     -> percent change, customers touched, churn you would roll back at
Each: id = snake_case key, prompt = one plain sentence, qtype = 'number' or 'text',
placeholder = a short concrete example.
""";
def intake_followups_llm(plan: str, known: str) -> IntakeQSet by llm(temperature=0.3);

sem decide_llm = """
ARBITER writes the founder's answer. FACTS is verified deterministic arithmetic — surviving
branches, killed ones with kill reasons, cash-out dates, milestone dates, margins.
RULES: use ONLY figures present in FACTS. Do NOT do arithmetic of your own — every margin is
already given, quote it. No confidence percentages. Speak to the founder's actual decision in
their own vocabulary.
title: <=8 words, the verdict. headline: starts YES / NO / PARTIAL / NOT YET followed by an
em dash and a complete instruction naming what to do instead — e.g. "NO — hire one rep now,
not three." Never restate the rejected plan as if recommending it.
because: 1-2 sentences citing cash-out vs milestone date and the given margin.
dont: the alternative that died and the number that killed it, '' if none died.
analysis: 3-5 sentences — what Blue tried, what Red broke, why this line survived and the
others did not; cite branch ids exactly as in FACTS. watch_for: 1-2 sentences, the earliest
observable signal this is going wrong. steps: 3-6 actions, 'when' = a real date from FACTS or
This week/Day 30/Weekly, 'title' imperative and plan-specific, 'detail' says what to do and
which number to watch; one step must name the kill condition.
""";
def decide_llm(decision: str, company: str, facts: str) -> DecisionAnswer by llm_lead(temperature=0.35);

sem baseline_plan_llm = """
You are a confident generic startup chatbot with no red team, no arithmetic, and no access to
the company's cash position. Answer the founder's plan in 2-3 breezy, self-assured sentences.
Give a clear recommendation. Do NOT mention runway, cash-out dates, or any risk analysis —
this is the foil that shows what advice without arithmetic sounds like.
""";
def baseline_plan_llm(plan: str) -> str by llm(temperature=0.8);

# ------------------------------------------------------------------ call plumbing

def _describe_company(company: dict) -> str {
    if not company { return "no company figures supplied"; }
    bits: list = [];
    if company.get("name") { bits.append(str(company["name"])); }
    if company.get("describe") { bits.append(str(company["describe"])[:180]); }
    bits.append(f"cash ${float(company.get('cash', 0.0)):,.0f}");
    bits.append(f"burn ${float(company.get('monthly_burn', 0.0)):,.0f}/mo");
    bits.append(f"MRR ${float(company.get('mrr', 0.0)):,.0f}/mo");
    bits.append(f"headcount {int(company.get('headcount', 0))}");
    if company.get("milestone") {
        bits.append(f"milestone {company['milestone']} on {company.get('milestone_date', '?')}");
    }
    if company.get("plan_cash") {
        bits.append(f"founder says this plan costs ~${float(company['plan_cash']):,.0f} one-time");
    }
    if company.get("plan_burn_delta") {
        bits.append(f"founder says it adds ~${float(company['plan_burn_delta']):,.0f}/mo");
    }
    return " · ".join(bits);
}

def _rate_limit_wait(err: str) -> float {
    # Groq answers 429 with "Please try again in 6.432s" — obey it instead of guessing.
    import re;
    low = str(err).lower();
    if ("rate limit" not in low) and ("ratelimit" not in low) and ("429" not in low) {
        return 0.0;
    }
    m = re.search(r"try again in ([0-9.]+)s", low);
    if m {
        return min(float(m.group(1)) + 1.0, 65.0);
    }
    m2 = re.search(r"try again in ([0-9.]+)m([0-9.]+)s", low);
    if m2 {
        return min(float(m2.group(1)) * 60.0 + float(m2.group(2)) + 1.0, 65.0);
    }
    return 20.0;
}

def _note_failure(label: str, attempt: int, err: str) {
    pause = _rate_limit_wait(err);
    kind = f"rate-limited, waiting {pause:.0f}s" if pause > 0.0 else "failed";
    print(f"[SplitHorizon] {label} attempt {attempt}/{LLM_ATTEMPTS} {kind}: {err[:160]}");
    if attempt < LLM_ATTEMPTS {
        time.sleep(pause if pause > 0.0 else LLM_BACKOFF * float(attempt));
    }
}

def _give_up(label: str, err: str) -> str {
    return f"{label} failed after {LLM_ATTEMPTS} attempts: {err[:300]}";
}

def normalize_draft_areas(raw: list) -> list {
    allowed = ["finance", "management", "launch", "publicity"];
    out: list = [];
    for m in raw {
        a = str(m).lower().strip();
        if a in ["hire", "hiring", "ops", "org"] { a = "management"; }
        elif a in ["runway", "money", "fundraising"] { a = "finance"; }
        elif a in ["marketing", "ads", "pr", "growth"] { a = "publicity"; }
        elif a in ["ship", "product", "release"] { a = "launch"; }
        if a in allowed and a not in out {
            out.append(a);
        }
    }
    return out;
}

def blue_propose(plan: str, company: dict, desk: str, already_tried: list, round_no: int) -> MoveDraft {
    tried = "; ".join([str(t) for t in already_tried]) if already_tried else "nothing yet — this is the first move";
    summary = _describe_company(company);
    label = f"Blue({desk} r{round_no})";
    attempt = 0;
    last = "";
    while attempt < LLM_ATTEMPTS {
        attempt += 1;
        try {
            return blue_propose_llm(plan, summary, desk, tried, round_no);
        } except Exception as e {
            last = str(e);
            _note_failure(label, attempt, last);
        }
    }
    raise RuntimeError(_give_up(label, last));
}

def red_attack(plan: str, company: dict, move_label: str, move_claim: str, desk: str) -> AttackDraft {
    summary = _describe_company(company);
    label = f"Red({desk})";
    attempt = 0;
    last = "";
    while attempt < LLM_ATTEMPTS {
        attempt += 1;
        try {
            return red_attack_llm(plan, summary, move_label, move_claim, desk);
        } except Exception as e {
            last = str(e);
            _note_failure(label, attempt, last);
        }
    }
    raise RuntimeError(_give_up(label, last));
}

def classify_plan(plan: str) -> PlanClass {
    attempt = 0;
    last = "";
    while attempt < LLM_ATTEMPTS {
        attempt += 1;
        try {
            cls = classify_plan_llm(plan);
            mods = normalize_draft_areas(cls.modules);
            if not mods { mods = ["finance"]; }
            return PlanClass(modules=mods, restated=cls.restated);
        } except Exception as e {
            last = str(e);
            _note_failure("classify_plan", attempt, last);
        }
    }
    raise RuntimeError(_give_up("classify_plan", last));
}

def intake_followups(plan: str, known: str) -> IntakeQSet {
    attempt = 0;
    last = "";
    while attempt < LLM_ATTEMPTS {
        attempt += 1;
        try {
            return intake_followups_llm(plan, known);
        } except Exception as e {
            last = str(e);
            _note_failure("intake_followups", attempt, last);
        }
    }
    raise RuntimeError(_give_up("intake_followups", last));
}

def decide(decision: str, company: dict, facts: str) -> DecisionAnswer {
    summary = _describe_company(company);
    attempt = 0;
    last = "";
    while attempt < LLM_ATTEMPTS {
        attempt += 1;
        try {
            return decide_llm(decision, summary, facts);
        } except Exception as e {
            last = str(e);
            _note_failure("arbiter", attempt, last);
        }
    }
    raise RuntimeError(_give_up("arbiter", last));
}

def baseline_plan(plan: str) -> str {
    # The foil is decoration, not the product — never fail a run over it.
    try {
        return baseline_plan_llm(plan);
    } except Exception as e {
        print(f"[SplitHorizon] baseline foil skipped: {str(e)[:120]}");
        return "";
    }
}
