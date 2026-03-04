#!/usr/bin/env bash
set -euo pipefail

source .env

RPC_URL="${TESTNET_RPC:-}"

usage() {
  cat <<'USAGE'
Usage:
  script/tenderly.sh run-batch <batch-json-file> <impersonated-address>
  script/tenderly.sh set-next-block-time <unix-timestamp>
USAGE
}

if ! command -v cast >/dev/null 2>&1; then
  echo "error: cast is required (Foundry)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

if [[ -z "$RPC_URL" ]]; then
  echo "error: TESTNET_RPC is not set in .env" >&2
  exit 1
fi

cmd="${1:-}"

case "$cmd" in
  run-batch)
    batch_file="${2:-}"
    from="${3:-}"

    if [[ -z "$batch_file" || -z "$from" ]]; then
      usage
      exit 1
    fi

    if [[ ! -f "$batch_file" ]]; then
      echo "error: batch file not found: $batch_file" >&2
      exit 1
    fi

    cast rpc --rpc-url "$RPC_URL" tenderly_impersonateAccount "$from" >/dev/null 2>&1 || true

    count=$(jq '.transactions | length' "$batch_file")
    echo "Executing $count transaction(s) as $from"

    i=0
    while IFS= read -r tx; do
      i=$((i + 1))
      value_dec=$(jq -r '.value // "0"' <<<"$tx")
      value_hex=$(cast to-hex "$value_dec")

      tx_obj=$(jq -c --arg from "$from" --arg value "$value_hex" '{
        from: $from,
        to: .to,
        data: (.data // "0x"),
        value: $value
      }' <<<"$tx")

      tx_hash=$(cast rpc --rpc-url "$RPC_URL" --raw eth_sendTransaction "[$tx_obj]")
      echo "[$i/$count] $tx_hash"
    done < <(jq -c '.transactions[]' "$batch_file")
    ;;

  set-next-block-time)
    ts="${2:-}"

    if [[ -z "$ts" ]]; then
      usage
      exit 1
    fi

    cast rpc --rpc-url "$RPC_URL" tenderly_setNextBlockTimestamp "$ts" >/dev/null 2>&1 || \

    echo "Set next block timestamp to $ts"
    ;;

  *)
    usage
    exit 1
    ;;
esac
