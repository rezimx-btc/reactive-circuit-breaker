# Research notes — Reactive Circuit-Breaker (21 Nov 2026)

All items below were verified from official docs or live RPC on 21 Nov 2026
~19:00 WIB. Anything marked OPEN could not be verified from docs and is
not assumed.

## Reactive Network (Omni v2, current docs — dev.reactive.network)

- **Lasna testnet:** chain ID **5318007**, RPC `https://lasna-rpc.rnk.dev/`,
  explorer `https://lasna.reactscan.net/`, currency lREACT.
  Verified live: `eth_chainId` → `0x512577` (5318007), `eth_blockNumber` OK.
- **System contract (both mainnet + Lasna):** `0x8888888888888888888888888888888888888888`.
  Legacy `0x0000…fffFfF` is deprecated — do NOT use it (old tutorials and
  some 2025-era projects still show it; the current docs mark it legacy).
- **Reactive contract pattern:** inherit the base (here hand-written, see
  below), implement `react(LogRecord) external` guarded by
  `msg.sender == SYSTEM`. `LogRecord` fields: chainId, contractAddress,
  topic0–3, data, blockNumber, opCode, blockHash, txHash, logIndex.
  `data` = ABI-encoded NON-indexed params only; `opCode` = topic count.
  Non-matching logs must fall through silently — reverting as a filter is
  billed anyway (docs: "ReactiveContractReverted").
- **Subscribe:** `SYSTEM.subscribe(chainId, contract, topic0..3)`; wildcard
  for topics is `REACTIVE_IGNORE` =
  `0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad`
  (official subscriptions page). Chain wildcard `0`, contract wildcard
  `address(0)`. At least one criterion must be specific.
- **Callbacks (current v1.0):** `SYSTEM.requestCallbackV_1_0(
  CallbackConfiguration_V_1_0{chainId, recipient, gasLimit, payload})`.
  The first 160 bits of the payload are overwritten with the requesting
  reactive contract's address — payload's first argument MUST be
  `address(0)` placeholder. Minimum callback gas limit **100,000**;
  reactive tx max gas **900,000**.
- **Callback contract auth:** `msg.sender == callback proxy` AND injected
  first arg == authorized reactive contract address (both checks, always).
- **Callback proxies (current docs, origins-and-destinations):**
  Base Sepolia (84532) `0x476F44b11F5C942c58f4c8E3d0300E5710743585`;
  Unichain Sepolia (1301) `0x775c9B990ADe401060B78D0e98684eEf8d2466C1`;
  Ethereum Sepolia `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4`;
  Lasna `0x8888…8888`. (Older community projects show `0x9299…FC4` for
  Unichain Sepolia — that is the LEGACY proxy; current table wins.)
- **Funding:** reactive tx fees draw on reserves in the system contract;
  callback fees are billed to the RECIPIENT on the destination chain in
  that chain's native token. Fund via `depositTo(address)` on the system
  contract (lREACT) / callback proxy (destination ETH). Direct transfers
  do NOT create reserves or clear debt. Read `debt(address)` /
  `reserves(address)` on the same contracts. A contract in debt receives
  nothing. `pay(uint256)` (IPayer) is how the system/proxy settles from a
  contract's own balance; `coverDebt()` settles `debt(address(this))`.
- **lREACT faucet:** send Sepolia ETH to the faucet contract on that chain:
  Base Sepolia `0x2afaFD298b23b62760711756088F75B7409f5967`,
  Ethereum Sepolia `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`.
  Rate **1 ETH → 100 lREACT**, max **5 ETH** per tx (excess is lost).
  Also callable as `request(address)` with value.
- **Deploy gotcha (verified in community runbooks):** `forge script`
  CANNOT deploy a reactive contract whose constructor calls `subscribe`
  — the subscribe precompile reverts in forge's local simulation. Deploy
  with `cast send --create` (constructor runs only on-chain), and keep
  `subscribe()` as a separate owner call. This project follows that shape.
- **CRON events:** legacy system contract emits Cron1/10/100…; not used
  here (the breaker is purely event-driven).
