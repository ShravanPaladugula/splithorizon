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
    launch_kw = ["launch", "ship", "release", "go-live", "golive", "market", "expand", "product", "campaign", "customer"];
    runway_kw = ["runway", "raise", "burn", "cash", "fundrais", "dilution", "bridge", "spend", "cost", "price", "pricing", "buy", "invest"];
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
    # The canned interlock cache is ONLY for the demo plan. Real founder plans
    # run live so Blue/Red address the actual decision.
    t = _lower(plan);
    is_demo = False;
    for k in DEMO_PLAN_KW {
        if k in t { is_demo = True; }
    }
    live = os.environ.get("SPLITHORIZON_LIVE", "") == "1";
    if live and not is_demo {
        return "custom";
    }
    has_h = "hire" in modules;
    has_l = "launch" in modules;
    has_r = "runway" in modules;
    if has_h and has_l { return "interlock"; }
    if has_h { return "hire"; }
    if has_l { return "launch"; }
    if has_r { return "runway"; }
    return "interlock";
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
    needed: list = ["cash", "burn", "milestone", "milestone_date"];
    if "hire" in modules { needed.append("hire_shape"); }
    if "launch" in modules { needed.append("launch_shape"); }
    if "runway" in modules { needed.append("raise_shape"); }
    # Always useful once for company state
    if "mrr" not in needed { needed.append("mrr"); }
    if "headcount" not in needed { needed.append("headcount"); }

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

    ready = len(questions) == 0;
    proposal = build_proposal(plan, answers, modules) if ready else "";
    company = build_company_overrides(answers);

    return {
        "modules": modules,
        "restated": restated,
        "fixture_id": fixture_id,
        "questions": questions,
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
    lines.append("Spine: what happens to the cash-out date, and does the milestone land before it?");
    return "\n".join(lines);
}
