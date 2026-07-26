# 4-minute demo script (judged slot)

**Hard rule:** Use **Try the hire × launch demo** only. Do **not** run live Gemini in the judged slot.

## Pre-flight (5 min before)

- [ ] `SPLITHORIZON_LIVE=0` in `.env` (or unset)
- [ ] `JAC_HOME=... PORT=8765 python3 serve.py` running; `http://127.0.0.1:8765` loads
- [ ] Click demo CTA once offline as a smoke test — expect Sep 22 kill + Oct 10 date line
- [ ] Backup screen recording ready on phone/laptop
- [ ] Mute Slack/Discord notifications

## Script (~4:00)

| Time | Say / do |
|---|---|
| 0:00–0:20 | “A chatbot gives advice. SplitHorizon gives you a **date**.” |
| 0:20–0:35 | Click **Try the hire × launch demo**. Show Northline cash / burn / Oct 3 milestone. |
| 0:35–0:50 | “Should we hire two engineers to hit the October launch? Opposite pulls: burn vs ship.” |
| 0:50–1:50 | **Fork futures**. Let playback run. Point at schema rail: Seed → Blue → Red → Verifier. |
| 1:50–2:20 | Open kill callout / dead branch: cash-out **Sep 22** before milestone **Oct 3**. “Verifier killed it — not the LLM.” |
| 2:20–2:50 | Arbiter date line: Plan A dies Sep 22; Plan B cash-out **Oct 10**. |
| 2:50–3:30 | Flash verifier registry + Jac walkers (`ProtocolWalker`, Blue/Red). “LLM proposes tags; Jac tools compute.” |
| 3:30–4:00 | Chatbot foil: “Just hire two engineers” — confident and wrong. End on the date. |

## Punchline (memorize)

> Plan A (two engineers) runs out Sep 22. Plan B (one + contractor) does not — cash-out Oct 10.
