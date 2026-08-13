#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "$repo_root/scripts/release/archive-utils.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

dist_dir="$tmp_dir/dist"
mkdir -p \
  "$dist_dir/EasyBar.app/Contents/MacOS" \
  "$dist_dir/EasyBarCalendarAgent.app/Contents/MacOS" \
  "$dist_dir/EasyBarNetworkAgent.app/Contents/MacOS"
printf '#!/bin/sh\n' >"$dist_dir/EasyBar.app/Contents/MacOS/EasyBar"
printf '#!/bin/sh\n' >"$dist_dir/EasyBarCalendarAgent.app/Contents/MacOS/EasyBarCalendarAgent"
printf '#!/bin/sh\n' >"$dist_dir/EasyBarNetworkAgent.app/Contents/MacOS/EasyBarNetworkAgent"
printf '#!/bin/sh\n' >"$dist_dir/easybar"
chmod +x \
  "$dist_dir/EasyBar.app/Contents/MacOS/EasyBar" \
  "$dist_dir/EasyBarCalendarAgent.app/Contents/MacOS/EasyBarCalendarAgent" \
  "$dist_dir/EasyBarNetworkAgent.app/Contents/MacOS/EasyBarNetworkAgent" \
  "$dist_dir/easybar"

"$repo_root/scripts/release/package.sh" \
  --version 9.8.7-dev.test \
  --dist-dir "$dist_dir" >/dev/null

main_archive="$dist_dir/EasyBar-9.8.7-dev.test.zip"
calendar_archive="$dist_dir/EasyBarCalendarAgent-9.8.7-dev.test.zip"
network_archive="$dist_dir/EasyBarNetworkAgent-9.8.7-dev.test.zip"

archive_contains_exact_entry "$main_archive" "EasyBar.app/Contents/MacOS/EasyBar"
archive_contains_exact_entry "$main_archive" "easybar"
test "$(archive_top_level_entries "$main_archive")" = $'EasyBar.app\neasybar'

archive_contains_exact_entry \
  "$calendar_archive" \
  "EasyBarCalendarAgent-9.8.7-dev.test/EasyBarCalendarAgent.app/Contents/MacOS/EasyBarCalendarAgent"
test "$(archive_top_level_entries "$calendar_archive")" = "EasyBarCalendarAgent-9.8.7-dev.test"

archive_contains_exact_entry \
  "$network_archive" \
  "EasyBarNetworkAgent-9.8.7-dev.test/EasyBarNetworkAgent.app/Contents/MacOS/EasyBarNetworkAgent"
test "$(archive_top_level_entries "$network_archive")" = "EasyBarNetworkAgent-9.8.7-dev.test"

if "$repo_root/scripts/release/package.sh" \
  --version '../unsafe' \
  --dist-dir "$dist_dir" >/dev/null 2>&1; then
  echo "Expected unsafe package version to fail" >&2
  exit 1
fi
