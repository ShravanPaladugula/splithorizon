include intake;
import json;
import os;

with entry {
    plan = "Open a second office in Austin and move half the team there";
    answers = {};
    modules = [];
    result = next_intake_questions(plan, answers, modules);
    os.makedirs("out", exist_ok=True);
    with open("out/last_intake.json", "w") as f {
        json.dump(result, f, indent=2);
    }
    print("OK");
}
