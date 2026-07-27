# Deterministic verifiers — THE MOAT. No LLM numbers enter scores.

import json;
import copy;

obj EvidenceResult {
    has check: str;
    has value: str;
    has passed: bool;
    has module: str = "";
    has detail: str = "";
}

obj VerifyBundle {
    has ok: bool;
    has kill_reason: str = "";
    has cash_out_date: str = "";
    has runway_months: float = 0.0;
    has milestone_hit: bool = False;
    has evidence: list = [];
}

# hire_2 → cash-out ~Sep 21 (before Oct 3) — BRUTAL KILL
# hire_1+contractor → cash-out ~Oct 10 (after Oct 3) — survives
glob EFFECT_CATALOG: dict = {
    "noop": {"burn_delta": 0.0, "headcount_delta": 0, "mrr_delta": 0.0, "cost_delta": 0.0, "milestone_shift_days": 0, "label": "Hold"},
    "hire_2_eng": {"burn_delta": 36000.0, "headcount_delta": 2, "mrr_delta": 0.0, "cost_delta": 108000.0, "milestone_shift_days": 0, "label": "Hire two engineers"},
    "hire_1_eng_contractor": {"burn_delta": 21000.0, "headcount_delta": 1, "mrr_delta": 0.0, "cost_delta": 63000.0, "milestone_shift_days": -7, "label": "One eng + contractor"},
    "hire_0_hold": {"burn_delta": 0.0, "headcount_delta": 0, "mrr_delta": 0.0, "cost_delta": 0.0, "milestone_shift_days": 45, "label": "Hold hiring"},
    "launch_full_oct": {"burn_delta": 8000.0, "headcount_delta": 0, "mrr_delta": 4000.0, "cost_delta": 24000.0, "milestone_shift_days": 0, "label": "Full October launch"},
    "launch_staged": {"burn_delta": 3000.0, "headcount_delta": 0, "mrr_delta": 1500.0, "cost_delta": 9000.0, "milestone_shift_days": 14, "label": "Staged launch"},
    "raise_soon": {"burn_delta": 2000.0, "headcount_delta": 0, "mrr_delta": 0.0, "cost_delta": 6000.0, "milestone_shift_days": 0, "label": "Start raising"},
    "cut_burn": {"burn_delta": -6000.0, "headcount_delta": 0, "mrr_delta": 0.0, "cost_delta": -18000.0, "milestone_shift_days": 10, "label": "Cut discretionary burn"}
};

glob STRESS_CATALOG: dict = {
    "burn_spike": {"burn_delta": 8000.0, "mrr_delta": 0.0, "milestone_shift_days": 0, "label": "Burn spike"},
    "onboarding_freeze": {"burn_delta": 2000.0, "mrr_delta": 0.0, "milestone_shift_days": 21, "label": "Onboarding freeze"},
    "launch_slip": {"burn_delta": 0.0, "mrr_delta": -2000.0, "milestone_shift_days": 28, "label": "Launch slip"},
    "revenue_miss": {"burn_delta": 0.0, "mrr_delta": -5000.0, "milestone_shift_days": 0, "label": "Revenue miss"},
    "generic": {"burn_delta": 2000.0, "mrr_delta": 0.0, "milestone_shift_days": 7, "label": "Generic stress"}
};

glob DAYS_IN_MONTH: list = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

def _is_leap(y: int) -> bool {
    if y % 400 == 0 { return True; }
    if y % 100 == 0 { return False; }
    return y % 4 == 0;
}

def _dim(y: int, m: int) -> int {
    if m == 2 and _is_leap(y) { return 29; }
    return int(DAYS_IN_MONTH[m - 1]);
}

def parse_ymd(s: str) -> list {
    parts = str(s).split("-");
    if len(parts) < 3 { return [2026, 7, 26]; }
    return [int(parts[0]), int(parts[1]), int(parts[2])];
}

def format_ymd(y: int, m: int, d: int) -> str {
    return f"{y:04d}-{m:02d}-{d:02d}";
}

def add_days(ymd: str, days: int) -> str {
    p = parse_ymd(ymd);
    y = p[0]; m = p[1]; d = p[2];
    remaining = int(days);
    if remaining >= 0 {
        while remaining > 0 {
            dim = _dim(y, m);
            room = dim - d;
            if remaining <= room {
                d = d + remaining;
                remaining = 0;
            } else {
                remaining = remaining - room - 1;
                d = 1;
                m = m + 1;
                if m > 12 { m = 1; y = y + 1; }
            }
        }
    } else {
        remaining = -remaining;
        while remaining > 0 {
            if remaining < d {
                d = d - remaining;
                remaining = 0;
            } else {
                remaining = remaining - d;
                m = m - 1;
                if m < 1 { m = 12; y = y - 1; }
                d = _dim(y, m);
            }
        }
    }
    return format_ymd(y, m, d);
}

