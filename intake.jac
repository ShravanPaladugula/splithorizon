# Adaptive founder intake — classify plan, ask what's missing for a survival sim.
# Stays on the masterplan spine: cash-out date vs milestone. Three modules only.

include drafts;

import json;
import os;

glob QUESTION_BANK: dict = {
    "cash": {
        "id": "cash",
        "prompt": "How much cash do you have in the bank right now (USD)?",
        "placeholder": "e.g. 120000",
        "field": "cash",
        "type": "number"
    },
    "burn": {
        "id": "burn",
        "prompt": "What's your monthly net burn (USD / month)?",
        "placeholder": "e.g. 42000",
        "field": "monthly_burn",
        "type": "number"
    },
    "mrr": {
        "id": "mrr",
        "prompt": "What's your current MRR (USD / month)?",
        "placeholder": "e.g. 15000",
        "field": "mrr",
        "type": "number"
    },
    "headcount": {
        "id": "headcount",
        "prompt": "How many people on the team today?",
        "placeholder": "e.g. 6",
        "field": "headcount",
        "type": "number"
    },
    "growth": {
        "id": "growth",
        "prompt": "How fast is MRR growing, % per month? (0 if flat)",
        "placeholder": "e.g. 8",
        "field": "growth",
        "type": "number"
    },
    "describe": {
        "id": "describe",
        "prompt": "In one sentence — what does the business do and who pays you?",
        "placeholder": "e.g. B2B SaaS for clinics, $99/mo per seat",
        "field": "describe",
        "type": "text"
    },
    "milestone": {
        "id": "milestone",
        "prompt": "What milestone are you racing toward?",
        "placeholder": "e.g. Public launch / Series A / Product v1",
        "field": "milestone",
        "type": "text"
    },
    "milestone_date": {
        "id": "milestone_date",
        "prompt": "What date does that milestone need to land?",
        "placeholder": "YYYY-MM-DD",
        "field": "milestone_date",
        "type": "date"
    },
    "hire_shape": {
        "id": "hire_shape",
        "prompt": "Hiring shape — what's the move you're tempted to make?",
        "placeholder": "",
        "field": "hire_shape",
        "type": "choice",
        "choices": [
            {"id": "two_eng", "label": "Hire two full-time engineers now"},
            {"id": "one_plus", "label": "One engineer + a contractor"},
            {"id": "hold", "label": "Hold hiring / stay lean"}
        ]
    },
    "launch_shape": {
        "id": "launch_shape",
        "prompt": "Launch shape — how are you thinking about shipping?",
        "placeholder": "",
        "field": "launch_shape",
        "type": "choice",
        "choices": [
            {"id": "full", "label": "Full public launch on the milestone date"},
            {"id": "staged", "label": "Staged / soft launch first"},
            {"id": "delay", "label": "Delay the launch if needed"}
        ]
    },
    "raise_shape": {
        "id": "raise_shape",
        "prompt": "Fundraising posture?",
        "placeholder": "",
        "field": "raise_shape",
        "type": "choice",
        "choices": [
            {"id": "raise_soon", "label": "Start raising soon"},
            {"id": "extend", "label": "Extend runway / cut burn first"},
            {"id": "none", "label": "Not raising this cycle"}
        ]
    }
};

def _lower(s: str) -> str {
    return str(s).lower();
}

def classify_modules_keywords(plan: str) -> list {
    t = _lower(plan);
    mods: list = [];
    hire_kw = ["hire", "hiring", "engineer", "eng ", "headcount", "contractor", "recruit", "team", "fire", "layoff"];
    launch_kw = ["launch", "ship", "release", "go-live", "golive", "market", "expand", "product", "campaign", "customer", "ad ", "ads", "advertis", "influencer", "signup", "sales", "outbound", "gtm", "growth"];
    runway_kw = ["runway", "raise", "burn", "cash", "fundrais", "dilution", "bridge", "spend", "cost", "price", "pricing", "buy", "invest", "office", "relocat"];
    for k in hire_kw {
        if k in t {
            if "hire" not in mods { mods.append("hire"); }
            break;
        }
    }
    for k in launch_kw {
        if k in t {
            if "launch" not in mods { mods.append("launch"); }
            break;
        }
    }
    for k in runway_kw {
        if k in t {
            if "runway" not in mods { mods.append("runway"); }
            break;
        }
    }
    if not mods {
        # Unknown decision — survival is always the spine; don't pretend it's hiring.
        mods = ["runway"];
    }
    return mods;
}

def classify_modules(plan: str) -> dict {
    # LLM classification when live (understands arbitrary plans); keywords otherwise.
    restated = "";
    cls = classify_plan(plan);
    mods: list = [];
    for m in cls.modules {
        if str(m) in ["hire", "launch", "runway"] and str(m) not in mods {
            mods.append(str(m));
        }
    }
    if mods {
        restated = cls.restated;
    } else {
        mods = classify_modules_keywords(plan);
    }
    return {"modules": mods, "restated": restated};
}

glob DEMO_PLAN_KW: list = ["two engineer", "2 engineer", "october launch"];

def pick_fixture(modules: list, plan: str) -> str {
    # ONLY the canned hire×launch demo uses fixture caches.
    # Every other founder plan is "custom" so Blue/Red follow THAT scenario.
    t = _lower(plan);
    for k in DEMO_PLAN_KW {
        if k in t { return "interlock"; }
    }
    return "custom";
}

