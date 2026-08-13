#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
helper="$repo_root/scripts/build/prepare-local-package.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

kit_root="$tmp_dir/easybar-kit"
workspace="$tmp_dir/local-package"
mkdir -p "$kit_root/Sources/EasyBarKit" "$kit_root/Sources/EasyBarShared"
cat >"$kit_root/Package.swift" <<'EOF_PACKAGE'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
  name: "EasyBarKit",
  products: [
    .library(name: "EasyBarKit", targets: ["EasyBarKit"]),
    .library(name: "EasyBarShared", targets: ["EasyBarShared"]),
  ],
  targets: [
    .target(name: "EasyBarKit"),
    .target(name: "EasyBarShared"),
  ]
)
EOF_PACKAGE
printf 'public struct EasyBarKitFixture {}\n' >"$kit_root/Sources/EasyBarKit/Fixture.swift"
printf 'public struct EasyBarSharedFixture {}\n' >"$kit_root/Sources/EasyBarShared/Fixture.swift"

resolved_before="$tmp_dir/Package.resolved.before"
cp "$repo_root/Package.resolved" "$resolved_before"

"$helper" --project-root "$repo_root" --output "$workspace"
[ -f "$workspace/.easybar-local-package" ]
[ -L "$workspace/Sources" ]
[ -L "$workspace/Tests" ]
mkdir -p "$workspace/.build"
printf 'preserved\n' >"$workspace/.build/cache-marker"

EASYBAR_KIT_ROOT="$kit_root" \
  swift package --package-path "$workspace" dump-package |
  python3 -c '
import json
import os
import sys

dependency = json.load(sys.stdin)["dependencies"][0]["fileSystem"][0]
expected = os.path.realpath(sys.argv[1])
actual = os.path.realpath(dependency["path"])
if actual != expected:
    raise SystemExit(f"unexpected local dependency path: {actual}")
' "$kit_root"

EASYBAR_KIT_ROOT="$kit_root" \
  swift build --package-path "$workspace" --show-bin-path >/dev/null
cmp -s "$repo_root/Package.resolved" "$resolved_before"

"$helper" --project-root "$repo_root" --output "$workspace"
grep -Fx preserved "$workspace/.build/cache-marker" >/dev/null
cmp -s "$repo_root/Package.resolved" "$resolved_before"

if "$helper" --project-root "$repo_root" --output "$repo_root" >/dev/null 2>&1; then
  echo "Expected the project root local workspace to be rejected" >&2
  exit 1
fi

if "$helper" --project-root "$repo_root" --output "$repo_root/Sources/local-package" >/dev/null 2>&1; then
  echo "Expected a project-local workspace outside .build to be rejected" >&2
  exit 1
fi

unowned_workspace="$tmp_dir/unowned"
mkdir -p "$unowned_workspace"
printf 'keep
' >"$unowned_workspace/existing"
if "$helper" --project-root "$repo_root" --output "$unowned_workspace" >/dev/null 2>&1; then
  echo "Expected a nonempty unowned workspace to be rejected" >&2
  exit 1
fi
grep -Fx keep "$unowned_workspace/existing" >/dev/null

if "$helper" --project-root "$repo_root" --output / >/dev/null 2>&1; then
  echo "Expected the filesystem root local workspace to be rejected" >&2
  exit 1
fi
