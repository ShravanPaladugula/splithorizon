include agents;
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
        result = here spawn ProtocolWalker(
            proposal=text,
            fixture_id=self.fixture_id,
            rounds=self.rounds,
            baseline=self.baseline,
            company_json="{}"
        );
        data = result.reports[0] if result.reports else {};
        report data;
    }
}

with entry {
    fid = os.environ.get("SPLITHORIZON_FIXTURE", "interlock");
    result = root spawn run_engine(fixture_id=fid, rounds=3, baseline=True);
    data = result.reports[0] if result.reports else {};
    memo = data.get("memo", {});
    print("DATE:", memo.get("date_line", ""));
    print("Recommended:", memo.get("recommended_branch_id", ""));
    print("Jac:", data.get("jac_runtime", ""));
    print("Walker reports:", len(data.get("walker_trace", [])));
}
