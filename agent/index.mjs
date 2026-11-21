// index.mjs — AI verdict agent for the Reactive Circuit-Breaker.
//
// Loop: poll BurstFlagged events on Reactive Lasna -> gather the burst's
// Withdrawal events + each sender's prior history on Base Sepolia ->
// classify with Groq (or the transparent heuristic fallback) ->
// submitVerdict() on VerdictOracle (Base Sepolia). LEGITIMATE unpauses the
// vault on-chain; then clearFlag() re-arms the breaker on Lasna.
//
// TESTNET ONLY. No mainnet anywhere in this file.
// Key handling: the agent key is read from AGENT_KEY_FILE (the cast-wallet
// JSON created for this project) or PRIVATE_KEY env. It is never printed,
// never written to disk by this agent, and only passed to `cast send` as a
// subprocess argument for the verdict/clearFlag transactions.
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { classifyBurst } from "./verdict.mjs";

const BASE_RPC = process.env.BASE_SEPOLIA_RPC ?? "https://sepolia.base.org";
const LASNA_RPC = process.env.LASNA_RPC ?? "https://lasna-rpc.rnk.dev/";
const BREAKER = process.env.BREAKER_ADDRESS ?? "";
const ORACLE = process.env.ORACLE_ADDRESS ?? "";
const VAULT = process.env.VAULT_ADDRESS ?? "";
const STATE_FILE = new URL("./state.json", import.meta.url).pathname;
const CAST = "/home/hatch/.foundry/bin/cast";

const BURST_TOPIC =
  "0xf0d69c6e3b1efb8e9e9d2eb7cc0de5594e2b0bc30063c423047a4d47991e1754"; // BurstFlagged(uint256,address,uint256,uint256,uint256)
const WITHDRAWAL_TOPIC =
  "0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65"; // Withdrawal(address,uint256)

function log(...a) {
  console.log(new Date().toISOString(), ...a);
}

function loadState() {
  try {
    return JSON.parse(readFileSync(STATE_FILE, "utf8"));
  } catch {
    return { lastLasnaBlock: null, doneBursts: [] };
  }
}
function saveState(s) {
  writeFileSync(STATE_FILE, JSON.stringify(s, null, 2));
}

async function rpc(url, method, params = []) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const j = await res.json();
  if (j.error) throw new Error(`${method}: ${JSON.stringify(j.error)}`);
  return j.result;
}

const hex = (n) => "0x" + BigInt(n).toString(16);
const toBig = (h) => BigInt(h);
const addrFromTopic = (t) => "0x" + t.slice(26).toLowerCase();

async function getLogs(url, address, topics, fromBlock, toBlock) {
  return rpc(url, "eth_getLogs", [
    { address, topics, fromBlock: hex(fromBlock), toBlock: hex(toBlock) },
  ]);
}

// eth_getLogs range caps differ per RPC (sepolia.base.org caps at 200
// blocks; Lasna allows more). Chunk every log scan to <=200 blocks so the
// same code works on both chains.
async function getLogsChunked(url, address, topics, fromBlock, toBlock) {
  const CHUNK = 200;
  const out = [];
  for (let start = fromBlock; start <= toBlock; start += CHUNK) {
    const end = Math.min(toBlock, start + CHUNK - 1);
    const logs = await getLogs(url, address, topics, start, end);
    out.push(...logs);
  }
  return out;
}

function decodeBurstFlagged(logEntry) {
  const data = logEntry.data.slice(2);
  const words = [0, 1, 2].map((i) => BigInt("0x" + data.slice(i * 64, (i + 1) * 64)));
  return {
    burstId: Number(toBig(logEntry.topics[1])),
    lastUser: addrFromTopic(logEntry.topics[2]),
    lastAmountWei: words[0].toString(),
    windowVolumeWei: words[1].toString(),
    timestamp: Number(words[2]),
    blockNumber: Number(toBig(logEntry.blockNumber)),
    txHash: logEntry.transactionHash,
  };
}

