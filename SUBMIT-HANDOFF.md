# SUBMIT HANDOFF — Reactive Omni Buildathon (DoraHacks)

**Status: READY TO SUBMIT.** Deploy + demo + video all done and verified
on-chain 2026-11-21. The parent only needs to: (1) create the public
GitHub repo via browser task, (2) verify it independently (ls-remote +
shallow clone), (3) submit the DoraHacks Build form. **Do NOT create the
repo or submit before reading the verification checklist at the end.**

- **Event:** Reactive Omni Buildathon — https://dorahacks.io/hackathon/reactive-omni-buildathon/detail
- **Track:** Reactive Meets AI
- **Prize:** $5,500 in REACT
- **Deadline:** 6 Dec 2026, 03:00 WIB (20:00 UTC, 5 Dec)
- **Team:** Solo — Uzansyah (rezimx-btc)
- **Project:** Reactive Circuit-Breaker with AI verdict

## What it is

A reactive contract on Reactive Lasna watches a vault on Base Sepolia
every second. When withdrawals burst past a threshold (0.005 ETH / 60 s)
it pauses the vault automatically via callback — and an AI agent (Groq
`openai/gpt-oss-20b`) judges the burst attack vs legitimate, so the pause
lifts fast when it was a false alarm. Demoed live end-to-end: burst →
pause in 6 blocks → 4th withdrawal reverts → LEGITIMATE verdict on-chain
→ vault unpauses → withdrawals resume.

## Contract addresses (all verified on-chain)

| Contract | Chain | Address | Explorer |
|---|---|---|---|
| Vault | Base Sepolia (84532) | `0x736749e20AB19A2E84299FA4794f883D6Af7BBF5` | https://sepolia.basescan.org/address/0x736749e20AB19A2E84299FA4794f883D6Af7BBF5 |
| VerdictOracle | Base Sepolia (84532) | `0x156C23756e01EF3E01C87cdcB04f9687b0179C8A` | https://sepolia.basescan.org/address/0x156C23756e01EF3E01C87cdcB04f9687b0179C8A |
| CircuitBreaker | Reactive Lasna (5318007) | `0x2381c5c6730a09b3e0750fe84044d3d9a039fc42` | https://lasna.reactscan.net/address/0x2381c5c6730a09b3e0750fe84044d3d9a039fc42 |

