# Fixtures: proposal texts for the three demo domains

glob FIXTURES: dict = {
    "logistics": {
        "id": "logistics",
        "name": "Defense / Logistics — Convoy Reroute",
        "proposal": """PROPOSAL: Reroute Supply Convoy Alpha through Highway 9 under fog advisory.

Context: Forward operating base needs medical and fuel resupply within 18 hours.
Current plan: Take the shortest paved route (Highway 9) through the river choke-point.
Budget: $85,000 for escort, fuel, and contingency.
Assets: 4 trucks (capacity 12 tons), 1 escort unit, limited ISR coverage in fog.
Constraints (HARD): (1) Do not exceed $85k. (2) Do not transit choke-point without overwatch if fog visibility < 200m. (3) Delivery SLA 18h.
Goal: Deliver ≥90% of medical cargo intact before SLA."""
    },
    "fintech": {
        "id": "fintech",
        "name": "Fintech — Suspicious Wire Hold vs Clear",
        "proposal": """PROPOSAL: Clear a $240,000 outbound wire flagged as medium-risk to meet client SLA.

Context: Corporate client needs same-day settlement. Fraud model score 0.62 (medium).
Ops proposes: Clear now; investigate after posting to avoid SLA breach.
Budget/risk limit: Expected fraud loss tolerance $50,000 for this corridor.
Constraints (HARD): (1) SLA clearance within 2 hours from flag. (2) Must not clear if fused fraud risk > 0.80. (3) Manual hold allowed but burns SLA.
Goal: Minimize fraud loss while keeping SLA breach rate under policy."""
    },
    "shelter": {
        "id": "shelter",
        "name": "Social Impact — Shelter Bed Allocation",
        "proposal": """PROPOSAL: Allocate all 40 remaining shelter beds to the first-arrived queue tonight.

Context: Cold weather surge. 58 people in queue. Equity policy requires proportional access for families with children and disability-priority clients.
Budget for overflow hotel vouchers: $12,000.
Constraints (HARD): (1) Physical capacity 40 beds. (2) Equity score must remain ≥ 0.70. (3) Overflow spend ≤ $12k.
Goal: Shelter the highest-need clients without collapsing equity or capacity."""
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
    return {};
}
