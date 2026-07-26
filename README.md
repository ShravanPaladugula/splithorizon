# SplitHorizon

**A chatbot gives you advice. SplitHorizon gives you a date.**

Decision simulator for startups: company state + decision → graph of futures → Blue/Red attack-defend → kill branches that fail hard arithmetic → survivors ranked by **survival** (cash-out date vs milestone).

Canonical plan: [`MASTERPLAN.md`](MASTERPLAN.md).

## Spine

Every module answers: what does this do to the **cash-out date**, and does the **milestone land before it**?

| Module | Question |
|---|---|
| Launch readiness | Should we ship on October 3rd? |
| Runway & burn | How long do we have, when do we start raising? |
| Hiring plan | Two engineers now, or one plus a contractor? |

**Interlock demo (THE demo):** *Should we hire two engineers to hit the October launch?* Hiring raises burn; launch may land sooner — opposite pulls.

## Architecture

- Every agent = walker. Every future = subgraph.
- Verifier = plain deterministic code (`verifiers.jac`) — **the moat**.
- LLM proposes claims/effect tags; tools compute numbers. No score figure ever came from a model.
- No fake “Confidence: 87%”. Show survival months, milestone hit, attacks, cost delta — each with Evidence.

## Quick start (offline)

```bash
export JAC_HOME=/tmp/jac_home
export PATH="$HOME/.local/bin:$PATH"
cd splithorizon

# Golden interlock run (cached drafts — no API key)
SPLITHORIZON_LIVE=0 jac run run_once.jac

# UI
PORT=8765 python3 serve.py
open http://127.0.0.1:8765
```

Click **Run the interlock demo**. Expect: blast-hire branch **killed** with a visible cash-out date before Oct 3; lean hire survives; arbiter outputs a **date line**.

## Demo script (~4 min)

1. Load Northline seed CompanyState (cash / burn / MRR / milestone Oct 3).
2. Ask the interlock question.
3. Graph builds L→R: Seed → Blue → Red → Verifier → Branches → Arbiter.
4. Within ~30s a check **kills** hire-two with a number (cash-out before milestone).
5. Survivors ranked by runway + milestone hit.
6. Punchline: *Plan A runs out Sep 21. Plan B doesn't — cash-out Oct 10.*
7. Flash verifier registry (alive_at_milestone, hire_burn_delta, …).

## Jac layout

| File | Role |
|---|---|
| `schema.jac` | CompanyState, Branch, Attack, Evidence |
| `verifiers.jac` | Pure arithmetic — THE MOAT |
| `drafts.jac` | `by llm()` moves/attacks (claims only) + cache |
| `engine.jac` | Brancher, state propagation, Arbiter |
| `fixtures.jac` | Seed company + interlock / modules |
| `cache/interlock.json` | Golden offline run |
| `serve.py` | Thin Python UI bridge |
