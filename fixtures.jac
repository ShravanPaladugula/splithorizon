# Seed company + interlock demo (primary)

import copy;

glob SEED_COMPANY: dict = {
    "name": "Northline",
    "as_of": "2026-07-26",
    "cash": 120000.0,
    "monthly_burn": 42000.0,
    "mrr": 15000.0,
    "growth_rate": 0.04,
    "headcount": 4,
    "milestone": "October product launch",
    "milestone_date": "2026-10-03"
};

glob FIXTURES: dict = {
    "interlock": {
        "id": "interlock",
        "name": "Interlock — Hire two engineers to hit October launch?",
        "module": "interlock",
        "proposal": "DECISION: Should we hire two engineers to hit the October launch?\n\nCompany: Northline seed state.\nTempted move: Hire two FTEs now so October 3 still lands.\nCounter-move: One engineer + contractor.\nSpine: cash-out date vs milestone."
    },
    "launch": {
        "id": "launch",
        "name": "Launch — Ship October 3?",
        "module": "launch",
        "proposal": "DECISION: Should we ship on October 3rd?\n\nCompany: Northline. Tempted: full public launch. Alt: staged rollout."
    },
    "runway": {
        "id": "runway",
        "name": "Runway — When do we start raising?",
        "module": "runway",
        "proposal": "DECISION: How long do we have, when do we start raising?\n\nCompany: Northline. Tempted: raise now + cut burn."
    },
    "hire": {
        "id": "hire",
        "name": "Hiring — Two eng now vs one + contractor",
        "module": "hire",
        "proposal": "DECISION: Two engineers now, or one plus a contractor?\n\nCompany: Northline seed state."
    }
};

def seed_company_state() -> dict {
    return copy.deepcopy(SEED_COMPANY);
}

def list_fixtures() -> list {
    out: list = [];
    for k in ["interlock", "hire", "launch", "runway"] {
        if k in FIXTURES {
            v = FIXTURES[k];
            out.append({"id": v["id"], "name": v["name"], "proposal": v["proposal"], "module": v["module"]});
        }
    }
    return out;
}

def get_fixture(fixture_id: str) -> dict {
    if fixture_id in FIXTURES {
        return FIXTURES[fixture_id];
    }
    return FIXTURES["interlock"];
}
