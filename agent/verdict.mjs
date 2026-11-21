// verdict.mjs — burst classification behind one interface.
//
// Two scorers, same output shape { verdict, reason, model }:
//   1. Groq LLM (preferred): OpenAI-compatible chat completion.
//      - If GROQ_API_KEY is set, calls https://api.groq.com/openai/v1/chat/completions.
//      - Otherwise tries the registered custom.groq helper
//        (~/workspace/custom-connectors/custom.groq/bin/groq.py), which
//        carries the credential via the connector — the key is NEVER read
//        into this process, never logged, never written to disk.
//      - Model: openai/gpt-oss-20b (verified working 2026-11-20).
//   2. Heuristic scorer (fallback): transparent rule-based points. Used
//      ONLY when no Groq route works, and the verdict is then labelled
//      model:"heuristic" — never presented as an LLM verdict.
//
// Verdicts: "LEGITIMATE" | "ATTACK_LIKE" (matching VerdictOracle.Verdict).
import { spawnSync } from "node:child_process";

export const GROQ_MODEL = "openai/gpt-oss-20b";
const GROQ_HELPER =
  "/home/hatch/workspace/custom-connectors/custom.groq/bin/groq.py";

export function burstFeatures(burst) {
  // burst: { burstId, windowVolumeWei, lastAmountWei, lastUser,
  //          withdrawals: [{ user, amountWei, timestamp }...],
  //          priorCounts: { address: number-of-earlier-withdrawals } }
  const w = burst.withdrawals ?? [];
  const senders = [...new Set(w.map((x) => x.user.toLowerCase()))];
  const total = w.reduce((a, x) => a + BigInt(x.amountWei), 0n);
  const maxSingle = w.reduce(
    (a, x) => (BigInt(x.amountWei) > a ? BigInt(x.amountWei) : a),
    0n,
  );
  const span =
    w.length > 1
      ? Math.max(...w.map((x) => x.timestamp)) -
        Math.min(...w.map((x) => x.timestamp))
      : 0;
  const freshSenders = senders.filter(
    (s) => (burst.priorCounts?.[s.toLowerCase()] ?? 0) === 0,
  );
  const perSender = {};
  for (const x of w) {
    const s = x.user.toLowerCase();
    perSender[s] = (perSender[s] ?? 0n) + BigInt(x.amountWei);
  }
  const maxSender = Object.values(perSender).reduce((a, b) => (b > a ? b : a), 0n);
  return {
    burstId: burst.burstId,
    nWithdrawals: w.length,
    nSenders: senders.length,
    nFreshSenders: freshSenders.length,
    totalWei: total.toString(),
    maxSingleWei: maxSingle.toString(),
    dominantShare:
      total > 0n ? Number((maxSingle * 100n) / total) / 100 : 0,
    dominantSenderShare:
      total > 0n ? Number((maxSender * 100n) / total) / 100 : 0,
    spanSeconds: span,
    windowVolumeWei: burst.windowVolumeWei?.toString?.() ?? "0",
  };
}

/// Transparent heuristic scorer. Points (threshold >= 4 => ATTACK_LIKE):
///   +2  one sender is >= 80% of the burst volume (drain concentration)
///   +2  span < 10s with >= 3 withdrawals (machine-speed burst)
///   +1  per fresh sender (no prior withdrawal history), capped at +2
///   +1  burst volume >= 2x the breaker threshold
///   +1  single withdrawal >= 50% of the burst volume
export function heuristicVerdict(features, thresholdWei) {
  let score = 0;
  const reasons = [];
  if (features.dominantSenderShare >= 0.8) {
    score += 2;
    reasons.push("one sender is >=80% of burst volume");
  }
  if (features.spanSeconds < 10 && features.nWithdrawals >= 3) {
    score += 2;
    reasons.push(`${features.nWithdrawals} withdrawals in ${features.spanSeconds}s`);
  }
  if (features.nFreshSenders > 0) {
    const pts = Math.min(2, features.nFreshSenders);
    score += pts;
    reasons.push(`${features.nFreshSenders} sender(s) with no prior history`);
  }
  if (
    thresholdWei &&
    BigInt(features.windowVolumeWei) >= BigInt(thresholdWei) * 2n
  ) {
    score += 1;
    reasons.push("volume >= 2x threshold");
  }
  if (features.nWithdrawals > 1 && features.dominantShare >= 0.5) {
    score += 1;
    reasons.push("one withdrawal >=50% of burst volume");
  }
  const verdict = score >= 4 ? "ATTACK_LIKE" : "LEGITIMATE";
  const reason =
    (reasons.length ? reasons.join("; ") : "spread across known users, normal pace") +
    ` (heuristic score ${score}/8)`;
  return { verdict, reason, model: "heuristic", score };
}

function groqPrompt(features) {
  return [
    "You are a vault security analyst. Classify this withdrawal burst.",
    "Reply with exactly one line in this format: VERDICT: <LEGITIMATE|ATTACK_LIKE> — <one short reason>",
    `Burst: ${features.nWithdrawals} withdrawals, ${features.nSenders} distinct senders (${features.nFreshSenders} with no prior history), total ${features.totalWei} wei, largest single ${features.maxSingleWei} wei (dominant share ${features.dominantShare}), largest single sender share ${features.dominantSenderShare}, time span ${features.spanSeconds}s.`,
    "Decision rules — apply them strictly:",
    "1. ATTACK_LIKE only if a single sender is >=80% of the volume, OR >=3 withdrawals within 10s by fresh sender(s).",
    "2. Otherwise LEGITIMATE: several known senders with spread amounts, or a span over 30s, is normal user activity — a 55s span is NOT rapid.",
    "3. When in doubt between the two, choose LEGITIMATE.",
  ].join("\n");
}

function parseLlmVerdict(text) {
  const m = String(text ?? "").match(
    /VERDICT:\s*(LEGITIMATE|ATTACK_LIKE)\s*[—\-]\s*(.+)/i,
  );
  if (!m) return null;
  return {
    verdict: m[1].toUpperCase(),
    reason: m[2].trim().slice(0, 200),
    model: `groq:${GROQ_MODEL}`,
  };
}

async function groqViaApi(features) {
  const key = process.env.GROQ_API_KEY;
  if (!key) return null;
  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model: GROQ_MODEL,
      messages: [{ role: "user", content: groqPrompt(features) }],
      max_tokens: 300,
      temperature: 0,
    }),
  });
  if (!res.ok) return null;
  const data = await res.json();
  return parseLlmVerdict(data?.choices?.[0]?.message?.content ?? "");
}

function groqViaHelper(features) {
  // Subprocess the registered connector helper; the credential stays
  // inside the connector flow and is never visible to this process.
  const r = spawnSync(
    "python3",
    [GROQ_HELPER, "chat", "--model", GROQ_MODEL, "--prompt", groqPrompt(features), "--max-tokens", "300"],
    { encoding: "utf8", timeout: 120_000 },
  );
  if (r.status !== 0) return null;
  return parseLlmVerdict(r.stdout ?? "");
}

/// Classify a burst. Tries Groq (API key, then connector helper), falls
/// back to the transparent heuristic — and says so in `model`.
export async function classifyBurst(burst, thresholdWei) {
  const features = burstFeatures(burst);
  const viaApi = await groqViaApi(features).catch(() => null);
  if (viaApi) return { ...viaApi, features };
  const viaHelper = groqViaHelper(features);
  if (viaHelper) return { ...viaHelper, features };
  return { ...heuristicVerdict(features, thresholdWei), features };
}
