# Deterministic tool nodes — facts, not LLM guesses

import json;

obj ToolResult {
    has tool_name: str;
    has ok: bool;
    has detail: str;
    has metrics_json: str = "{}";
}

# Scenario templates keyed by tag
glob SCENARIO_TEMPLATES: dict = {
    "logistics_delay": {
        "description": "Fog + choke-point delay: convoy loses 6h and fuel margin",
        "severity": 0.75,
        "likelihood": 0.65,
        "cost_delta": 12000.0,
        "capacity_hit": 0.3
    },
    "fraud_spike": {
        "description": "Coordinated fraud spike: synthetic identities inflate wire risk 3x",
        "severity": 0.85,
        "likelihood": 0.55,
        "cost_delta": 0.0,
        "capacity_hit": 0.0,
        "risk_delta": 0.35
    },
    "capacity_surge": {
        "description": "Shelter demand surge: arrivals exceed beds by 40%",
        "severity": 0.8,
        "likelihood": 0.7,
        "cost_delta": 8000.0,
        "capacity_hit": 0.4
    },
    "generic": {
        "description": "Generic disruption stressor",
        "severity": 0.6,
        "likelihood": 0.5,
        "cost_delta": 5000.0,
        "capacity_hit": 0.2
    }
};

def budget_calc(spent: float, action_cost: float, budget_limit: float) -> ToolResult {
    projected = spent + action_cost;
    remaining = budget_limit - projected;
    ok = projected <= budget_limit + 1e-6;
    metrics = {
        "spent": spent,
        "action_cost": action_cost,
        "projected": projected,
        "budget_limit": budget_limit,
        "remaining": remaining
    };
    detail = (
        f"BudgetCalc: spent={spent:.0f} + cost={action_cost:.0f} = {projected:.0f} "
        + f"vs limit={budget_limit:.0f} → {'OK' if ok else 'OVER BUDGET'}"
    );
    return ToolResult(tool_name="BudgetCalc", ok=ok, detail=detail, metrics_json=json.dumps(metrics));
}

def constraint_check(
    hard_rules_json: str,
    spent: float,
    budget_limit: float,
    capacity_used: float,
    capacity_limit: float,
    sla_hours_left: float,
    equity_score: float,
    flags_json: str = "{}"
) -> ToolResult {
    rules = json.loads(hard_rules_json) if hard_rules_json else [];
    flags = json.loads(flags_json) if flags_json else {};
    violations: list[str] = [];
    for rule in rules {
        r = str(rule.get("rule", ""));
        lim = float(rule.get("limit_value", 0.0));
        if r == "budget" and spent > lim {
            violations.append(f"budget {spent:.0f} > {lim:.0f}");
        } elif r == "capacity" and capacity_limit > 0 and capacity_used > capacity_limit {
            violations.append(f"capacity {capacity_used:.2f} > {capacity_limit:.2f}");
        } elif r == "sla" and sla_hours_left < lim {
            violations.append(f"SLA hours left {sla_hours_left:.1f} < min {lim:.1f}");
        } elif r == "equity" and equity_score < lim {
            violations.append(f"equity {equity_score:.2f} < min {lim:.2f}");
        } elif r == "must_not" {
            if flags.get("fog_choke_no_overwatch") {
                violations.append(str(rule.get("description", "must_not violated: fog choke without overwatch")));
            }
            if flags.get("fraud_clear_above_threshold") {
                violations.append(str(rule.get("description", "must_not violated: clear above fraud threshold")));
            }
        }
    }
    if budget_limit > 0 and spent > budget_limit {
        msg = f"budget {spent:.0f} > {budget_limit:.0f}";
        if msg not in violations {
            violations.append(msg);
        }
    }
    if capacity_limit > 0 and capacity_used > capacity_limit {
        msg = f"capacity {capacity_used:.2f} > {capacity_limit:.2f}";
        if msg not in violations {
            violations.append(msg);
        }
    }
    ok = len(violations) == 0;
    metrics = {
        "violations": violations,
        "spent": spent,
        "capacity_used": capacity_used,
        "equity_score": equity_score,
        "sla_hours_left": sla_hours_left,
        "flags": flags
    };
    detail = "ConstraintCheck: PASS" if ok else "ConstraintCheck: FAIL — " + "; ".join(violations);
    return ToolResult(tool_name="ConstraintCheck", ok=ok, detail=detail, metrics_json=json.dumps(metrics));
}

def scenario_inject(tag: str) -> ToolResult {
    key = tag if tag in SCENARIO_TEMPLATES else "generic";
    tmpl = SCENARIO_TEMPLATES[key];
    metrics = dict(tmpl);
    metrics["tag"] = key;
    detail = f"ScenarioInject[{key}]: {tmpl['description']}";
    return ToolResult(tool_name="ScenarioInject", ok=True, detail=detail, metrics_json=json.dumps(metrics));
}

def dispatch_tool(name: str, ctx: dict) -> ToolResult {
    if name == "BudgetCalc" {
        return budget_calc(
            float(ctx.get("spent", 0.0)),
            float(ctx.get("action_cost", 0.0)),
            float(ctx.get("budget_limit", 0.0))
        );
    } elif name == "ConstraintCheck" {
        return constraint_check(
            str(ctx.get("hard_rules_json", "[]")),
            float(ctx.get("spent", 0.0)),
            float(ctx.get("budget_limit", 0.0)),
            float(ctx.get("capacity_used", 0.0)),
            float(ctx.get("capacity_limit", 1.0)),
            float(ctx.get("sla_hours_left", 24.0)),
            float(ctx.get("equity_score", 1.0)),
            str(ctx.get("flags_json", "{}"))
        );
    } elif name == "ScenarioInject" {
        return scenario_inject(str(ctx.get("tag", "generic")));
    }
    return ToolResult(tool_name=name, ok=False, detail=f"Unknown tool {name}");
}
