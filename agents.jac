include schema;
include verifiers;
walker SeedWorldWalker {
    can start with Root entry { visit [-->][?:CompanyState]; visit [-->][?:Branch]; }
}
walker BlueWalker {
    can start with Root entry { visit [-->][?:Tool]; }
}
walker RedWalker {
    can start with Root entry { visit [-->][?:Tool]; }
}
walker ScoreWalker {
    can start with Root entry { visit [-->][?:Branch]; }
    can score with Branch entry {
        hit = 2.0 if here.milestone_hit else 0.0;
        report {"branch": here.branch_id, "rank": here.runway_months + hit, "alive": here.alive};
    }
}
walker ArbiterWalker {
    can start with Root entry { visit [-->][?:Branch]; }
    can review with Branch entry {
        if here.alive { report here.branch_id; }
    }
}
