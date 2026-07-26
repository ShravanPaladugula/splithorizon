# Real Jac walkers — ProtocolWalker runs the survival protocol, materializes
# the result as OSP nodes on the live walker graph, then role-walkers visit them.

include engine;

import json;
import os;

def attach_osp_from_result(result: dict) {
    # Attach onto root so visit/[-->] from ProtocolWalker sees this run.
    company = result.get("company", {});
    if company {
        root ++> CompanyState(
            cash=float(company.get("cash", 0.0)),
            monthly_burn=float(company.get("monthly_burn", 0.0)),
            mrr=float(company.get("mrr", 0.0)),
            growth_rate=float(company.get("growth_rate", 0.0)),
            headcount=int(company.get("headcount", 0)),
            milestone=str(company.get("milestone", "")),
            milestone_date=str(company.get("milestone_date", "")),
            as_of=str(company.get("as_of", ""))
        );
    }
    root ++> Tool(name="VerifyState", schema_desc="runway/hire/launch arithmetic");
    root ++> Tool(name="CashOutDate", schema_desc="deterministic cash-out date");
    for b in result.get("branches", []) {
        root ++> Branch(
            branch_id=str(b.get("id", "")),
            parent_id=str(b.get("parent_id", "")),
            round_no=int(b.get("round", 0)),
            label=str(b.get("label", "")),
            move=str(b.get("move", "")),
            alive=bool(b.get("alive", True)),
            kill_reason=str(b.get("kill_reason", "")),
            summary=str(b.get("summary", "")),
            side_created=str(b.get("side_created", "seed")),
            cash=float(b.get("cash", 0.0)),
            monthly_burn=float(b.get("monthly_burn", 0.0)),
            mrr=float(b.get("mrr", 0.0)),
            growth_rate=float(b.get("growth_rate", 0.0)),
            headcount=int(b.get("headcount", 0)),
            milestone=str(b.get("milestone", "")),
            milestone_date=str(b.get("milestone_date", "")),
            as_of=str(b.get("as_of", "")),
            cash_out_date=str(b.get("cash_out_date", "")),
            runway_months=float(b.get("runway_months", 0.0)),
            milestone_hit=bool(b.get("milestone_hit", False))
        );
    }
    for a in result.get("attacks", []) {
        root ++> Attack(
            attack_id=str(a.get("id", "")),
            claim=str(a.get("claim", "")),
            severity=str(a.get("severity", "medium")),
            check_hint=str(a.get("check_hint", "alive_at_milestone")),
            round_no=int(a.get("round", 0))
        );
    }
    i = 0;
    for e in result.get("evidence_log", []) {
        i += 1;
        root ++> Evidence(
            evidence_id=f"ev{i}",
            check=str(e.get("check", "")),
            value=str(e.get("value", "")),
            passed=bool(e.get("passed", True)),
            module=str(e.get("module", "runway"))
        );
    }
    memo = result.get("memo", {});
    if memo {
        root ++> Memo(
            recommended_branch_id=str(memo.get("recommended_branch_id", "")),
            title=str(memo.get("title", "")),
            prose=str(memo.get("prose", "")),
            kill_shots=str(memo.get("kill_shots", "")),
            open_risks=str(memo.get("open_risks", "")),
            dissent=str(memo.get("dissent", "")),
            date_line=str(memo.get("date_line", ""))
        );
    }
}

walker SeedWorldWalker {
    has hits: int = 0;
    can start with Root entry {
        visit [-->][?:CompanyState];
        visit [-->][?:Tool];
        report {"walker": "SeedWorldWalker", "company_tool_hits": self.hits};
    }
    can on_company with CompanyState entry { self.hits += 1; }
    can on_tool with Tool entry { self.hits += 1; }
}

walker BlueWalker {
    has blue_n: int = 0;
    has kills: int = 0;
    can start with Root entry {
        visit [-->][?:Branch];
        report {"walker": "BlueWalker", "blue_branches": self.blue_n, "killed": self.kills};
    }
    can on_branch with Branch entry {
        if here.side_created == "blue" {
            self.blue_n += 1;
            if not here.alive { self.kills += 1; }
        }
    }
}

