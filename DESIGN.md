# DESIGN.md — Reactive Circuit-Breaker: AI-Verdicted Drain Protection

**Event:** Reactive Omni Buildathon (DoraHacks, Reactive Network)
**Team:** rezimx-btc (solo) · **Track:** Reactive Meets AI (registered; $1,000 1st place)
**Window:** 5 Nov–5 Dec 2026 · **Submission deadline:** 6 Dec 2026, 03:00 WIB
  (page: event 2026-11-04T12:00Z to 2026-12-05T20:00Z)
**Prizes (track):** Reactive Meets AI — $1,000 for 1st place (paid in REACT)
**Status:** RESEARCH + DESIGN (21 Nov). Build starts now.

---

## 1. The problem

A vault that lets users withdraw on demand can be drained in seconds: a burst of
large withdrawals — a compromised key, a flash-loan-assisted exploit, a fat-fingered
script — empties it before any human notices. Blockchains react slowly because
nothing watches them continuously. And a dumb automatic pause is almost as bad: it
freezes legitimate users on every busy day.

## 2. The concept — Reactive Circuit-Breaker with an AI verdict

**One line:** *A reactive contract watches the vault every second; when withdrawals
burst past a threshold it pauses the vault automatically — and an AI agent judges
the burst attack vs legitimate, so the pause lifts fast when it was a false alarm.*

Two halves, each doing what it is good at:
- **Reactive contract (on-chain, ~1 s blocks):** subscribes to the vault's
  `Withdrawal` events on Base Sepolia (and/or Unichain Sepolia). If withdrawals in
  a rolling window exceed the threshold, its callback calls `pause()` on the vault.
  This is the mandatory reactive loop: origin event → reactive transaction →
  callback, all visible on-chain.
- **AI verdict agent (off-chain):** reads each flagged burst (amounts, timing,
  addresses, history), classifies it ATTACK-LIKE vs LEGITIMATE, and writes the
  verdict on-chain to a Verdict contract. A LEGITIMATE verdict unpauses the vault
  automatically; ATTACK-LIKE keeps it paused for manual review.

Demo flow: (1) normal withdrawal — passes, no flag; (2) burst of large withdrawals
— reactive callback pauses the vault mid-burst, remaining withdrawals revert;
(3) AI agent scores the burst and posts its verdict on-chain; (4) legitimate burst
→ vault unpauses, withdrawals resume.

### Why this concept

- **Execution (judging, gate):** entries without visible reactive transactions +
  callbacks "aren't scored further". The pause callback IS the reactive loop, on
  every demo run.
- **Integration:** the reactive contract does real work (it is the circuit-breaker,
  not a bolt-on notifier).
