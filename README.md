# SplitHorizon

**Adversarial counterfactual decision engine** built for JacHacks SF (Jul 26, 2026).

Before you commit to a plan, SplitHorizon **forks the world into counterfactual branches**. Blue walkers defend a proposal; Red walkers attack it with tool-grounded stressors; an Arbiter scores which futures survive.

> Memory is the branched graph. Agents are walkers. Tools are places.

## Why Jac

| Product idea | Jac construct |
|---|---|
| World / situation | `WorldEntity`, `Constraint`, `Goal` nodes |
| Plan A vs Plan B | `Branch` nodes + `forked_from` edges |
| Blue / Red teams | Opposing walkers / turn protocol (`BlueWalker` / `RedWalker`) |
| Calculator / checklist / inject | Walkers **visit** `Tool` nodes (`BudgetCalc`, `ConstraintCheck`, `ScenarioInject`) |
| Attack / plan language | `by llm()` typed drafts (`extract_world`, `blue_propose`, `red_attack`, `arbiter_narrate`) |
| Final write-up | `Memo` + Arbiter |

This is not a chatbot wrapper: the executable state is a **versioned graph**, and tool use happens **mid-traversal**.

## Demo (4 minutes)

1. **Problem (20s):** One-shot AI plans fail; nobody red-teams them.
2. **Baseline (30s):** Load **logistics** fixture → show brittle one-shot baseline (Highway 9, high confidence).
3. **SplitHorizon (90s):** Run engine. Narrate Blue speed-run → **Red kill shot** (fog choke / must_not via `ScenarioInject` + `ConstraintCheck`) → Blue Ridge Road patch → survivor. Point at Jac walker/tool visit logs.
4. **Memo (40s):** Recommended branch, kill shots, open risks, dissent trail.
5. **Generality (30s):** Flip to **fintech** or **shelter** fixture for 10s.
6. **Close (20s):** Planning, memory, tools, multi-agent, Jac-native.

## Quick start

### 1. Install Jac

```bash
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"
jac --version
```

If first-run runtime extraction fails under a restricted home directory, use:

```bash
export JAC_HOME=/tmp/jac_home
HOME=$JAC_HOME jac --version
```

### 2. Run the offline demo (cached fixtures — no API key)

```bash
cd splithorizon
chmod +x scripts/run_demo.sh
JAC_HOME=/tmp/jac_home HOME=/tmp/jac_home ./scripts/run_demo.sh run logistics
```

Expected: Red **[KILL]** on the naive Highway 9 branch, Blue patches via Ridge Road, Arbiter emits a memo. Tool visits include `BudgetCalc`, `ConstraintCheck`, `ScenarioInject`.

All three fixtures:

```bash
JAC_HOME=/tmp/jac_home HOME=/tmp/jac_home ./scripts/run_demo.sh all
```

Hello path (walker visits a Tool node):

```bash
JAC_HOME=/tmp/jac_home HOME=/tmp/jac_home ./scripts/run_demo.sh hello
```

### 3. Interactive UI (Mac)

```bash
JAC_HOME=/tmp/jac_home python3 serve.py
open http://127.0.0.1:8765
```

- Paste / pick a scenario → **Run · Fork the world**
- D3 tree **animates branches as Blue/Red events fire** (play / scrub / click nodes)
- Inspector shows scores, kill reasons, findings, tool visits per branch
- **Jac schema** panel: nodes, edges, walkers from `schema.jac`
- Arbiter memo + baseline foil + event stream

### 4. Live LLM path (optional)

```bash
export OPENAI_API_KEY=...   # or ANTHROPIC_API_KEY / GOOGLE_API_KEY
export SPLITHORIZON_LIVE=1
jac install byllm
# then run without relying on cache — free-text proposals work
```

Default is **offline/cache** (`cache/*.json`) so the stage demo survives flaky keys.

## Repository layout

```
schema.jac      # Nodes/edges: Branch, Action, Stressor, Tool, Memo, …
drafts.jac      # by llm() surface + fixture cache fallbacks
tools.jac       # BudgetCalc, ConstraintCheck, ScenarioInject
engine.jac      # Turn scheduler: seed → Blue → Red → Score → Arbiter
agents.jac      # Explicit OSP walkers for the Jac story
fixtures.jac    # Three demo proposals
main.jac        # CLI entry + API walkers
cache/          # Cached Seed/Blue/Red/Memo/Baseline for offline demo
ui/             # Minimal HTML/JS frontend (≥40% of product logic is Jac)
serve.py        # Thin static+API bridge that shells to `jac run`
```

**MVP freeze:** N=3 rounds, max_branches=12, 3 tools, 3 fixtures. Out of scope: maps, sensors, auth, mobile, 26 tools.

## Fixtures

1. **logistics** — convoy reroute under fog + choke-point (defense angle)
2. **fintech** — clear vs hold suspicious wire under SLA + fraud gate
3. **shelter** — bed allocation under capacity + equity floor

## Devpost / submit checklist

### Partial submit (~5:50)

- [ ] Project name: **SplitHorizon**
- [ ] Tagline: *Fork the world. Let Red break the plan. Keep what survives.*
- [ ] Tracks: **Agentic AI** (primary), AI for Defense, Best JacHammer / Best Use of Jaclang
- [ ] Repo link + this README
- [ ] Built with Jac / star [jaseci-labs/jac](https://github.com/jaseci-labs/jac) + [jaseci](https://github.com/jaseci-labs/jaseci) if logged in
- [ ] Screenshot of branch graph + memo

### Final submit (~7:15)

- [ ] 90s demo video (manual day-of — screen record the UI run on logistics)
- [ ] Confirm offline path works on presentation laptop (`./scripts/run_demo.sh run logistics`)
- [ ] No new features after freeze — only bugfixes

### Video notes (manual)

Record: baseline text → Run → zoom kill on Red branch → Blue patch → memo. Narrate Jac: walkers, `by llm()`, tool nodes.

## What is mocked / cached

| Piece | Behavior |
|---|---|
| LLM drafts | Served from `cache/<fixture>.json` unless `SPLITHORIZON_LIVE=1` |
| Tools | Always deterministic (real arithmetic / rule checks / scenario templates) |
| Baseline foil | Cached one-shot overconfident plan for pitch contrast |
| UI server | Thin Python bridge; engine remains Jac |

## Risks for live demo

- Jac first-run extraction needs a writable `JAC_HOME` (use `/tmp/jac_home` if home is locked down)
- Live LLM without cache needs API keys + `jac install byllm`
- Prefer **cached logistics** path on stage — it shows a visible Red kill + Blue patch every time

## License

MIT — hackathon demo code.
