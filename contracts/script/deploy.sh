#!/usr/bin/env bash
# Deploy the Reactive Circuit-Breaker — TESTNET ONLY.
#   Base Sepolia (84532): Vault + VerdictOracle
#   Reactive Lasna (5318007): CircuitBreaker
#
# The deployer key is NEVER in this repo. It is read from
#   $DEPLOYER_KEY_FILE (default ~/.dorahacks-testnet/deployer.json,
#   the cast-wallet JSON created for this project) or $PRIVATE_KEY.
# Funding (verified 2026-11-21): deployer holds 0.048 Base Sepolia ETH
#   (bridged from Sepolia by the user). Amounts below are scaled to that
#   budget: swap 0.012 ETH -> 1.2 lREACT; callback reserve 0.005 ETH;
#   breaker threshold 0.005 ETH (demo burst 0.006 ETH trips it).
# The CircuitBreaker is deployed with `cast send --create` (NOT forge
# script): its constructor path calls SYSTEM.subscribe via a precompile
# that reverts under forge's local simulation. subscribe() is therefore
# a separate owner call (step 4).
# Every step saves its receipt JSON to ../deploy-logs/ and the final
# python block writes ../deploy-results.json (tx hash + block + gasUsed
# per step) and ../deployments.json.
set -euo pipefail
# Script lives at contracts/script/deploy.sh; the Foundry project root is
# its parent (contracts/).
cd "$(dirname "$0")/.."

BASE_RPC="${BASE_SEPOLIA_RPC:-https://sepolia.base.org}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
KEY_FILE="${DEPLOYER_KEY_FILE:-$HOME/.dorahacks-testnet/deployer.json}"
if [ -z "${PRIVATE_KEY:-}" ]; then
  PRIVATE_KEY="$(python3 -c "import json;d=json.load(open('$KEY_FILE'));print((d['data'][0] if isinstance(d.get('data'),list) else d)['private_key'])")"
fi
export PATH="$HOME/.foundry/bin:$PATH"

DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "deployer: $DEPLOYER"
echo "Base Sepolia balance: $(cast balance "$DEPLOYER" --rpc-url "$BASE_RPC") wei"
echo "Lasna balance:        $(cast balance "$DEPLOYER" --rpc-url "$LASNA_RPC") wei"

OUT="../deployments.json"
RESULTS="../deploy-results.json"
[ -f "$OUT" ] && cp "$OUT" "$OUT.bak"
mkdir -p ../deploy-logs

# txhash extractor: prints transactionHash from a cast/forge JSON file
txh() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('transactionHash') or '')" "$1"; }
# receipt saver: cast receipt --json for a tx hash (waits for the receipt)
receipt() { cast receipt "$1" --rpc-url "$2" --json > "$3" 2>/dev/null || echo "WARN: receipt fetch failed for $1"; }

# ---- step 0: lREACT (only if the deployer holds no lREACT) ----
LASNA_BAL="$(cast balance "$DEPLOYER" --rpc-url "$LASNA_RPC")"
if [ "$LASNA_BAL" = "0" ]; then
  echo "--- step 0: swapping 0.012 Base Sepolia ETH -> 1.2 lREACT via the Reactive faucet ---"
  cast send --json --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" \
    0x2afaFD298b23b62760711756088F75B7409f5967 --value 0.012ether > ../deploy-logs/step0-faucet.json
  echo "faucet tx: $(txh ../deploy-logs/step0-faucet.json)"
  echo "polling Lasna balance (up to ~10 min, the faucet mints cross-chain)..."
  for i in $(seq 1 30); do
    sleep 20
    LASNA_BAL="$(cast balance "$DEPLOYER" --rpc-url "$LASNA_RPC")"
    echo "  poll $i: Lasna balance = $LASNA_BAL wei"
    if [ "$LASNA_BAL" != "0" ]; then break; fi
  done
  if [ "$LASNA_BAL" = "0" ]; then echo "ERROR: lREACT did not land after 10 min"; exit 1; fi
fi