- **Usefulness:** drain protection is a real problem every vault has.
- **Craft:** readable contracts, a working demo, docs someone else can follow.
- **Reactive Meets AI:** the neural/AI half is a genuine part of the loop (the
  verdict decides the vault's state), not decoration.

## 3. Architecture

```
Base Sepolia (origin chain)                Reactive Network (Lasna testnet)
┌─────────────────────────┐                ┌──────────────────────────────┐
│ Vault (demo vault)      │  Withdrawal    │ CircuitBreaker (reactive)  │
│  deposit / withdraw /   │ ──events──────▶│  subscribe(Vault.Withdrawal)│
│  pause / unpause        │                │  rolling-window threshold    │
│                         │ ◀──pause()──── │  callback → pause vault    │
└─────────────────────────┘                └──────────────┬───────────────┘
                                                          │ flag event
                                                          ▼
                                   VerdictOracle (on Base Sepolia)
                                   AI agent (Node/TS, Groq LLM via
                                   OpenAI-compatible endpoint if the
                                   key/route works, else a local
                                   heuristic scorer — document which)
                                   posts ATTACK/LEGITIMATE + reason;
                                   LEGITIMATE → unpause()
```

**Contracts (Solidity, Foundry):**
- `Vault.sol` — demo vault: deposit (accept ETH or a test ERC20 — pick one and
  keep it), withdraw with pause guard, `pause()/unpause()` restricted to the
  reactive contract + owner, events.
- `CircuitBreaker.sol` — reactive contract: subscribes to `Withdrawal` events,
  tracks volume in a rolling window (timestamps, NOT block counts — Base Sepolia
  makes 200 ms blocks), threshold configurable, callback pauses the vault, emits
  `BurstFlagged`.
- `VerdictOracle.sol` — stores AI verdicts per burst (burstId, verdict, reason
  hash, timestamp); `LEGITIMATE` verdict unpauses the vault.

**AI agent (Node/TS):** polls `BurstFlagged` events, fetches burst details
(amounts, sender set, timing, each sender's prior history), asks the model to
classify + give a one-line reason, submits the verdict tx. Keep the model call
behind one interface so the scorer can be swapped (LLM vs heuristic) without
touching the loop.

## 4. Judging (from the event page, 4 criteria, 1–5 each, equally weighted)

| Criterion | How this entry scores |
|---|---|
| Execution | Reactive txs + callbacks on-chain in every demo run (the gate). |
| Integration | Reactive contract IS the breaker; AI verdict drives vault state. |
| Usefulness | Drain protection for any withdrawable vault. |
| Craft | Readable code, working demo, docs to reproduce. |

## 5. Chain + deployment — RESEARCH FIRST

The DoraHacks page text did NOT include the per-track brief sections — **research
these from the official Reactive docs before writing code:**
- Reactive Network docs (reactive.network): reactive contract pattern
  (`subscribe`, callback, `reactive` contract deployment on Lasna testnet),
  how to deploy + fund a reactive contract (REACT test tokens — faucet?),
  subscription mechanics and gas.
- Origin chains: Unichain Sepolia + Base Sepolia — public RPCs, faucets for
  test ETH, block explorers for tx links.
- Base Sepolia produces blocks every ~200 ms: use timestamps for windows/
  cooldowns (per the event's own ground rule).
- Groq as the AI model route: Groq exposes an OpenAI-compatible API. The
  connected Groq account exists; confirm from the Groq connector doc how to call
  it, keep the key server-side only, never in the repo. If Groq does not fit,
  fall back to a transparent heuristic scorer and SAY SO in the README (do not
  fake an AI verdict).

## 6. Repo plan

```
dorahacks-reactive-omni-buildathon/
├── DESIGN.md            ← this file
├── README.md            ← problem, loop, setup, deploy, demo, tx links
├── LICENSE              ← MIT
├── contracts/           ← Foundry: Vault.sol, CircuitBreaker.sol,
│                          VerdictOracle.sol + tests + deploy scripts
├── agent/               ← AI verdict agent (Node/TS)
└── docs/                ← demo script, screenshots, tx hashes (full loop:
                           origin event → reactive tx → callback → verdict)
```

Deliverables (per the event page): public repo link + deployed contract
addresses + tx hashes showing the FULL loop (origin event → callback) + demo
video under 3 minutes. Repo name (public, `rezimx-btc/`):
`reactive-circuit-breaker` (confirm at build time).

## 7. Risks + open questions

1. **Reactive docs / faucet unknowns** — research first; if the Lasna faucet or
   subscription flow blocks, report to the coordinator, don't fake the loop.
2. **Track-brief details missing from the fetched page** — the builder must pull
   the Reactive Meets AI brief from Reactive docs; if the brief demands
   something this design lacks, adapt and note it.
3. **AI model route** — Groq vs heuristic; decide after the connector check,
   document honestly.
4. **Two origin chains?** Start with Base Sepolia only; add Unichain Sepolia
   only if time remains — one working loop beats two half-loops.
5. **Demo video (<3 min)** — the builder produces a scripted terminal demo +
   screenshots; video assembly is a later (parent) step.
