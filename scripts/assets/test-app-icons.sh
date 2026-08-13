#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script="$script_dir/app_icons.sh"

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

assert_rejected "expected SVG:ICNS" icon.svg
assert_rejected "paths must not be empty" :EasyBar.icns
assert_rejected "paths must not be empty" icon.svg:
assert_rejected ".icns extension" icon.svg:EasyBar.png
assert_rejected "must be different paths" EasyBar.icns:EasyBar.icns
