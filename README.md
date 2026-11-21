# Reactive Circuit-Breaker with AI verdict

**Event:** Reactive Omni Buildathon (DoraHacks) · **Track:** Reactive Meets AI ·
**Team:** rezimx-btc (solo) · **Status:** ✅ deployed on testnet, demoed
live end-to-end, video recorded (21 Nov 2026).

> A reactive contract watches the vault every second; when withdrawals burst
> past a threshold it pauses the vault automatically — and an AI agent judges
> the burst attack vs legitimate, so the pause lifts fast when it was a false
> alarm.

## How it works

```
Base Sepolia (84532)                         Reactive Lasna (5318007)
┌──────────────────────┐  Withdrawal       ┌─────────────────────────────┐
│ Vault                │  events           │ CircuitBreaker (reactive)   │
│  deposit / withdraw  │ ───────────────▶  │  rolling 60s window,        │
│  pause / unpause     │                   │  threshold 0.005 ETH,       │
│                      │ ◀── pause() ────  │  callback → pause vault     │
└──────────────────────┘  (via callback   └──────────────┬──────────────┘
                          proxy)                         │ BurstFlagged
                                                         ▼
                                   VerdictOracle (Base Sepolia)
                                   AI agent (Groq gpt-oss-20b, or
                                   transparent heuristic fallback)
                                   LEGITIMATE → unpause()
```

Demo flow: (1) normal withdrawal passes; (2) burst of large withdrawals —
reactive callback pauses the vault mid-burst, further withdrawals revert;
(3) AI agent scores the burst and posts its verdict on-chain;
(4) legitimate burst → vault unpauses, withdrawals resume.

## Contracts (`contracts/`, Foundry, Solidity 0.8.29)

| Contract | Chain | Role |
|---|---|---|
| `Vault.sol` | Base Sepolia | ETH demo vault; `Withdrawal` events; `pauseViaCallback` authenticated by callback proxy + breaker address; `unpauseByOracle` by VerdictOracle/owner |
| `CircuitBreaker.sol` | Reactive Lasna | Subscribes to `Withdrawal`; rolling window by `block.timestamp` (NOT block counts — Base Sepolia makes ~200 ms blocks); trips at ≥ 0.005 ETH / 60 s; `requestCallbackV_1_0` → `pauseViaCallback`; emits `BurstFlagged` |
| `VerdictOracle.sol` | Base Sepolia | One verdict per burst (`LEGITIMATE` / `ATTACK_LIKE` + one-line reason); `LEGITIMATE` auto-unpauses the vault |

Tests: **19/19 pass** (`forge test` in `contracts/`).

Note on the Reactive library: the official `reactive-lib` was fetched but
tripped an execution-risk check on this machine, so it was deleted unused.
The contracts implement the minimal documented interfaces by hand
(`ISystemContractMinimal`, `pay()`, `receive()`, `LogRecord`) using only
values from the official docs — see `docs/research.md`.

## AI verdict agent (`agent/`, Node ≥ 20, zero dependencies)

Polls `BurstFlagged` on Lasna, gathers the burst's withdrawals + each
sender's prior history on Base Sepolia, classifies, posts the verdict.

- **Model (verified): Groq `openai/gpt-oss-20b`** via the OpenAI-compatible
  API. The agent never touches the key: it shells out to the registered
  `custom.groq` connector helper, or uses `GROQ_API_KEY` if set.
  Verified 21 Nov 2026: 1-sender/3 s burst → `ATTACK_LIKE`; 3-known-sender/
  55 s burst → `LEGITIMATE`, both with one-line reasons.
- **Fallback:** if no Groq route works, a transparent heuristic scorer
  (rules in `agent/verdict.mjs`) decides and the verdict is labelled
  `model: "heuristic"` — never presented as an LLM verdict.
- The prompt uses strict decision rules (attack only on ≥80% single-sender
  share or ≥3 withdrawals in <10 s by fresh senders; doubt → LEGITIMATE);
  a loose prompt was observed over-flagging a legitimate burst.

## Setup

```bash
cp .env.example .env   # no secrets in the repo, ever
# deployer key: fresh testnet-only key, OUTSIDE the repo:
#   ~/.dorahacks-testnet/deployer.json (chmod 600)
#   created with: cast wallet new --json
export PATH="$HOME/.foundry/bin:$PATH"
cd contracts && forge test
```

## Deploy (TESTNET ONLY — never mainnet)

```bash
bash contracts/script/deploy.sh   # writes deployments.json + deploy-results.json
```

Needs, before running: Base Sepolia ETH on the deployer (the script's
step 0 swaps 0.012 Base Sepolia ETH → 1.2 lREACT via the Reactive faucet
`0x2afaFD298b23b62760711756088F75B7409f5967`). The breaker is deployed
with `cast send --create`, not `forge script` (the subscribe precompile
reverts under forge simulation — see research).

**Funding path actually used (21 Nov 2026):** the user sent 0.05
Sepolia ETH to the deployer (tx
`0xd8e36df6b6d6b9fe579d1fd0cd2b0246f8cf9185697916d323b8f3d3a8f0e13b`,
Sepolia block 12182892); 0.048 ETH was bridged Sepolia → Base Sepolia
via the Optimism Standard Bridge (`depositETHTo`, tx
`0xc6dac952d874c3607f605c58f968815ed217a418d5789ab113ff114aeefe6260`,
Sepolia block 12183026, gasUsed 534,353; landed ~8 min later).
Faucets (Coinbase, Alchemy, Chainlink, QuickNode, Infura) were all
tried first and failed — browser login / Turnstile / mainnet-balance
gates. Bridge address verified from the official Base docs
(`0xfd0Bf71F60660E2f608ed56e1659C450eB113120`); note the v2.8.0 bridge
has no `depositETH(address,uint32,bytes)` — the working signature is
`depositETHTo(address,uint32,bytes)`, and the L1 gas limit must be
≥ 6M with `_l2Gas` 100,000 (the `metered()` modifier burns L1 gas
proportional to `_l2Gas`; a 2M-limit attempt reverted).

