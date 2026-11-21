# Demo results — full loop (origin event → reactive tx → callback → verdict)

Deployed and demoed live on testnet, 2026-11-21. Two demo runs were
executed against the same contracts; run #2 is the clean, recorded run
(video `video/reactive-circuit-breaker-demo.mp4`, typescript
`docs/demo-recorded.typescript`). Run #1 proved the reactive path but its
agent pass crashed on an RPC log-range limit; the state was reset with a
manual verdict and run #2 re-ran the full loop end-to-end with the agent.

## Deployments

| Contract | Chain | Address | Deploy tx |
|---|---|---|---|
| Vault | Base Sepolia (84532) | `0x736749e20AB19A2E84299FA4794f883D6Af7BBF5` | `0xf04b0c35f9a74c7e5047cf4b9f06988d4c20e371e4cb0555e8c504250fb4af86` (block 61786334, gasUsed 1,165,944) |
| VerdictOracle | Base Sepolia (84532) | `0x156C23756e01EF3E01C87cdcB04f9687b0179C8A` | `0x664ea9cf417ba22853d95ea08da9861314ad4e3f72df27b4fc74818e5e1ab4e1` (block 61786359, gasUsed 984,937) |
| CircuitBreaker | Reactive Lasna (5318007) | `0x2381c5c6730a09b3e0750fe84044d3d9a039fc42` | `0x96e00e2b7ddc35d50ec4e2747155415f467f4493d645bcafff06d60c13a71c02` (block 8906993, gasUsed 1,916,845) |

Wiring txs: `setCircuitBreaker`
`0x3d6adf9d3ebcd1c3ad23c48bce183eaa7118a6d88144620a5d59c125f2afff91`
(block 61787392, gasUsed 45,298) ·
`setVerdictOracle`
`0xb8e4f564b6b835e5f80e13b5844eafbc517d0ae82ea3d27be0d03f052e2c9c68`
(block 61787419, gasUsed 45,320) ·
`subscribe()`
`0xed93ff07669c962b43ddf22d21352be0a2407dd45488e26645d16fba5601158a`
(block 8907005, gasUsed 38,204) ·
`depositTo` breaker reserves (0.5 lREACT)
`0xa8a89b422ffd602aefa9f4d4f6011fa7f33b254911ec7d622e1a5949dcd4d49a`
(block 8907011, gasUsed 51,795) ·
`depositTo` vault callback reserves (0.005 ETH)
`0xda0c76b64abe54c6c370f2b409c88fa7cc8abf6e017234ecfecb3a7b9d90aa6b`
(block 61787487, gasUsed 51,889) ·
lREACT faucet swap (0.012 ETH → 1.2 lREACT)
`0xf51725dd96270a90d5487c7d5710f65a4f7f99000d7bf0634156ff28b6befa9c`
(block 61786203, gasUsed 24,794).

Funding path (testnet only): the user sent 0.05 Sepolia ETH to the
deployer
`0xd8e36df6b6d6b9fe579d1fd0cd2b0246f8cf9185697916d323b8f3d3a8f0e13b`
(Sepolia block 12182892, gasUsed 204,600); bridged 0.048 ETH
Sepolia → Base Sepolia via the Optimism Standard Bridge
`0xc6dac952d874c3607f605c58f968815ed217a418d5789ab113ff114aeefe6260`
(Sepolia block 12183026, gasUsed 534,353; landed on Base Sepolia as
48,000,000,000,000,000 wei). Deployer:
`0xc92Ba015a2b5Cf53D3BDe3D3b074616F43fCc0c7` (fresh testnet-only key).

Breaker parameters: window 60 s, threshold **0.005 ETH**
(5,000,000,000,000,000 wei). Demo amounts are scaled to that budget
(deposit 0.005 ETH, prior/normal withdrawal 0.0005 ETH, burst
withdrawal 0.002 ETH ×3 = 0.0065 ETH total ≥ 0.005 threshold).

