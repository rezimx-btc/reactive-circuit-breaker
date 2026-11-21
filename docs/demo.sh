#!/usr/bin/env bash
# Full demo loop — TESTNET ONLY. Run after contracts/script/deploy.sh.
# Amounts scaled to the 0.048 Base Sepolia ETH budget (threshold 0.005 ETH):
#   1. Normal withdrawal (0.0005 ETH) — passes, no flag.
#   2. Legitimate burst: 3 KNOWN senders withdraw 0.002 ETH each, ~25s
#      apart (inside the 60s window; total 0.0005 + 0.002*3 = 0.0065 ETH
#      >= 0.005 threshold) — the reactive breaker pauses the vault
#      mid-burst; a 4th withdrawal reverts.
#   3. AI agent (Groq) classifies LEGITIMATE -> verdict on-chain -> vault
#      auto-unpauses; withdrawals resume.
#   4. (Optional, second run) Attack burst: one FRESH sender drains fast
#      -> ATTACK_LIKE -> vault stays paused for manual review.
# Timing: after setup we wait 75s so the three "prior" withdrawals fall
# out of the 60s window — the trip is then deterministic at burst w/d 3
# (volume at w/d 2 = 0.0045 < 0.005; at w/d 3 = 0.0065 >= 0.005).
# Every tx hash is echoed and saved to ../demo-logs/<slug>.json (full
# receipt) + ../demo-txlog.txt (slug + hash); the final python block
# writes ../demo-results.json. Record the results in docs/demo-results.md.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"
KEY_FILE="${DEPLOYER_KEY_FILE:-$HOME/.dorahacks-testnet/deployer.json}"
PRIVATE_KEY="$(python3 -c "import json;d=json.load(open('$KEY_FILE'));print((d['data'][0] if isinstance(d.get('data'),list) else d)['private_key'])")"
BASE_RPC="${BASE_SEPOLIA_RPC:-https://sepolia.base.org}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"

VAULT="$(python3 -c "import json;print(json.load(open('deployments.json'))['baseSepolia']['vault'])")"
ORACLE="$(python3 -c "import json;print(json.load(open('deployments.json'))['baseSepolia']['verdictOracle'])")"
BREAKER="$(python3 -c "import json;print(json.load(open('deployments.json'))['lasna']['circuitBreaker'])")"
DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "vault=$VAULT oracle=$ORACLE breaker=$BREAKER deployer=$DEPLOYER"

mkdir -p demo-logs
TXLOG="demo-txlog.txt"
: > "$TXLOG"

# send <slug> <rpc> <privkey> <to> [cast-send args...]
# Runs cast send --json, echoes "slug: 0xhash", saves the full receipt
# JSON to demo-logs/<slug>.json, appends "slug hash" to the tx log.
send() {
  local slug="$1" rpc="$2" key="$3"; shift 3
  local j tx
  j="$(cast send --json --rpc-url "$rpc" --private-key "$key" "$@")"
  echo "$j" > "demo-logs/${slug}.json"
  tx="$(echo "$j" | python3 -c "import json,sys;print(json.load(sys.stdin).get('transactionHash',''))")"
  echo "$slug: $tx"
  echo "$slug $tx" >> "$TXLOG"
}
# Same as send() but tolerates a revert (used for the blocked 4th w/d).
# A reverted cast send returns a cast error envelope (valid JSON, no
# transactionHash) — record its message, not an empty hash.
send_may_revert() {
  local slug="$1" rpc="$2" key="$3"; shift 3
  local j tx
  j="$(cast send --json --rpc-url "$rpc" --private-key "$key" "$@" 2>&1 || true)"
  echo "$j" > "demo-logs/${slug}.json"
  tx="$(echo "$j" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('transactionHash') or ('(reverted: '+d['errors'][0]['message'][:70]+')' if d.get('errors') else '(reverted, no tx hash)'))")"
  echo "$slug: $tx"
  echo "$slug $tx" >> "$TXLOG"
}

# Demo wallets: three "known users" (fresh testnet keys, funded by the deployer with 0.0051 ETH each for gas; their vault balances come from deposits).
mkkey() { cast wallet new --json | python3 -c "import json,sys;d=json.load(sys.stdin)['data'][0];print(d['address'],d['private_key'])"; }
read -r U1 U1K <<< "$(mkkey)"; read -r U2 U2K <<< "$(mkkey)"; read -r U3 U3K <<< "$(mkkey)"
echo "users: $U1 $U2 $U3"
for U in $U1 $U2 $U3; do
  send "fund-$U" "$BASE_RPC" "$PRIVATE_KEY" "$U" --value 0.0051ether
done
echo "users funded (0.0051 ETH gas each)"

