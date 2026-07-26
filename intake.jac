# Adaptive founder intake — pick a consult desk, then ask what's missing for survival sim.
# Spine unchanged: cash-out date vs milestone.
# Desks: finance · management · launch · publicity

include drafts;

import json;
import os;

glob CONSULT_AREAS: list = ["finance", "management", "launch", "publicity"];

glob AREA_META: dict = {
    "finance": {
        "label": "Finance",
        "blurb": "Raise, burn, pricing, MRR, runway",
        "agents": "Finance Blue / Finance Red"
    },
    "management": {
        "label": "Management",
        "blurb": "Hiring, headcount, contractors, infra",
        "agents": "Management Blue / Management Red"
    },
    "launch": {
        "label": "Launch",
        "blurb": "Ship dates, staged release, product go-live",
        "agents": "Launch Blue / Launch Red"
    },
    "publicity": {
        "label": "Publicity",
        "blurb": "Ads, campaigns, influencers, GTM buzz",
        "agents": "Publicity Blue / Publicity Red"
    }
};

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
    "management_shape": {
        "id": "management_shape",
        "prompt": "Management desk — what's the org move you're tempted to make?",
        "placeholder": "",
        "field": "management_shape",
        "type": "choice",
        "choices": [
            {"id": "two_eng", "label": "Hire two full-time engineers now"},
            {"id": "one_plus", "label": "One engineer + a contractor"},
            {"id": "infra", "label": "Invest in infra / tools, hold headcount"},
            {"id": "hold", "label": "Hold hiring / stay lean"}
        ]
    },
    "launch_shape": {
        "id": "launch_shape",
        "prompt": "Launch desk — how are you thinking about shipping?",
        "placeholder": "",
        "field": "launch_shape",
        "type": "choice",
        "choices": [
            {"id": "full", "label": "Full public launch on the milestone date"},
            {"id": "staged", "label": "Staged / soft launch first"},
            {"id": "delay", "label": "Delay the launch if needed"}
        ]
    },
    "finance_shape": {
        "id": "finance_shape",
        "prompt": "Finance desk — what's the money move?",
        "placeholder": "",
        "field": "finance_shape",
        "type": "choice",
        "choices": [
            {"id": "raise_soon", "label": "Start raising soon"},
            {"id": "extend", "label": "Extend runway / cut burn first"},
            {"id": "price_up", "label": "Raise prices / push MRR"},
            {"id": "none", "label": "Hold cash posture this cycle"}
        ]
    },
    "publicity_shape": {
        "id": "publicity_shape",
        "prompt": "Publicity desk — how are you going to market this?",
        "placeholder": "",
        "field": "publicity_shape",
        "type": "choice",
        "choices": [
            {"id": "paid", "label": "Paid ads / paid acquisition push"},
            {"id": "influencer", "label": "Influencer / creator partnerships"},
            {"id": "organic", "label": "Organic / content / community first"},
            {"id": "hold_mkt", "label": "Hold marketing spend"}
        ]
    }
};

def _lower(s: str) -> str {
    return str(s).lower();
}

def normalize_areas(raw: list) -> list {
    # Map legacy module ids + aliases onto the four consult desks.
    out: list = [];
    for m in raw {
        a = str(m).lower().strip();
        if a in ["hire", "hiring", "ops", "org"] { a = "management"; }
        elif a in ["runway", "money", "fundraising"] { a = "finance"; }
        elif a in ["marketing", "ads", "pr", "growth"] { a = "publicity"; }
        elif a in ["ship", "product", "release"] { a = "launch"; }
        if a in CONSULT_AREAS and a not in out {
            out.append(a);
        }
    }
    return out;
}