Deployer (fresh testnet-only key, NOT the user's wallet, NOT the Muse
EOA): `0xc92Ba015a2b5Cf53D3BDe3D3b074616F43fCc0c7`.
Breaker parameters: window 60 s, threshold **0.005 ETH**
(5,000,000,000,000,000 wei). Vault owner = deployer; Oracle agent =
deployer; Breaker owner = deployer. `paused() = false`,
`flagged() = false` (final state, verified after demo run #2).

## Funding path (testnet only)

1. User sent 0.05 Sepolia ETH to the deployer:
   `0xd8e36df6b6d6b9fe579d1fd0cd2b0246f8cf9185697916d323b8f3d3a8f0e13b`
   (Sepolia block 12182892, gasUsed 204,600, status 0x1;
   from wallet 2 `0x9cC55F95836e30F518ce28347f6216314ec6FdF2`).
2. Bridged 0.048 ETH Sepolia → Base Sepolia via the Optimism Standard
   Bridge (`depositETHTo`, L1StandardBridge
   `0xfd0Bf71F60660E2f608ed56e1659C450eB113120`, verified from official
   Base docs):
   `0xc6dac952d874c3607f605c58f968815ed217a418d5789ab113ff114aeefe6260`
   (Sepolia block 12183026, gasUsed 534,353, status 0x1; landed on Base
   Sepolia as 48,000,000,000,000,000 wei after ~8 min).
   Note: the first bridge attempt with `_l2Gas` 200,000 + 2M L1 gas
   limit REVERTED (tx
   `0xe854bd35bb70d797d17f9f08f6e8038928cd67d29de3b206ae8d422c7ba74a9e`,
   status 0x0 — the bridge's `metered()` modifier burns L1 gas
   proportional to `_l2Gas`). The retry with `_l2Gas` 100,000 + 6M
   limit succeeded.
3. Faucets were all tried first and failed (Coinbase needs sign-in;
   Alchemy + Chainlink Turnstile failed repeatedly in the cloud browser;
   QuickNode needs mainnet ETH on the wallet; Infura's public faucet no
   longer exists). The bridge was the path that worked.

## Deploy tx hashes (all status 0x1)

| Step | Tx hash | Block | gasUsed |
|---|---|---|---|
| 0 — lREACT faucet swap (0.012 ETH → 1.2 lREACT) | `0xf51725dd96270a90d5487c7d5710f65a4f7f99000d7bf0634156ff28b6befa9c` | 61786203 (Base Sepolia) | 24,794 |
| 1 — Vault deploy | `0xf04b0c35f9a74c7e5047cf4b9f06988d4c20e371e4cb0555e8c504250fb4af86` | 61786334 | 1,165,944 |
| 1b — VerdictOracle deploy | `0x664ea9cf417ba22853d95ea08da9861314ad4e3f72df27b4fc74818e5e1ab4e1` | 61786359 | 984,937 |
| 2 — CircuitBreaker deploy (Lasna) | `0x96e00e2b7ddc35d50ec4e2747155415f467f4493d645bcafff06d60c13a71c02` | 8906993 (Lasna) | 1,916,845 |
| 3a — `setCircuitBreaker` | `0x3d6adf9d3ebcd1c3ad23c48bce183eaa7118a6d88144620a5d59c125f2afff91` | 61787392 | 45,298 |
| 3b — `setVerdictOracle` | `0xb8e4f564b6b835e5f80e13b5844eafbc517d0ae82ea3d27be0d03f052e2c9c68` | 61787419 | 45,320 |
| 4 — `subscribe()` (Lasna) | `0xed93ff07669c962b43ddf22d21352be0a2407dd45488e26645d16fba5601158a` | 8907005 (Lasna) | 38,204 |
| 5a — `depositTo` breaker reserves (0.5 lREACT) | `0xa8a89b422ffd602aefa9f4d4f6011fa7f33b254911ec7d622e1a5949dcd4d49a` | 8907011 (Lasna) | 51,795 |
| 5b — `depositTo` vault callback reserves (0.005 ETH) | `0xda0c76b64abe54c6c370f2b409c88fa7cc8abf6e017234ecfecb3a7b9d90aa6b` | 61787487 | 51,889 |

Receipts: `deploy-logs/` (13 files). Summary: `deploy-results.json`.
Addresses: `deployments.json` (gitignored — addresses are in the README
and `deploy-results.json` instead).

## Demo results

Full record: `docs/demo-results.md`. Two runs on the same contracts.

### Run #2 — RECORDED, clean full loop (the video run)

Users: `0x6E5A31D4e1616eb48a8E8A718306bdd4e64A752c`,
`0x7BaBA4d66527235ce35c4170A8e8881B769208Db`,
`0x61771ED4702fe69bcE3B93b07D0D2e5B4290A233`.
Amounts: deposit 0.005 ETH, prior/normal withdrawal 0.0005 ETH, burst
withdrawal 0.002 ETH ×3.

| Step | Tx hash | Block | gasUsed |
|---|---|---|---|
| Fund users (0.0051 ETH gas each) | `0x6296abeff1eec1627c3a1794db52aae7a52b9ce39d343224d1715659c683e8bb` · `0x3a4356763c08e3ec0611e35998350704e4b27d3eaf28ee7213548c6e697ff1c3` · `0xfd785a1b193e68918f0b43ed6aecfa14db299a4928c32f414c72b51d9484987d` | 61790138 / 61790157 / 61790173 | — |
| Deposits (0.005 ETH each) | `0xa1365bbf12212bb4d6f70d86c34fcb165227df8e118ff9c803997874466cf87c` · `0x433d266be9949296e832ac34e9c752c87ea3171ff04946e085b02fa98fba6e65` · `0x206e8efdae13c6aacd7225f5034773c078c2231b2d7345087e4d47eb38fd5d71` | 61790192 / 61790223 / 61790257 | — |
| Prior withdrawals (0.0005 ETH each) | `0x9c61f6d9718e22cfdbc96a1946668757279897f9cabfce72330632aba45ef711` · `0x42be4d62245f19c30372a39290981d96c766cc373492c04657bb701df6f3c2d8` · `0xacb2ba5a16cc2e0df44bef68e18f51effbac00f8caaa80b016c201a6e121290e` | 61790207 / 61790238 / 61790271 | — |
| Normal withdrawal 0.0005 ETH (passes) | `0xc03f897cd29420df4020ba936db7d4e7b2564dc41e98f35a585ad9043e5ae514` | 61790665 | 38,095 |
| Burst w/d 1: 0.002 ETH | `0x2473d0d57bcab6dd3cca4a130c7384c17738f3230095a7be513b0ecc3b76a02f` | 61790724 | 38,083 |
| Burst w/d 2: 0.002 ETH | `0x40facdfaf849115c050c9c453b91f1758e10ed6619b53a6b9556972d5ebed1fc` | 61790866 | 38,083 |
| Burst w/d 3: 0.002 ETH (trips breaker) | `0x8e07f8a0a7bdf1e8ba23ade136948422d469d2df3163ce2f27be9e8ffd505d82` | 61791010 | 38,083 |
| Reactive tx (`react()` + `BurstFlagged` #2, Lasna) | `0x4afbf412b0b7612e8bbb15b43b36c86d376f0c526b7dfc3e3049b37cd006588f` | 8907683 | 240,571 |
| Callback tx (`pauseViaCallback`) | `0xbfa0f0a9e3e1f4c1db4c48faf7c853c04fc49be5032411badc23e639f7f0026c` | 61791016 | 87,517 |
| 4th withdrawal reverts while paused | No tx — reverted at gas estimation: `execution reverted, data: 0x9e87fac8: Paused` (see `demo-logs/wd4-blocked.json`) | — | — |
| AI verdict (`submitVerdict` LEGITIMATE) | `0x26b28a71c1cf25d08c04774101aa2b2e42209508c538f657d0b3085e4034af9c` | 61791216 | 172,131 |
| Breaker re-armed (`clearFlag()`, Lasna) | `0x794adc190a6d20631be9f7b18f12dd667b6fd30d1429ea46f03f95695840bf67` | 8907726 | 24,872 |
| Withdrawal resumes after unpause | `0x0a3b854a29b2a092b23c85c08815dc3b354a7e681d4179a7168f48f5bb624084` | 61791306 | 38,095 |

Verdict detail: **LEGITIMATE via Groq `openai/gpt-oss-20b`** — "69s span
and no single sender exceeds 80% of volume." Features: 4 withdrawals,
3 senders, total 0.0065 ETH, max single 0.002 ETH, dominant share 0.30,
span 69 s. Burst volume at trip: 0.006 ETH (the normal 0.0005 ETH aged
out of the 60 s window before the trip — Lasna/Base Sepolia clock skew
of a few seconds; trip still fired exactly at burst w/d 3 as designed).

Final on-chain state: Vault `paused() = false`, Breaker
`flagged() = false`, `verdicts(1) = LEGITIMATE`,
`verdicts(2) = LEGITIMATE`.

### Run #1 — reactive path proved; agent crashed, state reset manually

Same contracts, same flow. Reactive path worked (pause 8 blocks after
burst w/d 3, 4th withdrawal reverted), but the agent crashed before
posting its verdict: `eth_getLogs is limited to a 200 range` (Base
Sepolia RPC caps log queries at 200 blocks; the agent's scan spanned
~2,300 blocks). Fixed in `agent/index.mjs` (chunked ≤200-block scans;
one wide query split by timestamp; skip bursts that already have an
on-chain verdict). State was reset with a manual verdict and run #2
re-ran the full loop with the agent.

| Step | Tx hash | Block | gasUsed |
|---|---|---|---|
| Reactive tx (`BurstFlagged` #1, Lasna) | `0x9e266a4e40d05b4fe019ce69168611bdebb74d9763937b34ee858907950a49e5` | 8907294 | 280,200 |
| Callback tx (`pauseViaCallback`) | `0xbc3dc6d4595a39781065c9bfa8710c598d864b11162d59a3f670236f4fdebdec` | 61788966 | 87,517 |
| Burst w/d 3 | `0xb90cb16f420df19327b28d7635cb7bbac2c8935c23a30489387bd332370a3932` | 61788958 | — |
| 4th withdrawal reverts while paused | No tx — reverted: `execution reverted, data: 0x9e87fac8: Paused` (see `demo-logs-run1/wd4-blocked.json`) | — | — |
| Manual reset verdict (LEGITIMATE) | `0x5f65d602573d75f09daacb5829beef1f0bb34d65f60c2b8d8f83aa17080ec08a` | 62014653 | 263,688 |
| Manual re-arm (`clearFlag()`, Lasna) | `0xb859ee47c84036a3c4c7f3783aaed9b3c77f64ef831a84135198bdb5f31a6fdb` | 8908243 | 24,872 |

Manual verdict reason (on-chain): "legitimate burst: 3 known senders,
55s span, spread amounts; agent run crashed on RPC eth_getLogs
200-block limit before posting, verdict posted manually to reset demo
state". Run #1 evidence: `demo-logs-run1/` + `demo-txlog-run1.txt` +
`docs/demo-recorded-run1.typescript`.

### Attack-burst run — NOT RUN (follow-up, not a blocker)

The attack-burst flow (1 fresh sender, 3 fast withdrawals →
`ATTACK_LIKE` → vault stays paused) was designed but not executed: the
deployer holds ~0.00008 Base Sepolia ETH after run #2, and the run
needs ~0.015 ETH of fresh user funding. The classifier rules for
`ATTACK_LIKE` were verified offline (Groq: 1-sender/3 s burst →
`ATTACK_LIKE`). The legitimate-burst loop (the event's core flow) is
fully proven live.

## Video

- **File:** `video/reactive-circuit-breaker-demo.mp4`
- **Length:** 149.4 s (2:29 — under the 3-min limit)
- **Format:** 1280×720, H.264, 10 fps
- **Size:** 1,638,738 bytes
- **SHA-256:** `d3ebae3d09114670340b1c19da60ce381289f55a67992ee75a8e5e0475ce44e7`
- **Recorded:** live run #2 via `script -T`
  (`docs/demo-recorded.typescript` + `docs/demo-recorded.timing`);
  rendered verbatim with `docs/render-demo-video.py` (PIL + ffmpeg,
  idle gaps capped at 12 s; raw 238.1 s → 141.8 s + 3 s title + 4 s end
  card). Verified with ffprobe + 5 visual frame checks.
- **Raw URL for the form** (after the repo is created, replace
  `<repo>` with the actual repo name):
  `https://raw.githubusercontent.com/rezimx-btc/<repo>/main/video/reactive-circuit-breaker-demo.mp4`
  (the validator only accepts a direct .mp4 URL; raw.githubusercontent
  is accepted, a GitHub release-asset URL is NOT).

Honest caveats (already in the README + `docs/demo-results.md`, do not
hide them): run #2's recorded agent features line shows
`nFreshSenders: 3` — the prior-history query in the recorded run missed
the setup priors; the verdict was driven by the 69 s span + spread and
is correct, and the query is fixed in the current `agent/index.mjs`
(validated read-only on burst #2: all 3 senders recognised as known).
The video also contains a ~15 s raw JSON receipt dump after the
`submitVerdict: ok=true` line; the agent now logs a one-line receipt
summary instead.

## Repo file list (for the browser task)

Suggested repo name: **`rezimx-btc/reactive-circuit-breaker`**
(public). Upload from `~/workspace/dorahacks-reactive-omni-buildathon/`:

**INCLUDE (tracked files):**
- `.env.example`, `.gitignore`, `DESIGN.md`, `LICENSE` (MIT),
  `README.md`, `SUBMIT-HANDOFF.md` (this file)
- `agent/index.mjs`, `agent/verdict.mjs`, `agent/package.json`
- `contracts/foundry.toml`, `contracts/foundry.lock`,
  `contracts/src/CircuitBreaker.sol`, `contracts/src/Vault.sol`,
  `contracts/src/VerdictOracle.sol`,
  `contracts/test/CircuitBreaker.t.sol`, `contracts/test/Vault.t.sol`,
  `contracts/test/VerdictOracle.t.sol`,
  `contracts/script/deploy.sh`
- `docs/demo-results.md`, `docs/demo.sh`, `docs/research.md`,
  `docs/render-demo-video.py`, `docs/demo-recorded.typescript`,
  `docs/demo-recorded.timing`, `docs/demo-recorded-run1.typescript`,
  `docs/demo-recorded-run1.timing`
- `deploy-results.json`, `demo-results.json`, `demo-txlog.txt`,
  `demo-txlog-run1.txt`
- `deploy-logs/` (13 receipt JSON files)
- `demo-logs/` (15 receipt JSON files, run #2)
- `demo-logs-run1/` (16 receipt JSON files, run #1)
- `video/reactive-circuit-breaker-demo.mp4`

**DO NOT UPLOAD (gitignored / build output / local state):**
- `contracts/lib/` (forge-std submodule — do NOT upload via web; the
  README does not say "forge install")
- `contracts/out/`, `contracts/cache/`
- `deployments.json` (gitignored; addresses are in the README +
  `deploy-results.json`)
- `agent/state.json`, `agent/node_modules/`
- `*.log` files (`deploy-run.log`, `demo-run.log`, etc.)
- `.env` (never exists in the repo; the deployer key lives OUTSIDE it
  in `~/.dorahacks-testnet/deployer.json`, chmod 600)

**Secret scan (21 Nov ~17:00 WIB):** grep for
`private[_-]?key|mnemonic|seed` across the repo found only code
references (`$PRIVATE_KEY` variable usage in deploy.sh/demo.sh, read
from a file outside the repo) and forge-std library text. No deployer
or user private key, seed, or API key is in any repo file. The 64-hex
values in `agent/index.mjs` are public event topic hashes, not keys.

**About repo (set in the browser):**
- Description: "Reactive circuit-breaker with AI verdict — a reactive
  contract on Lasna pauses a Base Sepolia vault when withdrawals burst,
  and a Groq AI agent judges attack vs legitimate on-chain."
- Website: https://sepolia.basescan.org/address/0x736749e20AB19A2E84299FA4794f883D6Af7BBF5
- Topics: `reactive`, `lasna`, `base-sepolia`, `ai-agents`, `smart-contracts`, `foundry`, `solidity`, `groq`

## DoraHacks Build form contents

Submit via the **form Build** (per the dorahacks-submission skill —
Reactive uses form Build, NOT API or PR). Event page:
https://dorahacks.io/hackathon/reactive-omni-buildathon/detail

- **Project name:** Reactive Circuit-Breaker with AI verdict
- **Brief description:** A reactive contract on Reactive Lasna watches
  a vault on Base Sepolia; when withdrawals burst past a threshold it
  pauses the vault automatically via callback, and an AI agent (Groq
  gpt-oss-20b) judges the burst attack vs legitimate on-chain, so the
  pause lifts fast when it was a false alarm. Deployed and demoed live
  on testnet.
- **Team Info:** Solo (Uzansyah) — sole builder: smart contracts,
  reactive logic, AI agent, demo, and video, end to end.
- **GitHub repo:** https://github.com/rezimx-btc/reactive-circuit-breaker
  (replace with the actual repo URL after creation)
- **Video:** https://raw.githubusercontent.com/rezimx-btc/reactive-circuit-breaker/main/video/reactive-circuit-breaker-demo.mp4
  (replace `<repo>` if the repo name differs; must be the raw .mp4 URL)
- **Pitch deck:** (none — no deck was produced for this entry; leave
  blank if the field is optional)
- **Track:** Reactive Meets AI
- **Looking for teammates:** No
- **Contact Info (organizer-only):** Telegram **@Xtrehb** (never
  @Xtrenuh — that is a misspelling) + backup Discord **ridhonsyah**
- **Description (full — paste as-is):**

> Reactive Circuit-Breaker with AI verdict — Reactive Meets AI track.
>
> A reactive contract on Reactive Lasna (5318007) watches a vault on
> Base Sepolia (84532). When withdrawals burst past 0.005 ETH in a
> 60-second window it pauses the vault automatically via callback, and
> an AI agent (Groq openai/gpt-oss-20b) judges the burst attack vs
> legitimate on-chain, so the pause lifts fast when it was a false
> alarm.
>
> Contracts (testnet, verified on-chain):
> - Vault (Base Sepolia): 0x736749e20AB19A2E84299FA4794f883D6Af7BBF5 —
>   deploy tx 0xf04b0c35f9a74c7e5047cf4b9f06988d4c20e371e4cb0555e8c504250fb4af86
>   (block 61786334)
> - VerdictOracle (Base Sepolia):
>   0x156C23756e01EF3E01C87cdcB04f9687b0179C8A — deploy tx
>   0x664ea9cf417ba22853d95ea08da9861314ad4e3f72df27b4fc74818e5e1ab4e1
>   (block 61786359)
> - CircuitBreaker (Lasna):
>   0x2381c5c6730a09b3e0750fe84044d3d9a039fc42 — deploy tx
>   0x96e00e2b7ddc35d50ec4e2747155415f467f4493d645bcafff06d60c13a71c02
>   (block 8906993)
> - Wiring: setCircuitBreaker
>   0x3d6adf9d3ebcd1c3ad23c48bce183eaa7118a6d88144620a5d59c125f2afff91,
>   setVerdictOracle
>   0xb8e4f564b6b835e5f80e13b5844eafbc517d0ae82ea3d27be0d03f052e2c9c68,
>   subscribe()
>   0xed93ff07669c962b43ddf22d21352be0a2407dd45488e26645d16fba5601158a
>
> Live demo (run #2, recorded — video link above):
> - Normal withdrawal 0.0005 ETH passes (tx
>   0xc03f897cd29420df4020ba936db7d4e7b2564dc41e98f35a585ad9043e5ae514).
> - Burst: 3 withdrawals of 0.002 ETH by 3 users (txs 0x2473d0d5…,
>   0x40facdfa…, 0x8e07f8a0…).
> - Reactive tx on Lasna flags burst #2 (volume 0.006 ETH, tx
>   0x4afbf412b0b7612e8bbb15b43b36c86d376f0c526b7dfc3e3049b37cd006588f,
>   block 8907683).
> - Callback pauses the vault 6 blocks later (tx
>   0xbfa0f0a9e3e1f4c1db4c48faf7c853c04fc49be5032411badc23e639f7f0026c,
>   block 61791016).
> - 4th withdrawal reverts while paused (execution reverted, Paused).
> - AI agent posts LEGITIMATE via Groq gpt-oss-20b ("69s span and no
>   single sender exceeds 80% of volume.", tx
>   0x26b28a71c1cf25d08c04774101aa2b2e42209508c538f657d0b3085e4034af9c,
>   block 61791216).
> - Breaker re-armed (clearFlag tx
>   0x794adc190a6d20631be9f7b18f12dd667b6fd30d1429ea46f03f95695840bf67),
>   withdrawal resumes (tx
>   0x0a3b854a29b2a092b23c85c08815dc3b354a7e681d4179a7168f48f5bb624084).
> - Final state: vault paused() = false, breaker flagged() = false,
>   verdicts(1) and verdicts(2) both LEGITIMATE.
>
> An earlier run #1 proved the same reactive path (pause + revert) but
> the agent crashed on an RPC eth_getLogs 200-block limit; the state
> was reset with a manual verdict and run #2 re-ran the full loop with
> the agent. Full tx record: docs/demo-results.md in the repo.
>
> Tests: forge test 19/19 pass. License: MIT. Testnet only — no
> mainnet deployment, no real funds.

## Verification checklist for the parent (do BEFORE submit)

1. Repo created via browser task (public, rezimx-btc). Confirm the
   upload list above — no `contracts/lib/`, no `*.log`, no
   `deployments.json`, no `agent/state.json`.
2. Independent verification: `git ls-remote` HEAD SHA must match the
   browser task's reported HEAD; shallow-clone and check
   `video/reactive-circuit-breaker-demo.mp4` sha256 =
   `d3ebae3d09114670340b1c19da60ce381289f55a67992ee75a8e5e0475ce44e7`
   and the three contract addresses in the README.
3. Confirm the raw video URL returns the .mp4 (validator rejects
   GitHub release-asset URLs).
4. Submit the Build form with the contents above. Success = dialog
   "Build Submitted!" + "Manage Submission", and the entry appears in
   Your Build on the hackathon page.
5. Read-only verification: the public build page shows the project
   name, track "Reactive Meets AI", Members 1, Team Solo (Uzansyah),
   Updated minutes ago. (The "Under Review" label does not appear on
   the public page — same as Aevum 51503 and HSK 51520.)
6. Record the Build ID + URL and report to the user. Do NOT touch
   Aevum (51503) or HSK (51520).

## Leftover state / follow-ups

- Deployer balances after run #2: Base Sepolia ~0.0000845 ETH,
  Lasna ~0.494 lREACT — NOT enough for another demo run. A further
  run (e.g. the attack-burst flow) needs ~0.015 Base Sepolia ETH of
  fresh funding and is a follow-up, not a submit blocker.
- `agent/state.json` (gitignored, local only) holds
  `lastLasnaBlock: 8907879`, `doneBursts: [2]` — the agent will not
  re-process burst #2.
- No mainnet anything. No user-wallet funds were spent. The only user
  funds involved were the 0.05 Sepolia ETH the user sent for this exact
  task (0.048 bridged, rest spent on bridge gas + deploy + demo gas).