# Each user deposits 0.005 ETH, then makes one small "prior" withdrawal so
# the AI sees them as known senders with history.
for pair in "$U1 $U1K" "$U2 $U2K" "$U3 $U3K"; do
  set -- $pair
  send "deposit-$1" "$BASE_RPC" "$2" "$VAULT" "deposit()" --value 0.005ether
  send "prior-$1" "$BASE_RPC" "$2" "$VAULT" "withdraw(uint256)" 500000000000000
done
echo "--- setup done: 3 known users, 0.0045 ETH each in vault ---"

# Wait 75s so ALL prior withdrawals age out of the 60s window before the
# burst starts (deterministic trip at burst withdrawal #3).
echo "--- waiting 75s so prior withdrawals leave the 60s window ---"
sleep 75

echo "--- 1. normal withdrawal (0.0005 ETH, user 1) — should pass, no flag ---"
send "normal-wd" "$BASE_RPC" "$U1K" "$VAULT" "withdraw(uint256)" 500000000000000
sleep 5
echo "breaker flagged? $(cast call --rpc-url "$LASNA_RPC" "$BREAKER" "flagged()(bool)")"

echo "--- 2. legitimate burst: 0.002 ETH x3, ~25s apart ---"
send "burst-wd1" "$BASE_RPC" "$U1K" "$VAULT" "withdraw(uint256)" 2000000000000000
sleep 25
send "burst-wd2" "$BASE_RPC" "$U2K" "$VAULT" "withdraw(uint256)" 2000000000000000
sleep 25
send "burst-wd3" "$BASE_RPC" "$U3K" "$VAULT" "withdraw(uint256)" 2000000000000000
echo "waiting for the reactive tx + callback (polling paused, up to ~150s)..."
PAUSED="false"
for i in $(seq 1 15); do
  sleep 10
  PAUSED="$(cast call --rpc-url "$BASE_RPC" "$VAULT" "paused()(bool)")"
  echo "  poll $i: vault paused? $PAUSED"
  if [ "$PAUSED" = "true" ]; then break; fi
done
echo "breaker flagged? $(cast call --rpc-url "$LASNA_RPC" "$BREAKER" "flagged()(bool)")"
echo "vault paused?   $PAUSED"
echo "--- 4th withdrawal while paused — should REVERT ---"
send_may_revert "wd4-blocked" "$BASE_RPC" "$U1K" "$VAULT" "withdraw(uint256)" 500000000000000

echo "--- 3. AI verdict agent (one pass) ---"
# Clean agent state so this run scans fresh (no stale lastLasnaBlock).
rm -f agent/state.json
BREAKER_ADDRESS="$BREAKER" ORACLE_ADDRESS="$ORACLE" VAULT_ADDRESS="$VAULT" \
  AGENT_KEY_FILE="$KEY_FILE" node agent/index.mjs --once

sleep 5
echo "vault paused after verdict? $(cast call --rpc-url "$BASE_RPC" "$VAULT" "paused()(bool)")"
echo "--- withdrawal resumes ---"
send "resume-wd" "$BASE_RPC" "$U1K" "$VAULT" "withdraw(uint256)" 500000000000000
echo "DEMO DONE — results in demo-results.json"

# ---- results file ----
python3 - "$VAULT" "$ORACLE" "$BREAKER" "$U1" "$U2" "$U3" <<'EOF'
import json, sys, glob, os
vault, oracle, breaker, u1, u2, u3 = sys.argv[1:7]
txs = {}
for line in open("demo-txlog.txt"):
    parts = line.split()
    if len(parts) >= 2:
        txs[parts[0]] = parts[1]
receipts = {}
for f in sorted(glob.glob("demo-logs/*.json")):
    slug = os.path.basename(f)[:-5]
    try:
        d = json.load(open(f))
    except Exception:
        continue
    r = {"txHash": d.get("transactionHash")}
    for k in ("blockNumber", "gasUsed", "status"):
        if k in d and d[k] is not None:
            v = d[k]
            if k in ("blockNumber", "gasUsed") and isinstance(v, str) and v.startswith("0x"):
                try:
                    v = int(v, 16)
                except Exception:
                    pass
            r[k] = v
    receipts[slug] = r
out = {
    "network": "testnet-only",
    "vault": vault, "verdictOracle": oracle, "circuitBreaker": breaker,
    "users": [u1, u2, u3],
    "thresholdWei": 5000000000000000, "windowSeconds": 60,
    "amountsWei": {"deposit": 5000000000000000, "priorWithdrawal": 500000000000000,
                   "normalWithdrawal": 500000000000000, "burstWithdrawal": 2000000000000000},
    "txHashes": txs, "receipts": receipts,
}
json.dump(out, open("demo-results.json", "w"), indent=2)
print("wrote demo-results.json")
EOF
