# SplitHorizon — Devpost draft (paste into Devpost before 7:15 PM)

**Title:** SplitHorizon  
**Tagline:** A chatbot gives you advice. SplitHorizon gives you a date.  
**Tracks:** Agentic AI + Fintech/Open (+ Best JacHammer / Best Use of Jaclang if selectable)  
**Repo:** https://github.com/ShravanPaladugula/splithorizon  

## Inspiration

Founders don’t need another confident opinion. They need to know whether a plan keeps them **alive past the milestone**. Hiring two engineers to hit an October launch *sounds* right — until burn pulls the cash-out date before ship day. SplitHorizon exists for that non-obvious interlock.

## What it does

1. You state a plan of action (or run the hire × launch demo).
2. Adaptive Jac intake classifies **hire / launch / runway** and asks only the missing numbers.
3. **Blue** proposes moves; **Red** attacks; **deterministic verifiers** kill branches that fail hard arithmetic (cash-out vs milestone, hire burn step).
4. Arbiter ranks survivors by **survival** and outputs a **date line** — plus a plan of action.
5. Optional chatbot foil: same question, one-shot LLM, no Red team.

## How we built it

- **Jac** — `ProtocolWalker` orchestrates the run; Seed / Blue / Red / Score / Arbiter walkers; OSP nodes (`CompanyState`, `Branch`, `Attack`, `Evidence`, `Memo`, `Tool`); `by llm()` for drafts only.
- **Verifiers** — pure Jac arithmetic. No score figure ever came from a model.
- **Offline golden path** — cached Blue/Red drafts so the judged demo cannot flake on API quotas.
- **Thin Python bridge** (`serve.py`) for the war-room UI (D3 futures tree + playback).

## Challenges

- Keeping LLM proposals from inventing dollars — solved by effect tags / bounded % + verifier-owned math.
- Live Gemini free-tier rate limits — demo path stays offline; live mode retries and falls back.
- Making “walkers” real for JacHammer — protocol materializes OSP nodes and spawns role walkers after each run.

## Accomplishments

- Visible brutal kill: hire-two cash-out **Sep 22** before milestone **Oct 3**.
- Survivor date line: Plan B cash-out **Oct 10**.
- Adaptive intake + business profiles + decision analysis / plan of action for arbitrary founder plans.
- Dual-track story: agentic multi-walker protocol + founder fintech (runway / cash-out).

## What we learned

Jac’s value is **graph + walkers + typed LLM drafts** when tools stay deterministic. The pitch foil (chatbot vs date) is the product.

## What’s next

Persist decision history per company; more verifier modules; ship a rehearsed live custom-plan path once quota is stable.

## Built with

Jac, byllm / Gemini (live mode), Python, D3.js, HTML/CSS/JS

## Try it (offline demo)

```bash
export PATH="$HOME/.local/bin:$PATH"
export JAC_HOME=/tmp/jac_home
cd splithorizon
SPLITHORIZON_LIVE=0 PORT=8765 python3 serve.py
# open http://127.0.0.1:8765 → “Try the hire × launch demo” → Fork futures
```