function decodeWithdrawal(logEntry) {
  return {
    user: addrFromTopic(logEntry.topics[1]),
    amountWei: toBig(logEntry.data).toString(),
    timestamp: 0, // filled from block timestamp below
    blockNumber: Number(toBig(logEntry.blockNumber)),
    txHash: logEntry.transactionHash,
  };
}

async function blockTimestamp(url, blockNumber) {
  const b = await rpc(url, "eth_getBlockByNumber", [hex(blockNumber), false]);
  return Number(toBig(b.timestamp));
}

function agentKey() {
  if (process.env.AGENT_KEY_FILE) {
    const j = JSON.parse(readFileSync(process.env.AGENT_KEY_FILE, "utf8"));
    const data = Array.isArray(j.data) ? j.data[0] : j;
    return data.private_key;
  }
  if (process.env.PRIVATE_KEY) return process.env.PRIVATE_KEY;
  throw new Error("no agent key: set AGENT_KEY_FILE or PRIVATE_KEY");
}

function castSend(rpcUrl, to, sig, args, key) {
  const r = spawnSync(
    CAST,
    ["send", "--rpc-url", rpcUrl, "--private-key", key, to, sig, ...args],
    { encoding: "utf8", timeout: 180_000 },
  );
  return { ok: r.status === 0, out: (r.stdout ?? "") + (r.stderr ?? "") };
}

// One-line summary of a `cast send --json` output for the terminal log.
// (The raw receipt JSON is pages of hex — it buried the verdict lines in
// the recorded demo video. The full receipt is still in the tx itself.)
function summarizeCastOut(out) {
  try {
    const d = JSON.parse(out);
    if (d.transactionHash) {
      return `tx ${d.transactionHash} block ${d.blockNumber} gasUsed ${d.gasUsed} status ${d.status}`;
    }
    if (d.errors) return `error: ${String(d.errors[0]?.message ?? "unknown").slice(0, 160)}`;
    return out.slice(0, 200);
  } catch {
    return out.slice(0, 200);
  }
}

