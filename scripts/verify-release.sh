#!/usr/bin/env bash
set -euo pipefail

# Honor the workflow's pinned DEVELOPER_DIR or the contributor's selected Xcode.
toolchain_version=$(xcrun swift --version)
if [[ ! "$toolchain_version" =~ Swift\ version\ ([0-9]+)\.([0-9]+) ]] ||
  (( BASH_REMATCH[1] != 6 || BASH_REMATCH[2] < 3 )); then
  echo 'Select Xcode with Swift 6.3 or newer Swift 6' >&2
  exit 1
fi
printf '%s\n' "$toolchain_version"
xcrun swift build --configuration release --jobs 2
xcrun swift test --jobs 2
