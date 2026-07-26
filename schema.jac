# SplitHorizon graph schema — versioned world / branch OSP model

node WorldEntity {
    has entity_id: str;
    has kind: str;
    has name: str;
    has capacity: float = 0.0;
    has status: str = "ok";
    has attrs_json: str = "{}";
}

node Constraint {
    has constraint_id: str;
    has rule: str;
    has description: str;
    has hard: bool = True;
    has limit_value: float = 0.0;
    has unit: str = "";
}

node Goal {
    has goal_id: str;
    has description: str;
    has metric: str;
    has target_value: float = 1.0;
    has weight: float = 1.0;
}

node Action {
    has action_id: str;
    has who: str;
    has what: str;
    has when_label: str = "now";
    has cost: float = 0.0;
    has round_no: int = 0;
    has side: str = "blue";
}

node Stressor {
    has stressor_id: str;
    has description: str;
    has severity: float = 0.5;
    has likelihood: float = 0.5;
    has target_ref: str = "";
    has round_no: int = 0;
    has tag: str = "";
}

node Branch {
    has branch_id: str;
    has label: str;
    has parent_id: str = "";
    has round_no: int = 0;
    has alive: bool = True;
    has spent: float = 0.0;
    has residual_risk: float = 0.5;
    has goal_coverage: float = 0.0;
    has uncertainty: float = 0.5;
    has kill_reason: str = "";
    has summary: str = "";
    has side_created: str = "seed";
}

node Tool {
    has name: str;
    has schema_desc: str = "";
}

node Finding {
    has finding_id: str;
    has side: str;
    has claim: str;
    has evidence: str = "";
    has confidence: float = 0.5;
}

node Scorecard {
    has branch_id: str;
    has residual_risk: float;
    has goal_coverage: float;
    has cost: float;
    has uncertainty: float;
    has rank_score: float;
    has narrative: str = "";
}

node Memo {
    has recommended_branch_id: str;
    has title: str;
    has prose: str;
    has kill_shots: str = "";
    has open_risks: str = "";
    has dissent: str = "";
    has baseline_foil: str = "";
}

edge in_branch {
    has note: str = "";
}

edge forked_from {
    has via: str = "";
}

edge targets {
    has note: str = "";
}

edge mitigates {
    has note: str = "";
}

edge violates {
    has note: str = "";
}

edge uses_tool {
    has result_json: str = "";
}

edge supports {
    has note: str = "";
}

edge attacks {
    has note: str = "";
}

edge derived_from {
    has source: str = "llm";
}

edge has_tool {
    has note: str = "";
}