def classify_modules_keywords(plan: str) -> list {
    t = _lower(plan);
    mods: list = [];
    management_kw = ["hire", "hiring", "engineer", "eng ", "headcount", "contractor", "recruit", "team", "fire", "layoff", "infra", "infrastructure", "office", "relocat"];
    launch_kw = ["launch", "ship", "release", "go-live", "golive", "product", "mvp", "beta"];
    publicity_kw = ["ad ", "ads", "advertis", "influencer", "campaign", "marketing", "publicity", "pr ", "brand", "gtm", "content", "seo", "viral"];
    # Equipment buys are finance/capex — even if the UI desk was set to management.
    finance_kw = ["runway", "raise", "burn", "cash", "fundrais", "dilution", "bridge", "spend", "cost", "price", "pricing", "mrr", "revenue", "invest", "budget", "buy", "purchase", "printer", "equipment", "capex", "machine"];
    for k in management_kw {
        if k in t {
            if "management" not in mods { mods.append("management"); }
            break;
        }
    }
    for k in launch_kw {
        if k in t {
            if "launch" not in mods { mods.append("launch"); }
            break;
        }
    }
    for k in publicity_kw {
        if k in t {
            if "publicity" not in mods { mods.append("publicity"); }
            break;
        }
    }
    for k in finance_kw {
        if k in t {
            if "finance" not in mods { mods.append("finance"); }
            break;
        }
    }
    if not mods {
        mods = ["finance"];
    }
    return mods;
}

def classify_modules(plan: str) -> dict {
    restated = "";
    cls = classify_plan(plan);
    mods = normalize_areas(cls.modules);
    if mods {
        restated = cls.restated;
    } else {
        mods = classify_modules_keywords(plan);
    }
    return {"modules": mods, "restated": restated};
}

glob DEMO_PLAN_KW: list = ["two engineer", "2 engineer", "october launch"];

def pick_fixture(modules: list, plan: str) -> str {
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
        modules = normalize_areas(modules_hint);
        if not modules {
            cls = classify_modules(plan);
            modules = cls["modules"];
            restated = str(cls["restated"]);
        }
    } else {
        cls = classify_modules(plan);
        modules = cls["modules"];
        restated = str(cls["restated"]);
    }
    fixture_id = pick_fixture(modules, plan);
    needed: list = ["describe", "cash", "burn", "mrr", "growth", "headcount", "milestone", "milestone_date"];
    if "management" in modules { needed.append("management_shape"); }
    if "launch" in modules { needed.append("launch_shape"); }
    if "finance" in modules { needed.append("finance_shape"); }
    if "publicity" in modules { needed.append("publicity_shape"); }

    questions: list = [];
    for qid in needed {
        meta = QUESTION_BANK[qid];
        field = str(meta["field"]);
        if not _answered(answers, field) {
            questions.append(meta);
        }
        if len(questions) >= 1 {
            break;
        }
    }

    extra_questions: list = [];
    if not questions and not _answered(answers, "_extra_done") {
        known_parts: list = [];
        for k in answers.keys() {
            known_parts.append(f"{k}: {answers[k]}");
        }
        qset = intake_followups(plan, "; ".join(known_parts));
        for q in qset.questions[:3] {
            field = f"extra_{q.id}";
            if _answered(answers, field) {
                continue;
            }
            if q.prompt and str(q.id) {
                extra_questions.append({
                    "id": field,
                    "prompt": str(q.prompt),
                    "placeholder": str(q.placeholder),
                    "field": field,
                    "type": "number" if str(q.qtype) == "number" else "text"
                });
            }
        }
        if not extra_questions {
            extra_questions = [
                {
                    "id": "extra_plan_cash",
                    "prompt": "How much cash does this plan spend in the next 90 days (USD)?",
                    "placeholder": "e.g. 40000",
                    "field": "extra_plan_cash",
                    "type": "number"
                },
                {
                    "id": "extra_burn_delta",
                    "prompt": "What does it do to monthly burn after that (USD / month, negative = cut)?",
                    "placeholder": "e.g. 10000",
                    "field": "extra_burn_delta",
                    "type": "number"
                },
                {
                    "id": "extra_success_signal",
                    "prompt": "What early signal tells you the plan is working?",
                    "placeholder": "e.g. +15% MoM MRR in 60 days",
                    "field": "extra_success_signal",
                    "type": "text"
                }
            ];
        }
    }

    ready = len(questions) == 0 and (len(extra_questions) == 0) and _answered(answers, "_extra_done");
    proposal = build_proposal(plan, answers, modules) if ready else "";
    company = build_company_overrides(answers);
    desks: list = [];
    for a in modules {
        meta = AREA_META.get(a, {});
        desks.append({
            "id": a,
            "label": str(meta.get("label", a)),
            "blurb": str(meta.get("blurb", "")),
            "agents": str(meta.get("agents", ""))
        });
    }

    return {
        "modules": modules,
        "areas": modules,
        "desks": desks,
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
    if _answered(answers, "biz_name") { out["name"] = str(answers["biz_name"]); }
    if _answered(answers, "website") { out["website"] = str(answers["website"]); }
    if _answered(answers, "summary") { out["summary"] = str(answers["summary"]); }
    if _answered(answers, "describe") { out["describe"] = str(answers["describe"]); }
    if _answered(answers, "extra_plan_cash") { out["plan_cash"] = float(answers["extra_plan_cash"]); }
    elif _answered(answers, "plan_cash") { out["plan_cash"] = float(answers["plan_cash"]); }
    if _answered(answers, "extra_burn_delta") { out["plan_burn_delta"] = float(answers["extra_burn_delta"]); }
    elif _answered(answers, "burn_delta") { out["plan_burn_delta"] = float(answers["burn_delta"]); }
    return out;
}

