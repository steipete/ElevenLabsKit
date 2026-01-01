#!/usr/bin/env bash
set -euo pipefail

threshold="${1:-70}"
ignore_regex='(/Tests/|/Examples/|/\.build/)'

codecov_ref="$(swift test --show-codecov-path)"
codecov_dir="$codecov_ref"
if [[ ! -d "$codecov_dir" ]]; then
  codecov_dir="$(dirname "$codecov_ref")"
fi

profdata="$codecov_dir/default.profdata"

if [[ ! -f "$profdata" ]]; then
  echo "error: no profdata at $profdata (run: swift test --enable-code-coverage)"
  exit 1
fi

bin_path="$(swift build --show-bin-path)"
bundle_dir="$(find "$bin_path" -maxdepth 1 -type d -name '*PackageTests.xctest' | head -n 1)"

if [[ -z "${bundle_dir}" ]]; then
  echo "error: could not find *PackageTests.xctest in $bin_path"
  exit 1
fi

test_binary="$(find "$bundle_dir" -type f -path '*/Contents/MacOS/*' | head -n 1)"

bundle_name="$(basename "$bundle_dir")"
bundle_exec="${bundle_name%.xctest}"
expected_binary="$bundle_dir/Contents/MacOS/$bundle_exec"
if [[ -x "$expected_binary" ]]; then
  test_binary="$expected_binary"
fi

if [[ -z "${test_binary}" || ! -f "${test_binary}" ]]; then
  echo "error: could not find test binary in $bundle_dir"
  exit 1
fi

coverage="$(
  xcrun llvm-cov report "$test_binary" \
    -instr-profile "$profdata" \
    -ignore-filename-regex "$ignore_regex" \
    -use-color=false \
    | awk '/^TOTAL/ { gsub(/%/, "", $10); print $10 }'
)"

if [[ -z "${coverage}" ]]; then
  echo "error: could not parse TOTAL coverage"
  exit 1
fi

echo "coverage: $coverage% (threshold: $threshold%)"
awk -v c="$coverage" -v t="$threshold" 'BEGIN { exit ((c + 0) >= (t + 0)) ? 0 : 1 }'