def days_between(a: str, b: str) -> int {
    def ord_of(s: str) -> int {
        p = parse_ymd(s);
        y = p[0]; m = p[1]; d = p[2];
        total = y * 365 + y // 4 - y // 100 + y // 400;
        i = 1;
        while i < m {
            total = total + _dim(y, i);
            i = i + 1;
        }
        return total + d;
    }
    return ord_of(b) - ord_of(a);
}

def pretty_date(ymd: str) -> str {
    if not ymd { return "—"; }
    p = parse_ymd(ymd);
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    mon = months[p[1] - 1] if p[1] >= 1 and p[1] <= 12 else "?";
    return f"{mon} {p[2]}, {p[0]}";
}

def raw_net_burn(state: dict) -> float {
    return float(state.get("monthly_burn", 0.0)) - float(state.get("mrr", 0.0));
}

def net_burn(state: dict) -> float {
    # True economics: MRR can cover burn (cash-flow positive).
    # Never clamp to $1 — that invents fake year-3026 cash-outs.
    net = raw_net_burn(state);
    if net < 0.0 { return 0.0; }
    return net;
}

def is_cashflow_positive(state: dict) -> bool {
    return raw_net_burn(state) <= 0.0;
}

def runway_months(state: dict) -> float {
    if is_cashflow_positive(state) {
        return 999.0;
    }
    nb = net_burn(state);
    if nb < 1.0 { nb = 1.0; }
    return float(state.get("cash", 0.0)) / nb;
}

def cash_out_date(state: dict) -> str {
    as_of = str(state.get("as_of", "2026-07-26"));
    if is_cashflow_positive(state) {
        # Not burning — cash-out is not the binding constraint. Park far past milestone.
        md = str(state.get("milestone_date", ""));
        if md {
            return add_days(md, 365 * 2);
        }
        return add_days(as_of, 365 * 3);
    }
    days = int(runway_months(state) * 30.437 + 0.5);
    return add_days(as_of, days);
}

glob MILESTONE_DRIFT_MIN: int = -30;
glob MILESTONE_DRIFT_MAX: int = 90;

def shift_milestone(state: dict, days: int) -> str {
    # The milestone is a fixed deadline the founder committed to, not a free variable.
    # Moves and stresses nudge it, but total drift is anchored to the ORIGINAL date so a
    # multi-round tree cannot walk the deadline months away from what was actually stated.
    md = str(state.get("milestone_date", ""));
    if not md { return md; }
    anchor = str(state.get("milestone_anchor", "")) or md;
    proposed = add_days(md, days);
    drift = days_between(anchor, proposed);
    if drift > MILESTONE_DRIFT_MAX { return add_days(anchor, MILESTONE_DRIFT_MAX); }
    if drift < MILESTONE_DRIFT_MIN { return add_days(anchor, MILESTONE_DRIFT_MIN); }
    return proposed;
}

def effect_label(tag: str) -> str {
    if tag in EFFECT_CATALOG { return str(EFFECT_CATALOG[tag].get("label", tag)); }
    return tag;
}

def apply_effect(state: dict, tag: str) -> dict {
    st = copy.deepcopy(state);
    spec = EFFECT_CATALOG[tag] if tag in EFFECT_CATALOG else EFFECT_CATALOG["noop"];
    st["monthly_burn"] = float(st.get("monthly_burn", 0.0)) + float(spec.get("burn_delta", 0.0));
    st["headcount"] = int(st.get("headcount", 0)) + int(spec.get("headcount_delta", 0));
    st["mrr"] = float(st.get("mrr", 0.0)) + float(spec.get("mrr_delta", 0.0));
    shift = int(spec.get("milestone_shift_days", 0));
    if shift != 0 { st["milestone_date"] = shift_milestone(st, shift); }
    if float(st.get("monthly_burn", 0.0)) < 1000.0 { st["monthly_burn"] = 1000.0; }
    return {"state": st, "cost_delta": float(spec.get("cost_delta", 0.0)), "tag": tag, "label": str(spec.get("label", tag))};
}

