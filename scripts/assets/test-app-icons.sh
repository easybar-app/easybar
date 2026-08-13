#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script="$script_dir/app_icons.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

assert_rejected() {
  local expected="$1"
  shift
  local output

  if output="$("$script" missing-svg-tool missing-image-tool dist "$@" 2>&1)"; then
    echo "Expected invalid icon arguments to fail: $*" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    echo "Unexpected validation error for $*: $output" >&2
    exit 1
  fi
}

if output="$($script missing-svg-tool missing-image-tool '' icon.svg:EasyBar.icns 2>&1)"; then
  echo "Expected an empty icon staging directory to fail" >&2
  exit 1
fi
if [[ "$output" != *"must not be empty"* ]]; then
  echo "Unexpected empty staging-directory error: $output" >&2
  exit 1
fi

if output="$($script missing-svg-tool missing-image-tool / icon.svg:EasyBar.icns 2>&1)"; then
  echo "Expected the filesystem root icon staging directory to fail" >&2
  exit 1
fi
if [[ "$output" != *"must not be the filesystem root"* ]]; then
  echo "Unexpected root staging-directory error: $output" >&2
  exit 1
fi

assert_rejected "expected SVG:ICNS" icon.svg
assert_rejected "paths must not be empty" :EasyBar.icns
assert_rejected "paths must not be empty" icon.svg:
assert_rejected ".icns extension" icon.svg:EasyBar.png
assert_rejected "must be different paths" EasyBar.icns:EasyBar.icns
mkdir "$tmp_dir/EasyBar.icns"
assert_rejected "must not be a directory" "icon.svg:$tmp_dir/EasyBar.icns"
