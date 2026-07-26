include engine;
include fixtures;
import json;
import os;

with entry {
    fid = "custom";
    text = "DECISION: Run a $20k/month influencer marketing campaign to triple signups\n\nBusiness: B2B SaaS for dental clinics, $99/mo per seat.\nModules in play: launch, runway.\nTempted launch move: Full public launch on the milestone date.\nFundraising posture: Start raising soon.\nMilestone: Public launch by 2026-10-03.\nBusiness context: current influencer cac: 45; influencer conversion rate: 0.03.\nSpine: what happens to the cash-out date, and does the milestone land before it?";
    company = {"cash": 480000, "monthly_burn": 52000, "mrr": 18000, "headcount": 6, "growth_rate": 0.06, "milestone": "Public launch", "milestone_date": "2026-10-03", "name": "Northline"};
    if not text {
        fx = get_fixture(fid);
        if fx { text = str(fx["proposal"]); }
    }
    result = run_protocol(text, fid, 4, True, company);
    os.makedirs("out", exist_ok=True);
    with open("out/last_run.json", "w") as f {
        json.dump(result, f, indent=2);
    }
    print("OK");
}