def _answered(answers: dict, field: str) -> bool {
    if field not in answers { return False; }
    v = answers[field];
    if v == None { return False; }
    if str(v).strip() == "" { return False; }
    return True;
}

def next_intake_questions(plan: str, answers: dict, modules_hint: list = []) -> dict {
    restated = "";
    if modules_hint {
        # Already classified on the first call — don't re-run the LLM per answer.
        modules = modules_hint;
    } else {
        cls = classify_modules(plan);
        modules = cls["modules"];
        restated = str(cls["restated"]);
    }
    fixture_id = pick_fixture(modules, plan);
    needed: list = ["describe", "cash", "burn", "mrr", "growth", "headcount", "milestone", "milestone_date"];
    if "hire" in modules { needed.append("hire_shape"); }
    if "launch" in modules { needed.append("launch_shape"); }
    if "runway" in modules { needed.append("raise_shape"); }

    questions: list = [];
    for qid in needed {
        meta = QUESTION_BANK[qid];
        field = str(meta["field"]);
        if not _answered(answers, field) {
            questions.append(meta);
        }
        # Ask at most 1 new question per turn for a calm walkthrough
        if len(questions) >= 1 {
            break;
        }
    }

    # Statics done → one adaptive round: Gemini writes plan-specific follow-ups,
    # the frontend asks them one at a time, then marks _extra_done.
    extra_questions: list = [];
    if not questions and fixture_id == "custom" and not _answered(answers, "_extra_done") {
        known_parts: list = [];
        for k in answers.keys() {
            known_parts.append(f"{k}: {answers[k]}");
        }
        qset = intake_followups(plan, "; ".join(known_parts));
        for q in qset.questions[:3] {
            if q.prompt and str(q.id) {
                extra_questions.append({
                    "id": f"extra_{q.id}",
                    "prompt": str(q.prompt),
                    "placeholder": str(q.placeholder),
                    "field": f"extra_{q.id}",
                    "type": "number" if str(q.qtype) == "number" else "text"
                });
            }
        }
    }

    ready = len(questions) == 0 and len(extra_questions) == 0;
    proposal = build_proposal(plan, answers, modules) if ready else "";
    company = build_company_overrides(answers);

    return {
        "modules": modules,
        "restated": restated,
        "fixture_id": fixture_id,
        "questions": questions,
        "extra_questions": extra_questions,
        "ready": ready,
        "proposal": proposal,
        "company": company,
        "spine": "Every answer feeds one question: does the milestone land before cash-out?",
        "thesis": "Chatbot gives advice. SplitHorizon gives you a date."
    };
}

def build_company_overrides(answers: dict) -> dict {
    out: dict = {};
    if _answered(answers, "cash") { out["cash"] = float(answers["cash"]); }
    if _answered(answers, "monthly_burn") { out["monthly_burn"] = float(answers["monthly_burn"]); }
    if _answered(answers, "mrr") { out["mrr"] = float(answers["mrr"]); }
    if _answered(answers, "headcount") { out["headcount"] = int(float(answers["headcount"])); }
    if _answered(answers, "growth") { out["growth_rate"] = float(answers["growth"]) / 100.0; }
    if _answered(answers, "milestone") { out["milestone"] = str(answers["milestone"]); }
    if _answered(answers, "milestone_date") { out["milestone_date"] = str(answers["milestone_date"]); }
    return out;
}

def build_proposal(plan: str, answers: dict, modules: list) -> str {
    hire = str(answers.get("hire_shape", ""));
    launch = str(answers.get("launch_shape", ""));
    raise_s = str(answers.get("raise_shape", ""));
    ms = str(answers.get("milestone", "milestone"));
    md = str(answers.get("milestone_date", ""));
    lines: list = [];
    lines.append(f"DECISION: {plan}");
    lines.append("");
    if _answered(answers, "describe") {
        lines.append(f"Business: {answers['describe']}.");
    }
    lines.append(f"Modules in play: {', '.join(modules)}.");
    if hire {
        label = hire;
        if hire == "two_eng" { label = "Hire two full-time engineers now"; }
        elif hire == "one_plus" { label = "One engineer + contractor"; }
        elif hire == "hold" { label = "Hold hiring / stay lean"; }
        lines.append(f"Tempted hiring move: {label}.");
    }
    if launch {
        label = launch;
        if launch == "full" { label = "Full public launch on the milestone date"; }
        elif launch == "staged" { label = "Staged / soft launch first"; }
        elif launch == "delay" { label = "Delay launch if needed"; }
        lines.append(f"Tempted launch move: {label}.");
    }
    if raise_s {
        label = raise_s;
        if raise_s == "raise_soon" { label = "Start raising soon"; }
        elif raise_s == "extend" { label = "Extend runway / cut burn first"; }
        elif raise_s == "none" { label = "Not raising this cycle"; }
        lines.append(f"Fundraising posture: {label}.");
    }
    lines.append(f"Milestone: {ms} by {md}.");
    context_parts: list = [];
    for k in answers.keys() {
        ks = str(k);
        if ks.startswith("extra_") and str(answers[k]).strip() {
            context_parts.append(f"{ks[6:].replace('_', ' ')}: {answers[k]}");
        }
    }
    if context_parts {
        lines.append(f"Business context: {'; '.join(context_parts)}.");
    }
    lines.append("Spine: what happens to the cash-out date, and does the milestone land before it?");
    return "\n".join(lines);
}