## Demo

```bash
bash docs/demo.sh   # normal withdrawal -> legitimate burst -> pause -> AI verdict -> unpause
node agent/index.mjs --once   # single agent pass (or without --once to watch)
```

Full results (every tx hash, block, gasUsed): [docs/demo-results.md](docs/demo-results.md).
Demo video: `video/reactive-circuit-breaker-demo.mp4` (149.4 s, 1280×720,
sha256 `d3ebae3d09114670340b1c19da60ce381289f55a67992ee75a8e5e0475ce44e7`).

Demo amounts are scaled to the deployed threshold (0.005 ETH / 60 s):
deposit 0.005 ETH, prior/normal withdrawal 0.0005 ETH, burst
withdrawal 0.002 ETH ×3. Run #2 is the clean recorded run: burst w/d 3
trips the breaker (volume 0.006 ETH), callback pauses the vault 6 blocks
later, the 4th withdrawal reverts, the Groq `openai/gpt-oss-20b` agent
posts LEGITIMATE ("69s span and no single sender exceeds 80% of
volume."), the vault unpauses and withdrawals resume.

## Deployed addresses / tx hashes

**DEPLOYED + VERIFIED on-chain 21 Nov 2026.** Deployer (fresh
testnet-only key, outside the repo):
`0xc92Ba015a2b5Cf53D3BDe3D3b074616F43fCc0c7`.

| Contract | Chain | Address | Deploy tx |
|---|---|---|---|
| Vault | Base Sepolia (84532) | `0x736749e20AB19A2E84299FA4794f883D6Af7BBF5` | `0xf04b0c35f9a74c7e5047cf4b9f06988d4c20e371e4cb0555e8c504250fb4af86` (block 61786334, gasUsed 1,165,944) |
| VerdictOracle | Base Sepolia (84532) | `0x156C23756e01EF3E01C87cdcB04f9687b0179C8A` | `0x664ea9cf417ba22853d95ea08da9861314ad4e3f72df27b4fc74818e5e1ab4e1` (block 61786359, gasUsed 984,937) |
| CircuitBreaker | Reactive Lasna (5318007) | `0x2381c5c6730a09b3e0750fe84044d3d9a039fc42` | `0x96e00e2b7ddc35d50ec4e2747155415f467f4493d645bcafff06d60c13a71c02` (block 8906993, gasUsed 1,916,845) |

Wiring: `setCircuitBreaker`
`0x3d6adf9d3ebcd1c3ad23c48bce183eaa7118a6d88144620a5d59c125f2afff91`
(61787392) · `setVerdictOracle`
`0xb8e4f564b6b835e5f80e13b5844eafbc517d0ae82ea3d27be0d03f052e2c9c68`
(61787419) · `subscribe()`
`0xed93ff07669c962b43ddf22d21352be0a2407dd45488e26645d16fba5601158a`
(8907005) · reserves `0xa8a89b422ffd602aefa9f4d4f6011fa7f33b254911ec7d622e1a5949dcd4d49a`
(0.5 lREACT, 8907011) and
`0xda0c76b64abe54c6c370f2b409c88fa7cc8abf6e017234ecfecb3a7b9d90aa6b`
(0.005 ETH, 61787487) · lREACT swap
`0xf51725dd96270a90d5487c7d5710f65a4f7f99000d7bf0634156ff28b6befa9c`
(61786203). Every step's receipt is in `deploy-results.json` /
`deploy-logs/`.

- Vault: https://sepolia.basescan.org/address/0x736749e20AB19A2E84299FA4794f883D6Af7BBF5
- VerdictOracle: https://sepolia.basescan.org/address/0x156C23756e01EF3E01C87cdcB04f9687b0179C8A
- CircuitBreaker: https://lasna.reactscan.net/address/0x2381c5c6730a09b3e0750fe84044d3d9a039fc42

Honest caveats: run #2's recorded agent features line shows
`nFreshSenders: 3` (the prior-history query missed the setup priors);
the verdict was driven by the 69 s span + spread and is correct, and
the query is fixed in the current `agent/index.mjs` (validated read-only
on burst #2: all 3 senders recognised as known). The video also contains
a ~15 s raw JSON receipt dump after the `submitVerdict: ok=true` line;
the agent now logs a one-line receipt summary instead. The attack-burst
run (→ `ATTACK_LIKE`, vault stays paused) was designed but not executed
— deployer funds are exhausted (~0.00008 Base Sepolia ETH) and it needs
~0.015 ETH of fresh user funding; the legitimate-burst loop (the event's
core flow) is fully proven live. See `docs/demo-results.md` for details.

## Links

- Reactive docs: https://dev.reactive.network/reactive-contracts ·
  https://dev.reactive.network/callback-contracts ·
  https://dev.reactive.network/origins-and-destinations ·
  https://dev.reactive.network/economy
- Base Sepolia explorer: https://sepolia.basescan.org ·
  Lasna explorer: https://lasna.reactscan.net/
- Design: [DESIGN.md](DESIGN.md) · Research: [docs/research.md](docs/research.md)

## License

MIT — see [LICENSE](LICENSE).
