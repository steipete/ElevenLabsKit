#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$(swift build --package-path "$repo_root/Examples/ElevenLabsKitCLI" --show-bin-path)"
cli="$bin_dir/ElevenLabsKitCLI"
output="$(mktemp)"
trap 'rm -f "$output"' EXIT

check() {
  local expected_exit="$1"
  local expected_message="$2"
  shift 2
  local actual_exit=0
  env -u ELEVENLABS_API_KEY -u XI_API_KEY -u ELEVEN_API_KEY \
    "$cli" "$@" </dev/null >"$output" 2>&1 || actual_exit=$?
  if [[ "$actual_exit" != "$expected_exit" ]] || ! grep -Fq -- "$expected_message" "$output"; then
    printf 'FAIL: %s (exit %s, expected %s; expected message: %s)\n' "$*" "$actual_exit" "$expected_exit" "$expected_message" >&2
    cat "$output" >&2
    exit 1
  fi
}

check 0 'Usage:' --help
for value in -1 nope 1.5 999999999999999999999999999999 ''; do
  check 1 'error: --limit must be a non-negative integer.' voices --limit "$value"
done
for value in -1 5 nope 1.5 999999999999999999999999999999 ''; do
  check 1 'error: --latency-tier must be an integer from 0 to 4.' speak --latency-tier "$value" hello
done
check 1 'error: Missing value for --limit.' voices --limit
check 1 'error: Missing value for --latency-tier.' speak --latency-tier

# Valid values reach the credential check without sending any API requests.
for value in 0 1 9223372036854775807; do
  check 1 'error: Missing API key.' voices --limit "$value"
done
for value in 0 1 2 3 4; do
  check 1 'error: Missing API key.' speak --latency-tier "$value" hello
done
printf 'CLI argument checks passed.\n'
