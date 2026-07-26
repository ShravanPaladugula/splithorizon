# SplitHorizon — Masterplan (canonical)

**What it is:** A decision simulator for startups. Company state + decision → graph of futures → Blue/Red attack-defend → kill branches that fail hard arithmetic → survivors ranked by whether the company is still alive.

**One-line pitch:** a chatbot gives you advice; SplitHorizon gives you a **date**.

**Spine:** Every module answers: what does this do to the **cash-out date**, and does the **milestone land before it**? Arbiter scoring = **survival**, always.

## Three modules

1. **Launch readiness** — "Should we ship on October 3rd?"
2. **Runway & burn** — "How long do we have, when do we start raising?" *(the spine)*
3. **Hiring plan** — "Two engineers now, or one plus a contractor?"

## Interlock demo (THE demo)

> Should we hire two engineers to hit the October launch?

Hiring raises burn (cash-out earlier). Launch may ship sooner (revenue earlier). Opposite pulls — answer is non-obvious.

## Architecture

- Every agent = walker. Every future = subgraph.
- Verifier = plain deterministic code, no model.
- LLM proposes; tools compute. **No number in the score ever came from a model.**
- Kill "Confidence: 87%". Show decomposition: survival months, milestone hit y/n, unmitigated attacks, cost delta — each with Evidence.

## Data model

```
node CompanyState { cash, monthly_burn, mrr, growth_rate, headcount, milestone, milestone_date }
node Branch { move, state: CompanyState, alive }
node Attack { claim, severity }
node Evidence { check, value, passed }
edges: derives_from, attacks, verified_by, leads_to
```

Blue / Red / Seed = `by llm()`. Verifier + Arbiter = plain code.

## Demo script

1. Load company state
2. Ask interlock question
3. Graph builds
4. A check **KILLS** a branch with a visible number in first ~30s
5. Two survivors
6. Arbiter → output is a **DATE**
7. Flash verifier registry

## Constraints

- Cap depth (2–3 rounds)
- At least one brutal check so a branch visibly dies with a number
- Prefer Jac for graph/walkers; Python ok for thin serve bridge
- Do not invent fake confidence %
