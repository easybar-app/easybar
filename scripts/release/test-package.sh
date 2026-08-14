#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "$repo_root/scripts/release/archive-utils.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

assert_archive_roots() {
  local archive="$1"
  local expected="$2"
  local actual

  actual="$(archive_top_level_entries "$archive")"

  if [ "$actual" != "$expected" ]; then
    echo "Unexpected top-level entries in $archive" >&2
    echo "Expected:" >&2
    printf '%s\n' "$expected" >&2
    echo "Actual:" >&2
    printf '%s\n' "$actual" >&2
    echo "Complete archive listing:" >&2
    unzip -Z1 "$archive" >&2
    exit 1
  fi
}

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

archive_contains_exact_entry \
  "$main_archive" \
  "EasyBar.app/Contents/MacOS/EasyBar"

archive_contains_exact_entry \
  "$main_archive" \
  "easybar"

assert_archive_roots \
  "$main_archive" \
  $'EasyBar.app\neasybar'

archive_contains_exact_entry \
  "$calendar_archive" \
  "EasyBarCalendarAgent-9.8.7-dev.test/EasyBarCalendarAgent.app/Contents/MacOS/EasyBarCalendarAgent"

assert_archive_roots \
  "$calendar_archive" \
  "EasyBarCalendarAgent-9.8.7-dev.test"

archive_contains_exact_entry \
  "$network_archive" \
  "EasyBarNetworkAgent-9.8.7-dev.test/EasyBarNetworkAgent.app/Contents/MacOS/EasyBarNetworkAgent"

assert_archive_roots \
  "$network_archive" \
  "EasyBarNetworkAgent-9.8.7-dev.test"

if "$repo_root/scripts/release/package.sh" \
  --version '1.2.3-../../unsafe' \
  --dist-dir "$dist_dir" >/dev/null 2>&1; then
  echo "Expected unsafe package version to fail" >&2
  exit 1
fi

printf 'old main archive\n' >"$main_archive"
printf 'old calendar archive\n' >"$calendar_archive"
printf 'old network archive\n' >"$network_archive"

cp "$main_archive" "$tmp_dir/main.expected"
cp "$calendar_archive" "$tmp_dir/calendar.expected"
cp "$network_archive" "$tmp_dir/network.expected"

real_zip="$(command -v zip)"
fake_bin="$tmp_dir/bin"
zip_count="$tmp_dir/zip-count"

mkdir "$fake_bin"

cat >"$fake_bin/zip" <<'EOF_ZIP'
#!/usr/bin/env bash
set -euo pipefail

count=0
if [ -f "$FAKE_ZIP_COUNT_FILE" ]; then
  count="$(cat "$FAKE_ZIP_COUNT_FILE")"
fi

count=$((count + 1))
printf '%s\n' "$count" >"$FAKE_ZIP_COUNT_FILE"

if [ "$count" -eq 2 ]; then
  output=""
  previous=""

  for argument in "$@"; do
    if [ "$previous" = "-o" ]; then
      output="$argument"
      break
    fi

    case "$argument" in
    *.zip)
      output="$argument"
      break
      ;;
    esac

    previous="$argument"
  done

  if [ -z "$output" ]; then
    echo "Fake zip could not resolve output archive from: $*" >&2
    exit 2
  fi

  printf 'invalid zip archive\n' >"$output"
  exit 0
fi

exec "$REAL_ZIP" "$@"
EOF_ZIP

chmod +x "$fake_bin/zip"

if PATH="$fake_bin:$PATH" \
  FAKE_ZIP_COUNT_FILE="$zip_count" \
  REAL_ZIP="$real_zip" \
  "$repo_root/scripts/release/package.sh" \
  --version 9.8.7-dev.test \
  --dist-dir "$dist_dir" >/dev/null 2>&1; then
  echo "Expected invalid staged package to fail" >&2
  exit 1
fi

cmp -s "$main_archive" "$tmp_dir/main.expected"
cmp -s "$calendar_archive" "$tmp_dir/calendar.expected"
cmp -s "$network_archive" "$tmp_dir/network.expected"

leftovers="$(find "$dist_dir" -name '.easybar-package.*' -print)"
if [ -n "$leftovers" ]; then
  echo "Failed package creation left staging directories:" >&2
  printf '%s\n' "$leftovers" >&2
  exit 1
fi
