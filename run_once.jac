include engine;
include fixtures;
import json;
import os;

with entry {
    fid = "interlock";
    text = "DECISION: Hire two engineers to hit the October launch\n\nModules in play: hire, launch.\nTempted hiring move: Hire two full-time engineers now.\nTempted launch move: Full public launch on the milestone date.\nMilestone: Public launch by 2026-10-03.\nSpine: what happens to the cash-out date, and does the milestone land before it?";
    company = {"cash": 480000, "monthly_burn": 52000, "mrr": 18000, "headcount": 6, "milestone": "Public launch", "milestone_date": "2026-10-03", "name": "Northline"};
    if not text {
        fx = get_fixture(fid);
        if fx { text = str(fx["proposal"]); }
    }
    result = run_protocol(text, fid, 3, True, company);
    os.makedirs("out", exist_ok=True);
    with open("out/last_run.json", "w") as f {
        json.dump(result, f, indent=2);
    }
    print("OK");
}