# ---- step 1: Vault + VerdictOracle on Base Sepolia ----
# NOTE: forge create REQUIRES --broadcast (without it, it only dry-runs
# and prints no deployed address). --json must come BEFORE --constructor-args.
# Resume-safe: if a previous run already deployed them, reuse the addresses
# from the saved logs instead of redeploying.
echo "--- step 1: Vault (Base Sepolia) ---"
if [ -f ../deploy-logs/step1-vault.json ]; then
  VAULT="$(python3 -c "import json;d=json.load(open('../deploy-logs/step1-vault.json'));print(d.get('deployedTo') or '')")"
  VAULT_TX="$(txh ../deploy-logs/step1-vault.json)"
  echo "reusing VAULT=$VAULT tx=$VAULT_TX (from previous run)"
else
forge create --broadcast --json --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" \
  src/Vault.sol:Vault --constructor-args 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 \
  > ../deploy-logs/step1-vault.json
VAULT="$(python3 -c "import json;d=json.load(open('../deploy-logs/step1-vault.json'));print(d.get('deployedTo') or '')")"
VAULT_TX="$(txh ../deploy-logs/step1-vault.json)"
echo "VAULT=$VAULT tx=$VAULT_TX"
receipt "$VAULT_TX" "$BASE_RPC" ../deploy-logs/step1-vault-receipt.json
fi

echo "--- step 1b: VerdictOracle (Base Sepolia, agent=$DEPLOYER) ---"
if [ -f ../deploy-logs/step1b-oracle.json ]; then
  ORACLE="$(python3 -c "import json;d=json.load(open('../deploy-logs/step1b-oracle.json'));print(d.get('deployedTo') or '')")"
  ORACLE_TX="$(txh ../deploy-logs/step1b-oracle.json)"
  echo "reusing ORACLE=$ORACLE tx=$ORACLE_TX (from previous run)"
else
forge create --broadcast --json --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" \
  src/VerdictOracle.sol:VerdictOracle --constructor-args "$VAULT" "$DEPLOYER" \
  > ../deploy-logs/step1b-oracle.json
ORACLE="$(python3 -c "import json;d=json.load(open('../deploy-logs/step1b-oracle.json'));print(d.get('deployedTo') or '')")"
ORACLE_TX="$(txh ../deploy-logs/step1b-oracle.json)"
echo "ORACLE=$ORACLE tx=$ORACLE_TX"
receipt "$ORACLE_TX" "$BASE_RPC" ../deploy-logs/step1b-oracle-receipt.json
fi

# ---- step 2: CircuitBreaker on Lasna via cast --create ----
# Threshold 0.005 ETH (5000000000000000 wei), window 60s — demo burst
# (0.0005 normal + 0.002 x3 = 0.0065 ETH) trips it at the 3rd burst w/d.
echo "--- step 2: CircuitBreaker (Lasna) ---"
forge build -q
BIN="$(python3 -c "import json;print(json.load(open('out/CircuitBreaker.sol/CircuitBreaker.json'))['bytecode']['object'])")"
ARGS="$(cast abi-encode "constructor(address,uint256,uint256)" "$VAULT" 60 5000000000000000)"
# NOTE: the compiled bytecode object already starts with "0x", and
# cast abi-encode also returns a 0x-prefixed string — so the init code is
# BIN + ARGS-without-its-0x (a literal "0x${BIN}${ARGS}" would be "0x0x…"
# and cast rejects it).
cast send --json --rpc-url "$LASNA_RPC" --private-key "$PRIVATE_KEY" --create "${BIN}${ARGS:2}" \
  > ../deploy-logs/step2-breaker.json
BREAKER="$(python3 -c "import json;d=json.load(open('../deploy-logs/step2-breaker.json'));print(d.get('contractAddress') or '')")"
if [ -z "$BREAKER" ]; then echo "ERROR: no contractAddress in create receipt"; cat ../deploy-logs/step2-breaker.json; exit 1; fi
echo "BREAKER=$BREAKER tx=$(txh ../deploy-logs/step2-breaker.json)"

# ---- step 3: wire Vault <-> Breaker <-> Oracle (Base Sepolia) ----
echo "--- step 3: wiring ---"
cast send --json --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" "$VAULT" \
  "setCircuitBreaker(address)" "$BREAKER" > ../deploy-logs/step3a-wire-breaker.json
echo "setCircuitBreaker tx: $(txh ../deploy-logs/step3a-wire-breaker.json)"
cast send --json --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" "$VAULT" \
  "setVerdictOracle(address)" "$ORACLE" > ../deploy-logs/step3b-wire-oracle.json
