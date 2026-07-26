# Explicit OSP walkers (Jac-native agent surfaces). The turn scheduler in engine.jac
# orchestrates the same opposing goals; these walkers make the agentic story visible.

include schema;
include tools;

import json;

walker SeedWorldWalker {
    has label: str = "seed";

    can start with Root entry {
        print(f"[SeedWorldWalker] grounding world as {self.label}");
        visit [-->][?:Branch];
        visit [-->][?:Tool];
    }

    can on_branch with Branch entry {
        report here.branch_id;
    }
}

walker BlueWalker {
    has goal: str = "Maximize goal coverage under constraints";

    can start with Root entry {
        print(f"[BlueWalker] {self.goal}");
        visit [-->][?:Tool];
    }

    can use_budget with Tool entry {
        if here.name == "BudgetCalc" {
            res = dispatch_tool("BudgetCalc", {"spent": 0.0, "action_cost": 1000.0, "budget_limit": 85000.0});
            report res.detail;
        }
        visit [-->];
    }
}

walker RedWalker {
    has goal: str = "Falsify Blue plans with tool-grounded stressors";

    can start with Root entry {
        print(f"[RedWalker] {self.goal}");
        visit [-->][?:Tool];
    }

    can inject with Tool entry {
        if here.name == "ScenarioInject" {
            res = dispatch_tool("ScenarioInject", {"tag": "logistics_delay"});
            report res.detail;
        }
        if here.name == "ConstraintCheck" {
            res = dispatch_tool("ConstraintCheck", {
                "hard_rules_json": "[]",
                "spent": 90000.0,
                "budget_limit": 85000.0,
                "capacity_used": 1.1,
                "capacity_limit": 1.0,
                "sla_hours_left": 24.0,
                "equity_score": 1.0,
                "flags_json": "{\"fog_choke_no_overwatch\": true}"
            });
            report res.detail;
        }
    }
}

walker ToolDispatchWalker {
    has tool_name: str = "BudgetCalc";
    has ctx_json: str = "{}";

    can start with Root entry {
        visit [-->][?:Tool];
    }

    can run with Tool entry {
        if here.name == self.tool_name {
            ctx = json.loads(self.ctx_json) if self.ctx_json else {};
            res = dispatch_tool(here.name, ctx);
            report res.detail;
        }
    }
}

walker ScoreWalker {
    can start with Root entry {
        visit [-->][?:Branch];
    }

    can score with Branch entry {
        rank = here.goal_coverage - 0.5 * here.residual_risk;
        report {"branch": here.branch_id, "rank": rank, "alive": here.alive};
    }
}

walker ArbiterWalker {
    can start with Root entry {
        print("[ArbiterWalker] selecting surviving branch");
        visit [-->][?:Branch];
    }

    can review with Branch entry {
        if here.alive {
            report here.branch_id;
        }
    }
}
