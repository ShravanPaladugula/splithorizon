include intake;
import json;
import os;

with entry {
    plan = "Run a $20k/month influencer marketing campaign to triple signups";
    answers = {"cash": 480000, "monthly_burn": 52000, "mrr": 18000, "headcount": 6, "milestone": "Public launch", "milestone_date": "2026-10-03", "describe": "B2B SaaS for dental clinics, $99/mo per seat", "growth": 6, "launch_shape": "full", "raise_shape": "raise_soon", "extra_current_influencer_cac": 45, "extra_influencer_conversion_rate": 0.03, "_extra_done": 1};
    modules = ["launch", "runway"];
    result = next_intake_questions(plan, answers, modules);
    os.makedirs("out", exist_ok=True);
    with open("out/last_intake.json", "w") as f {
        json.dump(result, f, indent=2);
    }
    print("OK");
}
