# SplitHorizon entry — CLI demo + HTTP walkers for the UI

include engine;
include fixtures;

import json;
import os;

walker run_engine {
    has fixture_id: str = "logistics";
    has proposal: str = "";
    has rounds: int = 3;
    has baseline: bool = True;

    can start with Root entry {
        fid = self.fixture_id;
        text = self.proposal;
        if not text {
            fx = get_fixture(fid);
            if fx {
                text = str(fx["proposal"]);
            }
        }
        result = run_protocol(text, fid, self.rounds, self.baseline);
        report result;
        # Also write latest result for UI polling
        os.makedirs("out", exist_ok=True);
        with open("out/last_run.json", "w") as f {
            json.dump(result, f, indent=2);
        }
        print(json.dumps({"ok": True, "recommended": result.get("memo", {}).get("recommended_branch_id", ""), "branches": len(result.get("branches", []))}));
    }
}

walker list_demo_fixtures {
    can start with Root entry {
        report list_fixtures();
    }
}

walker hello_tool_path {
    # Scaffold proof: walker visits a Tool node
    can start with Root entry {
        here ++> Tool(name="BudgetCalc", schema_desc="demo");
        visit [-->];
    }
    can on_tool with Tool entry {
        res = dispatch_tool("BudgetCalc", {"spent": 1000.0, "action_cost": 500.0, "budget_limit": 2000.0});
        print(res.detail);
        report res.detail;
    }
}

with entry {
    # Default: run logistics fixture offline (cached)
    fid = os.environ.get("SPLITHORIZON_FIXTURE", "logistics");
    if os.environ.get("SPLITHORIZON_MODE", "run") == "hello" {
        root spawn hello_tool_path();
    } else {
        result = root spawn run_engine(fixture_id=fid, rounds=3, baseline=True);
        data = result.reports[0] if result.reports else {};
        memo = data.get("memo", {});
        print("==== SplitHorizon Decision Memo ====");
        print(memo.get("title", ""));
        print("Recommended:", memo.get("recommended_branch_id", ""));
        print(memo.get("prose", ""));
        print("Kill shots:", memo.get("kill_shots", ""));
        print("Open risks:", memo.get("open_risks", ""));
        print("Dissent:", memo.get("dissent", ""));
        print("Baseline foil:", data.get("baseline", "")[:240]);
        print("Branches:", len(data.get("branches", [])), "Tools used:", len(data.get("tool_log", [])));
    }
}