async function handleBurst(burst, state) {
  log(`burst #${burst.burstId} flagged: volume ${burst.windowVolumeWei} wei, tx ${burst.txHash}`);
  // 0. Skip if a verdict is already on-chain for this burst (idempotent:
  //    re-runs and manual resets must not re-submit and hit AlreadyVerdicted).
  const vData = await rpc(BASE_RPC, "eth_call", [
    { to: ORACLE, data: "0x3e0204fe" + hex(burst.burstId).slice(2).padStart(64, "0") }, // verdicts(uint256)
    "latest",
  ]).catch(() => "0x");
  const existing = vData && vData !== "0x" ? Number("0x" + vData.slice(2, 66)) : 0;
  if (existing !== 0) {
    log(`burst #${burst.burstId}: verdict already on-chain (${existing === 1 ? "LEGITIMATE" : "ATTACK_LIKE"}), skipping`);
    return true;
  }
  const burstTs = burst.timestamp;
  // Base Sepolia block range from the BURST TIMESTAMP — NOT the Lasna block
  // number (the two chains have unrelated heights; using the Lasna height
  // would query 2023-era Base Sepolia blocks and find nothing). Base
  // Sepolia runs ~8 blocks/s, so 120s ~= 1000 blocks; add a wide margin.
  const latest = Number(
    toBig(await rpc(BASE_RPC, "eth_blockNumber", [])),
  );
  const latestBlock = await rpc(BASE_RPC, "eth_getBlockByNumber", [
    hex(latest),
    false,
  ]);
  const latestTs = Number(toBig(latestBlock.timestamp));
  const toBlock = latest;
  let fromBlock = Math.max(
    0,
    latest - Math.ceil((latestTs - (burstTs - 120)) * 10) - 500,
  );
  if (fromBlock > latest) fromBlock = Math.max(0, latest - 500);
  // 1+2. Withdrawals: ONE wide chunked query, split by timestamp.
  //    (A separate "prior" query ending at fromBlock misses setup priors
  //    that fall between fromBlock and the burst — the fromBlock estimate
  //    lands ~1000 blocks early at ~8 blocks/s. Verified read-only on
  //    burst #2: the wide query finds all 3 setup priors, nFreshSenders 0.)
  const wide = await getLogsChunked(
    BASE_RPC, VAULT, [WITHDRAWAL_TOPIC], Math.max(0, fromBlock - 5000), toBlock,
  );
  const withdrawals = [];
  const priorCounts = {};
  for (const l of wide) {
    const w = decodeWithdrawal(l);
    w.timestamp = await blockTimestamp(BASE_RPC, w.blockNumber);
    if (w.timestamp >= burstTs - 120 && w.timestamp <= burstTs + 5) {
      withdrawals.push(w);
    } else if (w.timestamp < burstTs - 120) {
      const u = w.user.toLowerCase();
      priorCounts[u] = (priorCounts[u] ?? 0) + 1;
    }
  }
  // 3. Breaker threshold (for the heuristic's 2x rule).
  const thr = await rpc(LASNA_RPC, "eth_call", [
    { to: BREAKER, data: "0x42cde4e8" }, // threshold() — verified with cast sig
    "latest",
  ]).catch(() => "0x0");
  const thresholdWei = thr && thr !== "0x" ? toBig(thr).toString() : "0";

  // 4. Classify.
  const verdict = await classifyBurst(
    { ...burst, withdrawals, priorCounts },
    thresholdWei,
  );
  log(
    `burst #${burst.burstId}: ${verdict.verdict} via ${verdict.model} — ${verdict.reason}`,
  );
  log(`  features: ${JSON.stringify(verdict.features)}`);

  // 5. Post the verdict on-chain.
  const key = agentKey();
  const vNum = verdict.verdict === "LEGITIMATE" ? "1" : "2";
  const r = castSend(
    BASE_RPC, ORACLE, "submitVerdict(uint256,uint8,string)",
    [String(burst.burstId), vNum, verdict.reason], key,
  );
  log(`submitVerdict: ok=${r.ok} ${summarizeCastOut(r.out)}`);
  if (!r.ok) return false;

  // 6. Re-arm the breaker after a LEGITIMATE verdict.
  if (verdict.verdict === "LEGITIMATE") {
    const c = castSend(LASNA_RPC, BREAKER, "clearFlag()", [], key);
    log(`clearFlag on Lasna: ok=${c.ok} ${summarizeCastOut(c.out)}`);
  }
  state.doneBursts.push(burst.burstId);
  saveState(state);
  return true;
}

async function once() {
  if (!BREAKER || !ORACLE || !VAULT) {
    throw new Error("set BREAKER_ADDRESS, ORACLE_ADDRESS, VAULT_ADDRESS");
  }
  const state = loadState();
  const latest = Number(toBig(await rpc(LASNA_RPC, "eth_blockNumber", [])));
  const from = state.lastLasnaBlock ?? Math.max(0, latest - 2000);
  const logs = await getLogsChunked(LASNA_RPC, BREAKER, [BURST_TOPIC], from, latest);
  log(`scanning Lasna blocks ${from}..${latest}: ${logs.length} BurstFlagged`);
  for (const l of logs) {
    const burst = decodeBurstFlagged(l);
    if (state.doneBursts.includes(burst.burstId)) continue;
    await handleBurst(burst, state);
  }
  state.lastLasnaBlock = latest;
  saveState(state);
}

async function main() {
  const runOnce = process.argv.includes("--once");
  await once();
  if (runOnce) return;
  log("watching (poll every 15s, Ctrl-C to stop)...");
  setInterval(() => once().catch((e) => log("poll error:", e.message)), 15_000);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