def _clamp(v: float, lo: float, hi: float) -> float {
    if v < lo { return lo; }
    if v > hi { return hi; }
    return v;
}

def apply_move_draft(state: dict, burn_pct: float, mrr_pct: float, hc_delta: int, shift_days: int, label: str, cash_spend: float = 0.0, burn_add: float = 0.0) -> dict {
    # LLM proposes bounded percentages; THIS function does the arithmetic.
    st = copy.deepcopy(state);
    bp = _clamp(float(burn_pct), -40.0, 80.0);
    mp = _clamp(float(mrr_pct), -50.0, 60.0);
    hc = int(_clamp(float(hc_delta), -3.0, 5.0));
    sh = int(_clamp(float(shift_days), -45.0, 90.0));
    burn_delta = float(st.get("monthly_burn", 0.0)) * bp / 100.0;
    st["monthly_burn"] = float(st.get("monthly_burn", 0.0)) + burn_delta + float(burn_add);
    st["mrr"] = max(0.0, float(st.get("mrr", 0.0)) * (1.0 + mp / 100.0));
    st["headcount"] = max(0, int(st.get("headcount", 0)) + hc);
    spend = max(0.0, float(cash_spend));
    if spend > 0.0 {
        st["cash"] = max(0.0, float(st.get("cash", 0.0)) - spend);
    }
    if sh != 0 { st["milestone_date"] = shift_milestone(st, sh); }
    if float(st.get("monthly_burn", 0.0)) < 1000.0 { st["monthly_burn"] = 1000.0; }
    return {"state": st, "cost_delta": burn_delta * 3.0 + spend, "tag": "custom", "label": label};
}

def apply_stress_draft(state: dict, burn_pct: float, mrr_pct: float, shift_days: int) -> dict {
    st = copy.deepcopy(state);
    bp = _clamp(float(burn_pct), 0.0, 30.0);
    mp = _clamp(float(mrr_pct), -40.0, 0.0);
    sh = int(_clamp(float(shift_days), 0.0, 45.0));
    st["monthly_burn"] = float(st.get("monthly_burn", 0.0)) * (1.0 + bp / 100.0);
    st["mrr"] = max(0.0, float(st.get("mrr", 0.0)) * (1.0 + mp / 100.0));
    if sh != 0 { st["milestone_date"] = shift_milestone(st, sh); }
    return st;
}

def apply_stress(state: dict, tag: str) -> dict {
    st = copy.deepcopy(state);
    spec = STRESS_CATALOG[tag] if tag in STRESS_CATALOG else STRESS_CATALOG["generic"];
    st["monthly_burn"] = float(st.get("monthly_burn", 0.0)) + float(spec.get("burn_delta", 0.0));
    st["mrr"] = max(0.0, float(st.get("mrr", 0.0)) + float(spec.get("mrr_delta", 0.0)));
    shift = int(spec.get("milestone_shift_days", 0));
    if shift != 0 { st["milestone_date"] = shift_milestone(st, shift); }
    return st;
}

def check_runway(state: dict) -> EvidenceResult {
    months = runway_months(state);
    ok = months >= 1.5 or is_cashflow_positive(state);
    if is_cashflow_positive(state) {
        return EvidenceResult(check="runway_floor", value="CF+", passed=True, module="runway",
            detail=f"Cash-flow positive (MRR ${float(state.get('mrr', 0.0)):.0f}/mo covers burn ${float(state.get('monthly_burn', 0.0)):.0f}/mo)");
    }
    return EvidenceResult(check="runway_floor", value=f"{months:.2f} mo", passed=ok, module="runway",
        detail=f"Runway {months:.2f} months (net burn ${net_burn(state):.0f}/mo)");
}

def check_alive_at_milestone(state: dict) -> EvidenceResult {
    cout = cash_out_date(state);
    md = str(state.get("milestone_date", ""));
    if not md {
        return EvidenceResult(check="alive_at_milestone", value=cout, passed=True, module="runway", detail="No milestone date");
    }
    # Pass when cash-out is on/after milestone
    ok = days_between(md, cout) >= 0;
    detail = f"ALIVE CHECK: cash-out {pretty_date(cout)} vs milestone {pretty_date(md)} — " + ("OK" if ok else f"KILL — cash ends before ship");
    return EvidenceResult(check="alive_at_milestone", value=cout, passed=ok, module="runway", detail=detail);
}

