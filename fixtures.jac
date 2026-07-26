# Business decision fixtures — one focused product: hiring

glob FIXTURES: dict = {
    "hire": {
        "id": "hire",
        "name": "Hiring — Grow the team vs stay lean",
        "proposal": """DECISION: Hire 3 full-time people this quarter to grow faster.

Business: Bootstrapped SaaS, 4 people, ~$42k MRR, 11 months cash runway.
Tempted move: Hire 3 immediately (2 engineers + 1 AE) to hit a feature + sales push.
Monthly hire cost (fully loaded): ~$32k. Hiring budget this quarter: $96k.
HARD CONSTRAINTS: (1) Do not drop cash runway below 6 months. (2) Quarterly spend on new hires ≤ $96k. (3) Must not freeze product delivery for > 6 weeks during onboarding.
GOAL: Raise MRR ≥ 30% within 2 quarters without a bridge round."""
    }
};

def list_fixtures() -> list[dict] {
    out: list[dict] = [];
    for k in FIXTURES.keys() {
        v = FIXTURES[k];
        out.append({"id": v["id"], "name": v["name"], "proposal": v["proposal"]});
    }
    return out;
}

def get_fixture(fixture_id: str) -> dict {
    if fixture_id in FIXTURES {
        return FIXTURES[fixture_id];
    }
    # Default to hire — product focus
    if "hire" in FIXTURES {
        return FIXTURES["hire"];
    }
    return {};
}
