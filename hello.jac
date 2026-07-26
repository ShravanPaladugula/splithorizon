include schema;
include verifiers;
with entry { root ++> Tool(name="VerifyState", schema_desc="demo"); }
walker hello_tool_path {
    can start with Root entry { visit [-->]; }
    can on_tool with Tool entry {
        if here.name == "VerifyState" {
            res = dispatch_tool("VerifyState", {"state": {"cash": 120000.0, "monthly_burn": 78000.0, "mrr": 15000.0, "growth_rate": 0.04, "headcount": 6, "milestone": "October product launch", "milestone_date": "2026-10-03", "as_of": "2026-07-26"}, "prior_burn": 42000.0});
            print(res["detail"]);
            report res["detail"];
        }
    }
}
with entry { root spawn hello_tool_path(); }