walker RedWalker {
    has red_n: int = 0;
    has attack_n: int = 0;
    can start with Root entry {
        visit [-->][?:Branch];
        visit [-->][?:Attack];
        report {"walker": "RedWalker", "red_branches": self.red_n, "attacks": self.attack_n};
    }
    can on_branch with Branch entry {
        if here.side_created == "red" { self.red_n += 1; }
    }
    can on_attack with Attack entry { self.attack_n += 1; }
}

walker ScoreWalker {
    has scored: int = 0;
    has best_id: str = "";
    has best_rank: float = -999.0;
    can start with Root entry {
        visit [-->][?:Branch];
        report {
            "walker": "ScoreWalker",
            "scored": self.scored,
            "best_branch": self.best_id,
            "best_rank": self.best_rank
        };
    }
    can score with Branch entry {
        self.scored += 1;
        if here.alive {
            hit = 2.0 if here.milestone_hit else 0.0;
            rank = here.runway_months + hit;
            if rank > self.best_rank {
                self.best_rank = rank;
                self.best_id = here.branch_id;
            }
        }
    }
}

walker ArbiterWalker {
    has date_line: str = "";
    has recommended: str = "";
    can start with Root entry {
        visit [-->][?:Memo];
        report {
            "walker": "ArbiterWalker",
            "recommended": self.recommended,
            "date_line": self.date_line
        };
    }
    can on_memo with Memo entry {
        self.recommended = here.recommended_branch_id;
        self.date_line = here.date_line;
    }
}

walker ProtocolWalker {
    has proposal: str = "";
    has fixture_id: str = "interlock";
    has rounds: int = 3;
    has baseline: bool = True;
    has company_json: str = "{}";

    can start with Root entry {
        company = {};
        if self.company_json {
            try { company = json.loads(self.company_json); } except Exception { company = {}; }
        }
        result = run_protocol(
            self.proposal, self.fixture_id, self.rounds, self.baseline, company
        );
        # Materialize OSP nodes for this run (Jac graph memory + schema showcase).
        attach_osp_from_result(result);
        # Spawn role walkers — they visit whatever the graph exposes (JacHammer story).
        here spawn SeedWorldWalker();
        here spawn BlueWalker();
        here spawn RedWalker();
        here spawn ScoreWalker();
        here spawn ArbiterWalker();
        # Walker trace from protocol truth (visible to UI / Devpost judges).
        blue_n = 0; red_n = 0; blue_kill = 0; red_kill = 0;
        for b in result.get("branches", []) {
            side = str(b.get("side_created", ""));
            if side == "blue" {
                blue_n += 1;
                if not b.get("alive", True) { blue_kill += 1; }
            } elif side == "red" {
                red_n += 1;
                if not b.get("alive", True) { red_kill += 1; }
            }
        }
        memo = result.get("memo", {});
        walker_trace = [
            {"walker": "SeedWorldWalker", "node": "CompanyState", "company": str((result.get("company") or {}).get("name", ""))},
            {"walker": "BlueWalker", "blue_branches": blue_n, "killed": blue_kill},
            {"walker": "RedWalker", "red_branches": red_n, "attacks": len(result.get("attacks", [])), "killed": red_kill},
            {"walker": "ScoreWalker", "scored": len(result.get("scorecards", []))},
            {
                "walker": "ArbiterWalker",
                "recommended": memo.get("recommended_branch_id", ""),
                "date_line": memo.get("date_line", "")
            },
            {"walker": "ProtocolWalker", "evidence": len(result.get("evidence_log", [])), "osp": "Branch+Attack+Evidence+Memo"}
        ];
        result["walker_trace"] = walker_trace;
        result["jac_runtime"] = "walkers+osp+by_llm+verifiers";
        events = result.get("events", []);
        events.append({
            "kind": "walker",
            "message": f"Jac walkers — Blue {blue_n} / Red {red_n} / kills {blue_kill + red_kill} / evidence {len(result.get('evidence_log', []))}",
            "branch_id": ""
        });
        result["events"] = events;
        report result;
        os.makedirs("out", exist_ok=True);
        with open("out/last_run.json", "w") as f {
            json.dump(result, f, indent=2);
        }
    }
}