- **Verification:** Sourcify via `forge verify-contract --verifier sourcify
  --chain-id 5318007`.

## Why the Reactive library was NOT imported

`forge install Reactive-Network/reactive-lib` (v0.2.0) completed, but the
install step tripped an execution-risk check on this machine, so the cloned
files were deleted without being read, built, or imported. The contracts
instead implement the minimal documented interfaces by hand
(`ISystemContractMinimal`, `pay()`, `receive()`, LogRecord struct) using
only values copied from the official docs pages above. If the project later
adopts the official library, that is a deliberate decision for the repo
owner — the hand-written surface is ABI-identical for the functions used.

## Base Sepolia

- Chain ID **84532** (`0x14a34`), RPC `https://sepolia.base.org`
  (verified live: `eth_chainId` → `0x14a34`), explorer
  `https://sepolia.basescan.org`, currency Sepolia ETH.
- ~200 ms blocks → windows/cooldowns MUST use timestamps, not block counts.
- Faucets (all need a browser login / account — no programmatic no-auth
  route was found): Coinbase
  `https://www.coinbase.com/faucets/base-ethereum-goerli-faucet`
  (1 claim/24h), Alchemy `https://sepoliafaucet.com/`,
  thirdweb `https://thirdweb.com/base-sepolia-testnet/faucet`.
- OP Stack chain: same EVM semantics as Ethereum; Foundry works unchanged.

## Groq (AI model route)

- Groq exposes an OpenAI-compatible API at `api.groq.com`
  (`/openai/v1/chat/completions`). The registered `custom.groq` connector
  works: `models` lists 11 models incl. `openai/gpt-oss-20b`,
  `openai/gpt-oss-120b`, `qwen/qwen3.8-27b`.
- Verified 21 Nov 2026 with the strict prompt: `openai/gpt-oss-20b`
  classifies a 1-sender/3s burst ATTACK_LIKE and a 3-known-sender/55s
  burst LEGITIMATE, both with one-line reasons.
- Caution found during testing: with a loose prompt the same model
  over-flagged the legitimate burst ("rapid burst in 55s"). The agent
  therefore uses a strict rule-based prompt (attack only on >=80%
  single-sender share OR >=3 withdrawals in <10s by fresh senders;
  otherwise LEGITIMATE; doubt → LEGITIMATE).
- The agent NEVER handles the Groq key directly: it shells out to the
  registered connector helper `custom.groq/bin/groq.py chat`, which
  carries the credential via the connector flow; if `GROQ_API_KEY` is
  set it calls the API directly instead. If both routes fail it falls
  back to a transparent heuristic scorer and labels the verdict
  `model: "heuristic"` — never faked as an LLM verdict.

## OPEN (not verified — do not assume)

1. **Funding:** deployer `0xc92Ba015a2b5Cf53D3BDe3D3b074616F43fCc0c7` holds
   0 Base Sepolia ETH and 0 lREACT (checked 21 Nov ~19:05 WIB). The
   Coinbase faucet needs a browser login; no agent-side claim was
   possible. Deploy + demo loop are BLOCKED on one faucet claim
   (~0.05–0.1 Base Sepolia ETH is enough: deploy ~3 contracts + 0.1 ETH
   → 10 lREACT for Lasna + reserves).
2. **Reactive subscription latency:** docs do not state a firm
   origin→react() delay; demo script waits ~20s and checks on-chain.
   If the callback is slower, increase the wait — the loop is still valid.
3. **Lasna gas price / exact reactive-tx fee:** fee formula is
   `fee = p_base · C · (g_used + K)` (docs); no fixed quote. 0.5 lREACT
   reserves + 0.02 ETH callback reserves are a starting point; check
   `debt()`/`reserves()` after the first demo run.
4. **DoraHacks Reactive Meets AI track brief:** the event page text did
   not include per-track brief sections; the entry follows the design
   (reactive loop + AI verdict drives vault state) and the 4 judging
   criteria as stated in DESIGN.md. If the brief demands anything else,
   adapt before submit.