def build_proposal(plan: str, answers: dict, modules: list) -> str {
    mgmt = str(answers.get("management_shape", answers.get("hire_shape", "")));
    launch = str(answers.get("launch_shape", ""));
    fin = str(answers.get("finance_shape", answers.get("raise_shape", "")));
    pub = str(answers.get("publicity_shape", ""));
    ms = str(answers.get("milestone", "milestone"));
    md = str(answers.get("milestone_date", ""));
    lines: list = [];
    lines.append(f"DECISION: {plan}");
    lines.append("");
    if _answered(answers, "biz_name") {
        lines.append(f"Company: {answers['biz_name']}.");
    }
    if _answered(answers, "describe") {
        lines.append(f"Business: {answers['describe']}.");
    }
    if _answered(answers, "website") {
        lines.append(f"Website: {answers['website']}.");
    }
    if _answered(answers, "summary") {
        lines.append(f"Site intel: {str(answers['summary'])[:280]}");
    }
    lines.append(f"Consult desks: {', '.join(modules)}.");
    if mgmt {
        label = mgmt;
        if mgmt == "two_eng" { label = "Hire two full-time engineers now"; }
        elif mgmt == "one_plus" { label = "One engineer + contractor"; }
        elif mgmt == "infra" { label = "Invest in infra / tools, hold headcount"; }
        elif mgmt == "hold" { label = "Hold hiring / stay lean"; }
        lines.append(f"Management move: {label}.");
    }
    if launch {
        label = launch;
        if launch == "full" { label = "Full public launch on the milestone date"; }
        elif launch == "staged" { label = "Staged / soft launch first"; }
        elif launch == "delay" { label = "Delay launch if needed"; }
        lines.append(f"Launch move: {label}.");
    }
    if fin {
        label = fin;
        if fin == "raise_soon" { label = "Start raising soon"; }
        elif fin == "extend" { label = "Extend runway / cut burn first"; }
        elif fin == "price_up" { label = "Raise prices / push MRR"; }
        elif fin == "none" { label = "Hold cash posture this cycle"; }
        lines.append(f"Finance move: {label}.");
    }
    if pub {
        label = pub;
        if pub == "paid" { label = "Paid ads / paid acquisition push"; }
        elif pub == "influencer" { label = "Influencer / creator partnerships"; }
        elif pub == "organic" { label = "Organic / content / community first"; }
        elif pub == "hold_mkt" { label = "Hold marketing spend"; }
        lines.append(f"Publicity move: {label}.");
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
        lines.append("Plan specifics: " + "; ".join(context_parts) + ".");
    }
    if _answered(answers, "prior_history") {
        lines.append("");
        lines.append("PRIOR DECISIONS (founder follow-through):");
        lines.append(str(answers["prior_history"]));
        lines.append("Weight these outcomes: if they DID go through and it helped or hurt, bias Blue/Red toward that evidence; if they DID NOT, treat the prior recommendation as rejected.");
    }
    return "\n".join(lines);
}
