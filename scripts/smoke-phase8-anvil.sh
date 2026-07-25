#!/usr/bin/env bash
set -euo pipefail

workspace="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
protocol="$workspace/protocol"
output="$protocol/deployments/local"
release_cache="$workspace/.cache/phase8-release"
blueprint="$output/phase8-live-blueprint.json"
authenticated_flow="$release_cache/phase8-authenticated-flow.json"
release_evidence="$output/phase8-release-evidence.json"
inclusion_verifier="$release_cache/verify-phase8-inclusion"
home_rpc="${PHASE8_HOME_RPC:-http://127.0.0.1:8545}"
satellite_rpc="${PHASE8_SATELLITE_RPC:-http://127.0.0.1:8546}"
provider_a_url="${UNIFIED_MOCK_BRIDGE_PROVIDER_A:-http://127.0.0.1:58081}"
provider_b_url="${UNIFIED_MOCK_BRIDGE_PROVIDER_B:-http://127.0.0.1:58082}"
observer_signer="$workspace/tools/sign_phase8_observer.py"
expected_home_observer="0xe84d4f1b0cf0e0217292b079bb4db43ad1416f4609b111675e720d2b1dbc0eac"
expected_satellite_observer="0xb442c9cb0eb1bce60df619505451f95701b64e32b269bda231d95a7475f5a6ac"
mkdir -p "$output" "$release_cache"
rm -f -- "$blueprint" "$authenticated_flow" "$release_evidence" "$inclusion_verifier"

[[ "$(uv run python "$observer_signer" public home)" == "$expected_home_observer" ]] || {
  echo "Derived home observer public key differs from the reviewed fixture." >&2
  exit 1
}
[[ "$(uv run python "$observer_signer" public satellite)" == "$expected_satellite_observer" ]] || {
  echo "Derived satellite observer public key differs from the reviewed fixture." >&2
  exit 1
}

resolve_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
  elif [[ -x "$workspace/.cache/foundry-v1.7.1/$name" ]]; then
    printf '%s\n' "$workspace/.cache/foundry-v1.7.1/$name"
  else
    echo "Required Foundry tool '$name' was not found." >&2
    return 1
  fi
}

anvil="$(resolve_tool anvil)"
cast="$(resolve_tool cast)"
forge="$(resolve_tool forge)"
home_pid=""
satellite_pid=""
timestamps_pinned=false

remove_phase8_foundry_runs() {
  local cleanup_root="$1"
  [[ -d "$cleanup_root" ]] || return 0
  local resolved_root
  resolved_root="$(cd "$cleanup_root" && pwd -P)"
  [[ "$resolved_root" == "$protocol/"* ]] || {
    echo "Phase 8 Foundry cleanup root escaped protocol: $resolved_root" >&2
    return 1
  }
  while IFS= read -r -d '' candidate; do
    local resolved_candidate
    resolved_candidate="$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")"
    [[ "$(dirname "$resolved_candidate")" == "$resolved_root" ]] || {
      echo "Refusing escaped Phase 8 Foundry cleanup target: $resolved_candidate" >&2
      return 1
    }
    rm -rf -- "$resolved_candidate"
  done < <(
    find "$resolved_root" -mindepth 1 -maxdepth 1 -type d \
      -name 'DeployPhase8Local.s.sol-*' -print0
  )
}

cleanup() {
  if [[ "$timestamps_pinned" == true ]]; then
    "$cast" rpc --rpc-url "$home_rpc" anvil_setBlockTimestampInterval 1 >/dev/null 2>&1 || true
    "$cast" rpc --rpc-url "$satellite_rpc" anvil_setBlockTimestampInterval 1 >/dev/null 2>&1 || true
  fi
  [[ -z "$home_pid" ]] || kill "$home_pid" 2>/dev/null || true
  [[ -z "$satellite_pid" ]] || kill "$satellite_pid" 2>/dev/null || true
  find "$release_cache" "$output" -maxdepth 1 -type f \
    \( -name '*.pending' -o -name '*.pending.json' \) -delete
}
trap cleanup EXIT

endpoint_is_chain() {
  local rpc="$1"
  local expected="$2"
  [[ "$("$cast" chain-id --rpc-url "$rpc" 2>/dev/null || true)" == "$expected" ]]
}

if ! endpoint_is_chain "$home_rpc" 31337; then
  [[ "$home_rpc" == "http://127.0.0.1:8545" ]] || {
    echo "Unavailable/non-31337 home endpoint: $home_rpc" >&2
    exit 1
  }
  "$anvil" --silent --port 8545 --chain-id 31337 >/dev/null 2>&1 &
  home_pid="$!"
fi
if ! endpoint_is_chain "$satellite_rpc" 31338; then
  [[ "$satellite_rpc" == "http://127.0.0.1:8546" ]] || {
    echo "Unavailable/non-31338 satellite endpoint: $satellite_rpc" >&2
    exit 1
  }
  "$anvil" --silent --port 8546 --chain-id 31338 >/dev/null 2>&1 &
  satellite_pid="$!"
fi

for rpc_chain in "$home_rpc:31337" "$satellite_rpc:31338"; do
  rpc="${rpc_chain%:*}"
  expected="${rpc_chain##*:}"
  for _ in $(seq 1 40); do
    endpoint_is_chain "$rpc" "$expected" && break
    sleep 0.25
  done
  endpoint_is_chain "$rpc" "$expected" || {
    echo "Anvil did not start at $rpc." >&2
    exit 1
  }
