#!/usr/bin/env bash
set -euo pipefail

# Keep CI and local checks on the versions validated against our lint configs.
swiftformat_version=0.63.1
swiftformat_sha256=385ef1a263ba28685157b98c5536b9c9105e124518f28b7ef8a2bee4b167eaeb
swiftlint_version=0.65.1
swiftlint_sha256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0

bin_dir="${1:-.build/linters}"
mkdir -p "$bin_dir"
download_dir="$(mktemp -d "$bin_dir/downloads.XXXXXX")"
trap 'rm -rf "$download_dir"' EXIT

curl --fail --location --silent --show-error --retry 3 \
  "https://github.com/nicklockwood/SwiftFormat/releases/download/$swiftformat_version/swiftformat.zip" \
  --output "$download_dir/swiftformat.zip"
curl --fail --location --silent --show-error --retry 3 \
  "https://github.com/realm/SwiftLint/releases/download/$swiftlint_version/portable_swiftlint.zip" \
  --output "$download_dir/swiftlint.zip"

printf '%s  %s\n' "$swiftformat_sha256" "$download_dir/swiftformat.zip" \
  "$swiftlint_sha256" "$download_dir/swiftlint.zip" | shasum --algorithm 256 --check
unzip -qo "$download_dir/swiftformat.zip" swiftformat -d "$bin_dir"
unzip -qo "$download_dir/swiftlint.zip" swiftlint -d "$bin_dir"

"$bin_dir/swiftformat" --version
"$bin_dir/swiftlint" version
