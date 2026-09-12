#!/usr/bin/env bash
# Verify development recipes stop before using failed build or version results.
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/kit" "$tmp_dir/package" "$tmp_dir/scripts/dev" "$tmp_dir/scripts/build"
touch "$tmp_dir/kit/Package.swift"
cp "$repo_root/Makefile" "$tmp_dir/Makefile"

cat > "$tmp_dir/swift" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$CALL_LOG"
case "$*" in
  *--show-bin-path*) printf '%s\n' "$STUB_BIN" ;;
  *) exit 42 ;;
esac
STUB
cat > "$tmp_dir/scripts/dev/local-version.sh" <<'STUB'
#!/bin/sh
exit 42
STUB
cat > "$tmp_dir/scripts/build/bundle.sh" <<'STUB'
#!/bin/sh
touch "$BUNDLE_MARKER"
STUB
chmod +x "$tmp_dir/swift" "$tmp_dir/scripts/dev/local-version.sh" "$tmp_dir/scripts/build/bundle.sh"
export CALL_LOG="$tmp_dir/calls" STUB_BIN="$tmp_dir/bin" BUNDLE_MARKER="$tmp_dir/bundled"

if make -s -C "$tmp_dir" -o prepare-local-package support \
  EASYBAR_KIT_ROOT="$tmp_dir/kit" LOCAL_PACKAGE_DIR="$tmp_dir/package" \
  SWIFT="$tmp_dir/swift" >"$tmp_dir/output" 2>&1; then
  echo 'support unexpectedly succeeded after a failed runtime build' >&2
  exit 1
fi
[ "$(wc -l < "$CALL_LOG" | tr -d ' ')" = 1 ]
[ ! -e "$STUB_BIN" ]

if make -s -C "$tmp_dir" bundle-local >"$tmp_dir/output" 2>&1; then
  echo 'bundle-local unexpectedly succeeded after a failed version lookup' >&2
  exit 1
fi
[ ! -e "$BUNDLE_MARKER" ]

: > "$CALL_LOG"
if make -s -C "$tmp_dir" -o support run \
  EASYBAR_KIT_ROOT="$tmp_dir/missing-kit" LOCAL_PACKAGE_DIR="$tmp_dir/package" \
  SWIFT="$tmp_dir/swift" >"$tmp_dir/output" 2>&1; then
  echo 'run unexpectedly succeeded with a missing dependency directory' >&2
  exit 1
fi
[ ! -s "$CALL_LOG" ]