done

"$cast" rpc --rpc-url "$home_rpc" anvil_setBlockTimestampInterval 0 >/dev/null
"$cast" rpc --rpc-url "$satellite_rpc" anvil_setBlockTimestampInterval 0 >/dev/null
timestamps_pinned=true
home_timestamp="$("$cast" block latest --field timestamp --rpc-url "$home_rpc")"
satellite_timestamp="$("$cast" block latest --field timestamp --rpc-url "$satellite_rpc")"
if (( home_timestamp > satellite_timestamp )); then
  common_timestamp=$((home_timestamp + 3600))
else
  common_timestamp=$((satellite_timestamp + 3600))
fi
for rpc in "$home_rpc" "$satellite_rpc"; do
  "$cast" rpc --rpc-url "$rpc" evm_setNextBlockTimestamp "$common_timestamp" >/dev/null
  "$cast" rpc --rpc-url "$rpc" evm_mine >/dev/null
done

(
  cd "$protocol"
  remove_phase8_foundry_runs "$protocol/broadcast/multi"
  remove_phase8_foundry_runs "$protocol/cache/multi"
  "$forge" clean
  "$forge" script script/DeployPhase8Local.s.sol:DeployPhase8Local \
    --sig 'runDeployOnly(string,string,string)' \
    "$home_rpc" "$satellite_rpc" "$output" \
    --sender 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266 \
    --unlocked --broadcast --ffi --force --deny never
)

home_manifest="$output/phase8-home-31337.json"
satellite_manifest="$output/phase8-satellite-31338.json"
node - "$home_manifest" "$satellite_manifest" <<'NODE'
const fs = require("fs");
const home = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const satellite = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
if (
  Number(home.chain_id) !== 31337 ||
  Number(satellite.chain_id) !== 31338 ||
  home.contains_real_value !== false ||
  satellite.contains_real_value !== false ||
  home.mint_route_hash !== satellite.mint_route_hash
) {
  throw new Error("Phase 8 deployment manifest safety/parity check failed.");
}
NODE

[[ -f "$blueprint" ]] || {
  echo "Phase 8 deploy-only blueprint was not written." >&2
  exit 1
}

(
  cd "$workspace"
  go build -o "$inclusion_verifier" \
    ./services/chain-indexer/cmd/verify-phase8-inclusion
  uv run --frozen python tools/run_phase8_authenticated_flow.py \
    --home-rpc "$home_rpc" \
    --satellite-rpc "$satellite_rpc" \
    --provider-a-url "$provider_a_url" \
    --provider-b-url "$provider_b_url" \
    --blueprint "$blueprint" \
    --verifier "$inclusion_verifier" \
    --output "$authenticated_flow" \
    --max-messages 8
  uv run --frozen python tools/assemble_phase8_release_evidence.py

  export UNIFIED_POSTGRES_DSN="${UNIFIED_POSTGRES_DSN:-postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable}"
  export UNIFIED_CROSSCHAIN_DATABASE_URL="${UNIFIED_CROSSCHAIN_DATABASE_URL:-postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable&options=-c%20role%3Dunified_crosschain_runtime}"
  export UNIFIED_CROSSCHAIN_OBSERVER_DATABASE_URL="${UNIFIED_CROSSCHAIN_OBSERVER_DATABASE_URL:-postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable&options=-c%20role%3Dunified_crosschain_observer}"
  export UNIFIED_CROSSCHAIN_FINALITY_DATABASE_URL="${UNIFIED_CROSSCHAIN_FINALITY_DATABASE_URL:-postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable&options=-c%20role%3Dunified_crosschain_finality_attester}"
  export UNIFIED_CROSSCHAIN_RECOVERY_DATABASE_URL="${UNIFIED_CROSSCHAIN_RECOVERY_DATABASE_URL:-postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable&options=-c%20role%3Dunified_crosschain_recovery_verifier}"
  export UNIFIED_CROSSCHAIN_REORGANIZATION_DATABASE_URL="${UNIFIED_CROSSCHAIN_REORGANIZATION_DATABASE_URL:-postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable&options=-c%20role%3Dunified_crosschain_reorganization_verifier}"
  export UNIFIED_KAFKA_BROKERS="${UNIFIED_KAFKA_BROKERS:-127.0.0.1:19092}"
  export UNIFIED_OBJECT_ENDPOINT="${UNIFIED_OBJECT_ENDPOINT:-http://127.0.0.1:59000}"
  export UNIFIED_MOCK_BRIDGE_PROVIDER_A="$provider_a_url"
  export UNIFIED_MOCK_BRIDGE_PROVIDER_B="$provider_b_url"
  go run ./services/cross-chain-coordinator/cmd/local-worker \
    --mode smoke --timeout 90s
  uv run --frozen python tools/check_phase8_release_evidence.py \
    --stage pre-reset --evidence "$release_evidence"
)

node - "$authenticated_flow" <<'NODE'
const fs = require("fs");
const flow = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (
  Number(flow.completed_message_count) !== 8 ||
  flow.proof_boundary !== "AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT" ||
  flow.final_state.loan_state !== "CLOSED"
) {
  throw new Error("Authenticated flow summary is incomplete or non-terminal.");
}
NODE

echo "Phase 8 two-Anvil smoke passed: home=31337 satellite=31338 boundary=AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT messages=8 loan_state=CLOSED"