## Demo run #2 — legitimate burst (RECORDED, clean full loop)

Video: `video/reactive-circuit-breaker-demo.mp4` — 149.4 s, 1280×720,
H.264, 10 fps, 1,638,738 bytes, sha256
`d3ebae3d09114670340b1c19da60ce381289f55a67992ee75a8e5e0475ce44e7`.
Recorded live with `script -T` (`docs/demo-recorded.typescript` +
`docs/demo-recorded.timing`); rendered verbatim with
`docs/render-demo-video.py` (idle gaps capped at 12 s).

Users: `0x6E5A31D4e1616eb48a8E8A718306bdd4e64A752c`,
`0x7BaBA4d66527235ce35c4170A8e8881B769208Db`,
`0x61771ED4702fe69bcE3B93b07D0D2e5B4290A233`.

| Step | Tx / evidence |
|---|---|
| Fund users (0.0051 ETH gas each) | `0x6296abeff1eec1627c3a1794db52aae7a52b9ce39d343224d1715659c683e8bb` (61790138) · `0x3a4356763c08e3ec0611e35998350704e4b27d3eaf28ee7213548c6e697ff1c3` (61790157) · `0xfd785a1b193e68918f0b43ed6aecfa14db299a4928c32f414c72b51d9484987d` (61790173) |
| Deposits (0.005 ETH each) | `0xa1365bbf12212bb4d6f70d86c34fcb165227df8e118ff9c803997874466cf87c` (61790192) · `0x433d266be9949296e832ac34e9c752c87ea3171ff04946e085b02fa98fba6e65` (61790223) · `0x206e8efdae13c6aacd7225f5034773c078c2231b2d7345087e4d47eb38fd5d71` (61790257) |
| Prior withdrawals (0.0005 ETH each, known-sender history) | `0x9c61f6d9718e22cfdbc96a1946668757279897f9cabfce72330632aba45ef711` (61790207) · `0x42be4d62245f19c30372a39290981d96c766cc373492c04657bb701df6f3c2d8` (61790238) · `0xacb2ba5a16cc2e0df44bef68e18f51effbac00f8caaa80b016c201a6e121290e` (61790271) |
| Normal withdrawal 0.0005 ETH (passes, no flag) | `0xc03f897cd29420df4020ba936db7d4e7b2564dc41e98f35a585ad9043e5ae514` (block 61790665, gasUsed 38,095); `flagged() = false` |
| Burst w/d 1: 0.002 ETH user 1 | `0x2473d0d57bcab6dd3cca4a130c7384c17738f3230095a7be513b0ecc3b76a02f` (block 61790724, gasUsed 38,083) |
| Burst w/d 2: 0.002 ETH user 2 | `0x40facdfaf849115c050c9c453b91f1758e10ed6619b53a6b9556972d5ebed1fc` (block 61790866, gasUsed 38,083) |
| Burst w/d 3: 0.002 ETH user 3 | `0x8e07f8a0a7bdf1e8ba23ade136948422d469d2df3163ce2f27be9e8ffd505d82` (block 61791010, gasUsed 38,083) |
| Reactive tx on Lasna (`react()` + `BurstFlagged` #2) | `0x4afbf412b0b7612e8bbb15b43b36c86d376f0c526b7dfc3e3049b37cd006588f` (block 8907683, gasUsed 240,571); volume 6,000,000,000,000,000 wei (0.006 ETH) |
| Callback tx on Base Sepolia (`pauseViaCallback`) | `0xbfa0f0a9e3e1f4c1db4c48faf7c853c04fc49be5032411badc23e639f7f0026c` (block 61791016, gasUsed 87,517); `PausedByBreaker` burst #2, 6 blocks after burst w/d 3 |
| 4th withdrawal reverts while paused | No tx — reverted at gas estimation: `execution reverted, data: 0x9e87fac8: Paused` (see `demo-logs/wd4-blocked.json`) |
| AI verdict tx (`submitVerdict` LEGITIMATE) | `0x26b28a71c1cf25d08c04774101aa2b2e42209508c538f657d0b3085e4034af9c` (block 61791216, gasUsed 172,131); verdict LEGITIMATE via **Groq `openai/gpt-oss-20b`**: "69s span and no single sender exceeds 80% of volume." Features: 4 withdrawals, 3 senders, total 0.0065 ETH, max single 0.002 ETH, dominant share 0.30, span 69 s |
| Breaker re-armed (`clearFlag()`) | `0x794adc190a6d20631be9f7b18f12dd667b6fd30d1429ea46f03f95695840bf67` (Lasna block 8907726, gasUsed 24,872) |
| Withdrawal resumes after unpause | `0x0a3b854a29b2a092b23c85c08815dc3b354a7e681d4179a7168f48f5bb624084` (block 61791306, gasUsed 38,095); `paused() = false`, `flagged() = false` |

Final on-chain state (verified after run #2): Vault `paused() = false`,
Breaker `flagged() = false`, `verdicts(1) = LEGITIMATE`,
`verdicts(2) = LEGITIMATE`.

## Demo run #1 — legitimate burst (reactive path proved; agent crashed)

Same contracts, same flow. The reactive path worked (pause within 10 s
of burst w/d 3, 4th withdrawal reverted), but the agent crashed before
posting its verdict: `eth_getLogs is limited to a 200 range` — the
Base Sepolia RPC caps log queries at 200 blocks and the agent's
withdrawal scan spanned ~2,300 blocks. Fixed in `agent/index.mjs`
(chunked ≤200-block scans; one wide query split by timestamp; skip
bursts that already have an on-chain verdict). State was reset with a
manual verdict and run #2 re-ran the full loop with the agent.

Users: `0x0508b4A517f97c4C9Ce03D4B2543bE88C9b7B293`,
`0xA1dEd1B3fEf5A013362044BB468E2d732Ea55F50`,
`0x43b5Ca33396b55B4e6ae1D339E021B9Cf37E5860`.

| Step | Tx / evidence |
|---|---|
| Fund / deposit / prior (0.0052 / 0.005 / 0.0005 ETH) | funds `0x1abf97ad079e4cceaf032060060ba4571b6bff506102d0c449741016663f162d` (61788082) · `0x2d620a5bc8b51144314d2e75963b89150bf25877125cdf7c544640fb1e401da2` (61788100) · `0xb3abbc328597b0c97abbf8a0e663d03949602d53c892e417056cbcf923bf3d18` (61788119); deposits `0x55309d64df3c1b032b64e3abfb8c3df9782ac86be1adb58e36f6ac6a4e64c47f` (61788134) · `0x98d685e62eac2eea554a7bb79bce0b416dccd746ed5833faf7528e1581e829b4` (61788164) · `0xc9319f88e62e340140e7ad3310101d641ebee75d8ebd891b6882b3994d20f818` (61788197); priors `0xd7948fd41e413733672108389881edb6b924e4195af80289b3ec724e8f9a3d6f` (61788149) · `0x1525aa0a4b22762ebb6ff0756a08aab2bf0c86215796ff45468b672bdbf14d3c` (61788182) · `0x063b14e4b8d25feb70874dbfce8f45abc350aa564ea105b892d0bf487c9f21af` (61788214) |
| Normal withdrawal 0.0005 ETH | `0x61a84a07a851c341b1a6baf0b4e0475f2dbfbaf0da6caab4e8526c0f7115d4c3`; `flagged() = false` |
| Burst w/d 1–3 (0.002 ETH each) | `0x2c48f2b02e807c69393a60833386b1aba0dfb75d9b3b60fdff73312947ed04b8` · `0xf2cad77b86a25b2601fe50c4383ea44e557703e2e811853f8bc651825dfdaa42` · `0xb90cb16f420df19327b28d7635cb7bbac2c8935c23a30489387bd332370a3932` (block 61788958) |
| Reactive tx on Lasna (`BurstFlagged` #1) | `0x9e266a4e40d05b4fe019ce69168611bdebb74d9763937b34ee858907950a49e5` (block 8907294, gasUsed 280,200); volume 0.006 ETH |
| Callback tx (`pauseViaCallback`) | `0xbc3dc6d4595a39781065c9bfa8710c598d864b11162d59a3f670236f4fdebdec` (block 61788966, gasUsed 87,517) |
| 4th withdrawal reverts while paused | No tx — reverted: `execution reverted, data: 0x9e87fac8: Paused` (see `demo-logs-run1/wd4-blocked.json`) |
| Agent crashed (RPC log-range limit) | `Error: eth_getLogs: {"code":-32614,"message":"eth_getLogs is limited to a 200 range"}` — see `docs/demo-recorded-run1.typescript` |
| Manual reset verdict (LEGITIMATE) | `0x5f65d602573d75f09daacb5829beef1f0bb34d65f60c2b8d8f83aa17080ec08a` (block 62014653, gasUsed 263,688). Reason: "legitimate burst: 3 known senders, 55s span, spread amounts; agent run crashed on RPC eth_getLogs 200-block limit before posting, verdict posted manually to reset demo state" |
| Manual re-arm (`clearFlag()`) | `0xb859ee47c84036a3c4c7f3783aaed9b3c77f64ef831a84135198bdb5f31a6fdb` (Lasna block 8908243, gasUsed 24,872) |

Run #1 evidence is archived in `demo-logs-run1/` +
`demo-txlog-run1.txt` + `docs/demo-recorded-run1.typescript`.

## Demo run 2 (attack burst) — NOT RUN

The attack-burst flow (1 fresh sender, 3 fast withdrawals →
`ATTACK_LIKE` → vault stays paused) was designed but not executed: the
deployer holds ~0.00008 Base Sepolia ETH after run #2, and a second
attack run needs ~0.015 ETH of fresh user funding. It is a follow-up,
not a blocker: the legitimate-burst loop (the event's core flow) is
fully proven live, and the classifier rules for ATTACK_LIKE were
verified offline (Groq: 1-sender/3 s burst → `ATTACK_LIKE`).

## Honest caveats

- Run #2's agent features line shows `nFreshSenders: 3` — the
  prior-history query in the recorded run missed the setup priors (its
  range ended ~1,000 blocks too early). The verdict itself was driven
  by the 69 s span and the spread (max single-sender share 0.38) and is
  correct; the query is fixed in the current `agent/index.mjs` (one
  wide chunked query, split by timestamp — validated read-only on
  burst #2: all 3 senders recognised as known, `nFreshSenders: 0`).
  The fix landed after the recorded run, so the video still shows the
  old features line.
- The recorded video contains a raw JSON dump (the agent's `cast send`
  receipt, ~15 s) after the `submitVerdict: ok=true` line. The verdict
  line itself is readable; the agent now logs a one-line receipt
  summary instead (fix in current `agent/index.mjs`).
- The breaker's `windowVolumeWei` at trip time was 0.006 ETH, not the
  0.0065 ETH total of the 4 withdrawals — the normal withdrawal (0.0005
  ETH) aged out of the 60 s window by the time the third burst
  withdrawal's `react()` executed (Lasna/Base Sepolia clock skew of a
  few seconds). The trip still fired exactly at burst withdrawal #3, as
  designed (volume at w/d 2 = 0.0045 < 0.005; at w/d 3 = 0.006 ≥ 0.005).

## Status 21 Nov 2026 ~17:00 WIB

DEPLOYED + DEMOED LIVE. Contracts on Base Sepolia + Lasna, demo run #2
complete end-to-end (pause → Groq LEGITIMATE verdict → unpause →
resume). Video rendered and verified (ffprobe + frame checks). Ready
for repo + DoraHacks Build submit.
