#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

assert_rejected() {
  local dist_dir="$1"
  local expected="$2"
  local error_file="$tmp_dir/error"

  if make -s -C "$repo_root" clean-dist DIST_DIR="$dist_dir" >/dev/null 2>"$error_file"; then
    echo "Expected unsafe distribution path to be rejected: $dist_dir" >&2
    exit 1
  fi
  grep -F "$expected" "$error_file" >/dev/null
}

assert_rejected . "must not be the project root"
assert_rejected / "must not be the filesystem root"
assert_rejected "$(dirname -- "$repo_root")" "must not be the project root"
assert_rejected .git "must not be inside Git metadata"
assert_rejected Sources "contains tracked project files"
assert_rejected Makefile "contains tracked project files"

safe_dist="$tmp_dir/dist"
mkdir -p "$safe_dist/subdirectory"
touch "$safe_dist/subdirectory/file"
make -s -C "$repo_root" clean-dist DIST_DIR="$safe_dist"
if [ -e "$safe_dist" ]; then
  echo "Safe distribution directory was not removed: $safe_dist" >&2
  exit 1
fi