echo "setVerdictOracle tx: $(txh ../deploy-logs/step3b-wire-oracle.json)"

# ---- step 4: subscribe the breaker to Vault.Withdrawal ----
echo "--- step 4: subscribe() on Lasna ---"
cast send --json --rpc-url "$LASNA_RPC" --private-key "$PRIVATE_KEY" "$BREAKER" "subscribe()" \
  > ../deploy-logs/step4-subscribe.json
echo "subscribe tx: $(txh ../deploy-logs/step4-subscribe.json)"

# ---- step 5: fund fee reserves via depositTo (docs: direct transfers do NOT create reserves) ----
echo "--- step 5: funding reserves ---"
cast send --json --rpc-url "$LASNA_RPC" --private-key "$PRIVATE_KEY" \
  0x8888888888888888888888888888888888888888 "depositTo(address)" "$BREAKER" --value 0.5ether \
  > ../deploy-logs/step5a-reserve-lasna.json
echo "breaker reserve (0.5 lREACT) tx: $(txh ../deploy-logs/step5a-reserve-lasna.json)"
cast send --json --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" \
  0x476F44b11F5C942c58f4c8E3d0300E5710743585 "depositTo(address)" "$VAULT" --value 0.005ether \
  > ../deploy-logs/step5b-reserve-base.json
echo "vault callback reserve (0.005 ETH) tx: $(txh ../deploy-logs/step5b-reserve-base.json)"

# ---- results: deploy-results.json + deployments.json ----
python3 - "$VAULT" "$ORACLE" "$BREAKER" "$DEPLOYER" <<'EOF'
import json, sys, glob, os
vault, oracle, breaker, deployer = sys.argv[1:5]

def load(p):
    try:
        return json.load(open(p))
    except Exception:
        return {}

def rec(step, files):
    d = {}
    for f in files:
        d.update(load(f))
    out = {"step": step}
    for k in ("transactionHash", "blockNumber", "gasUsed", "contractAddress", "deployedTo", "status"):
        if k in d and d[k] is not None:
            v = d[k]
            # hex ints -> decimal for readability
            if k in ("blockNumber", "gasUsed") and isinstance(v, str) and v.startswith("0x"):
                try:
                    v = int(v, 16)
                except Exception:
                    pass
            out[k] = v
    return out

steps = [
    rec("0-faucet-swap-0.012ETH-to-lREACT", ["../deploy-logs/step0-faucet.json"]),
    rec("1-vault-deploy", ["../deploy-logs/step1-vault.json", "../deploy-logs/step1-vault-receipt.json"]),
    rec("1b-oracle-deploy", ["../deploy-logs/step1b-oracle.json", "../deploy-logs/step1b-oracle-receipt.json"]),
    rec("2-breaker-deploy-lasna", ["../deploy-logs/step2-breaker.json"]),
    rec("3a-wire-setCircuitBreaker", ["../deploy-logs/step3a-wire-breaker.json"]),
    rec("3b-wire-setVerdictOracle", ["../deploy-logs/step3b-wire-oracle.json"]),
    rec("4-subscribe", ["../deploy-logs/step4-subscribe.json"]),
    rec("5a-reserve-breaker-0.5-lREACT", ["../deploy-logs/step5a-reserve-lasna.json"]),
    rec("5b-reserve-vault-callback-0.005-ETH", ["../deploy-logs/step5b-reserve-base.json"]),
]
results = {
    "network": "testnet-only",
    "deployer": deployer,
    "baseSepolia": {"chainId": 84532, "vault": vault, "verdictOracle": oracle},
    "lasna": {"chainId": 5318007, "circuitBreaker": breaker},
    "steps": steps,
}
json.dump(results, open("../deploy-results.json", "w"), indent=2)
json.dump({"network": "testnet-only", "deployer": deployer,
  "baseSepolia": {"chainId": 84532, "rpc": "https://sepolia.base.org",
    "vault": vault, "verdictOracle": oracle},
  "lasna": {"chainId": 5318007, "rpc": "https://lasna-rpc.rnk.dev/",
    "circuitBreaker": breaker}},
  open("../deployments.json", "w"), indent=2)
print("wrote ../deploy-results.json and ../deployments.json")
EOF
echo "DONE. Vault=$VAULT Oracle=$ORACLE Breaker=$BREAKER"
