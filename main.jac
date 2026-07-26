include engine;
include fixtures;
import json;
import os;

walker run_engine {
    has fixture_id: str = "interlock";
    has proposal: str = "";
    has rounds: int = 3;
    has baseline: bool = True;
    can start with Root entry {
        text = self.proposal;
        if not text {
            fx = get_fixture(self.fixture_id);
            if fx { text = str(fx["proposal"]); }
        }
        result = run_protocol(text, self.fixture_id, self.rounds, self.baseline);
        report result;
        os.makedirs("out", exist_ok=True);
        with open("out/last_run.json", "w") as f { json.dump(result, f, indent=2); }
    }
}

with entry {
    fid = os.environ.get("SPLITHORIZON_FIXTURE", "interlock");
    result = root spawn run_engine(fixture_id=fid, rounds=3, baseline=True);
    data = result.reports[0] if result.reports else {};
    memo = data.get("memo", {});
    print("DATE:", memo.get("date_line", ""));
    print("Recommended:", memo.get("recommended_branch_id", ""));
}
