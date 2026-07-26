# SplitHorizon — CompanyState / Branch / Attack / Evidence

node CompanyState {
    has cash: float = 0.0;
    has monthly_burn: float = 0.0;
    has mrr: float = 0.0;
    has growth_rate: float = 0.0;
    has headcount: int = 0;
    has milestone: str = "";
    has milestone_date: str = "";
    has as_of: str = "";
}

node Branch {
    has branch_id: str;
    has label: str;
    has parent_id: str = "";
    has round_no: int = 0;
    has move: str = "";
    has alive: bool = True;
    has kill_reason: str = "";
    has summary: str = "";
    has side_created: str = "seed";
    has cash: float = 0.0;
    has monthly_burn: float = 0.0;
    has mrr: float = 0.0;
    has growth_rate: float = 0.0;
    has headcount: int = 0;
    has milestone: str = "";
    has milestone_date: str = "";
    has as_of: str = "";
    has cash_out_date: str = "";
    has runway_months: float = 0.0;
    has milestone_hit: bool = False;
}

node Attack {
    has attack_id: str;
    has claim: str;
    has severity: str = "medium";
    has check_hint: str = "runway";
    has round_no: int = 0;
}

node Evidence {
    has evidence_id: str;
    has check: str;
    has value: str;
    has passed: bool;
    has module: str = "runway";
}

node Tool {
    has name: str;
    has schema_desc: str = "";
}

node Memo {
    has recommended_branch_id: str;
    has title: str;
    has prose: str;
    has kill_shots: str = "";
    has open_risks: str = "";
    has dissent: str = "";
    has date_line: str = "";
}

edge derives_from { has note: str = ""; }
edge attacks { has note: str = ""; }
edge verified_by { has result_json: str = "{}"; }
edge leads_to { has via: str = ""; }
edge has_tool { has note: str = ""; }
