include intake;
import json;
import os;

with entry {
    plan = "should I raise now or cut burn";
    answers = {};
    result = next_intake_questions(plan, answers);
    os.makedirs("out", exist_ok=True);
    with open("out/last_intake.json", "w") as f {
        json.dump(result, f, indent=2);
    }
    print("OK");
}