def check_hire_burn(state: dict, prior_burn: float) -> EvidenceResult {
    if prior_burn < 0.0 {
        return EvidenceResult(check="hire_burn_delta", value="n/a", passed=True, module="hire", detail="No prior burn");
    }
    cur = float(state.get("monthly_burn", 0.0));
    delta = cur - prior_burn;
    # BRUTAL: +$30k/mo or more fails hard with a visible number
    ok = delta < 30000.0;
    detail = f"Hire burn Δ +${delta:,.0f}/mo" + ("" if ok else " — BRUTAL FAIL (≥ $30k/mo step)");
    return EvidenceResult(check="hire_burn_delta", value=f"+${delta:,.0f}/mo", passed=ok, module="hire", detail=detail);
}

def check_milestone_before_cashout(state: dict) -> EvidenceResult {
    base = check_alive_at_milestone(state);
    return EvidenceResult(check="milestone_before_cashout", value=base.value, passed=base.passed, module="launch", detail=base.detail);
}

def verify_state(state: dict, prior_burn: float = -1.0, modules: list = []) -> VerifyBundle {
    mods = modules if modules else ["runway", "launch", "hire"];
    evidence: list = [];
    cout = cash_out_date(state);
    months = runway_months(state);
    ms_hit = False;

    if "runway" in mods {
        evidence.append(check_runway(state));
        ev = check_alive_at_milestone(state);
        evidence.append(ev);
        ms_hit = ev.passed;
    }
    if "hire" in mods {
        evidence.append(check_hire_burn(state, prior_burn));
    }
    if "launch" in mods {
        evidence.append(check_milestone_before_cashout(state));
        if "runway" not in mods {
            ms_hit = check_alive_at_milestone(state).passed;
        }
    }

    ok = True;
    kill_reason = "";
    for e in evidence {
        if not e.passed and e.check in ["alive_at_milestone", "milestone_before_cashout", "runway_floor", "hire_burn_delta"] {
            ok = False;
            if not kill_reason { kill_reason = e.detail; }
        }
    }
    return VerifyBundle(ok=ok, kill_reason=kill_reason, cash_out_date=cout, runway_months=months, milestone_hit=ms_hit, evidence=evidence);
}

def list_verifier_registry() -> list {
    return [
        {"name": "runway_floor", "module": "runway", "blurb": "Cash / net burn ≥ 1.5 months"},
        {"name": "alive_at_milestone", "module": "runway", "blurb": "Cash-out on/after milestone (BRUTAL)"},
        {"name": "hire_burn_delta", "module": "hire", "blurb": "Hire burn step < $30k/mo (BRUTAL)"},
        {"name": "milestone_before_cashout", "module": "launch", "blurb": "Milestone lands before cash-out"},
        {"name": "cash_out_date", "module": "runway", "blurb": "Deterministic cash-out from burn"},
        {"name": "apply_effect", "module": "all", "blurb": "Effect catalog: LLM picks tag, code applies numbers"}
    ];
}

def evidence_to_dicts(evidence: list) -> list {
    out: list = [];
    for e in evidence {
        out.append({"check": e.check, "value": e.value, "passed": e.passed, "module": e.module, "detail": e.detail});
    }
    return out;
}

def dispatch_tool(name: str, ctx: dict) -> dict {
    if name == "VerifyState" {
        bundle = verify_state(ctx.get("state", {}), float(ctx.get("prior_burn", -1.0)));
        return {
            "tool_name": name,
            "ok": bundle.ok,
            "detail": bundle.kill_reason or f"cash-out {pretty_date(bundle.cash_out_date)}",
            "metrics": {
                "cash_out_date": bundle.cash_out_date,
                "runway_months": bundle.runway_months,
                "milestone_hit": bundle.milestone_hit,
                "evidence": evidence_to_dicts(bundle.evidence)
            }
        };
    }
    if name == "CashOutDate" {
        st = ctx.get("state", ctx);
        cout = cash_out_date(st) if "cash" in st else cash_out_date({
            "as_of": str(ctx.get("as_of", "2026-07-26")),
            "cash": float(ctx.get("cash", 0.0)),
            "monthly_burn": float(ctx.get("monthly_burn", 0.0)),
            "mrr": float(ctx.get("mrr", 0.0))
        });
        return {"tool_name": name, "ok": True, "detail": f"CashOutDate → {pretty_date(cout)}", "metrics": {"cash_out_date": cout}};
    }
    return {"tool_name": name, "ok": False, "detail": f"Unknown tool {name}", "metrics": {}};
}
