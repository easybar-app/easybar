#!/usr/bin/env bash
# Test application bundle creation.
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
bundle_script="$repo_root/scripts/build/bundle.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
kit_root="$tmp_dir/easybar-kit"
build_root="$tmp_dir/build"
dist_dir="$tmp_dir/dist"
mkdir -p \
  "$fake_bin" \
  "$kit_root/Sources/EasyBarKit/Lua/easybar" \
  "$kit_root/Sources/EasyBarKit/Events" \
  "$kit_root/Sources/EasyBarKit/Theme" \
  "$kit_root/Sources/EasyBarKit/Assets" \
  "$kit_root/Sources/EasyBarCalendarAgent" \
  "$kit_root/Sources/EasyBarNetworkAgent" \
  "$kit_root/packaging" \
  "$kit_root/themes" \
  "$kit_root/.build" \
  "$dist_dir"

: >"$kit_root/Package.swift"
printf 'runtime\n' >"$kit_root/Sources/EasyBarKit/Lua/runtime.lua"
cat >"$kit_root/Sources/EasyBarKit/Lua/easybar_api.lua" <<'EOF_LUA_API'
-- EasyBar Lua API stub version: dev
---@field version string EasyBar application version (`dev`).
EasyBar.version = "dev"
EOF_LUA_API
printf 'return {}\n' >"$kit_root/Sources/EasyBarKit/Lua/easybar/init.lua"
printf '{}\n' >"$kit_root/Sources/EasyBarKit/Events/event_catalog.json"
printf '{}\n' >"$kit_root/Sources/EasyBarKit/Theme/theme_tokens.json"
printf '<svg/>\n' >"$kit_root/Sources/EasyBarKit/Assets/easybar-menubar.svg"
printf 'name = "default"\n' >"$kit_root/themes/default.toml"
printf '<svg/>\n' >"$kit_root/packaging/easybar-calendar-agent-icon.svg"
printf '<svg/>\n' >"$kit_root/packaging/easybar-network-agent-icon.svg"
printf 'original\n' >"$kit_root/.build/easybar-build-version"
printf 'previous distribution\n' >"$dist_dir/old-marker"

python3 - "$kit_root" <<'PY_PLISTS'
import plistlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
for name in ("EasyBarCalendarAgent", "EasyBarNetworkAgent"):
    path = root / "Sources" / name / "Info.plist"
    with path.open("wb") as handle:
        plistlib.dump(
            {
                "CFBundleIdentifier": f"io.github.gi8lino.{name}",
                "CFBundleExecutable": name,
                "CFBundleName": name,
                "CFBundleDisplayName": name,
                "CFBundleShortVersionString": "0.0.0",
                "CFBundleVersion": "0.0.0",
            },
            handle,
        )
PY_PLISTS

cat >"$fake_bin/uname" <<'EOF_UNAME'
#!/usr/bin/env sh
case "${1:-}" in
-s) echo Darwin ;;
-m) echo arm64 ;;
*) echo Darwin ;;
esac
EOF_UNAME

cat >"$fake_bin/swift" <<'EOF_SWIFT'
#!/usr/bin/env bash
set -euo pipefail

package_root=$PWD
product=""
show_bin_path=false
while [ "$#" -gt 0 ]; do
  case "$1" in
  --package-path)
    package_root=${2:?}
    shift 2
    ;;
  --product)
    product=${2:?}
    shift 2
    ;;
  --show-bin-path)
    show_bin_path=true
    shift
    ;;
  *) shift ;;
  esac
done

if [ "$package_root" = "$FAKE_KIT_ROOT" ]; then
  bin_dir="$FAKE_BUILD_ROOT/kit"
else
  bin_dir="$FAKE_BUILD_ROOT/root"
fi
mkdir -p "$bin_dir"

if [ "$show_bin_path" = true ]; then
  printf '%s\n' "$bin_dir"
  exit 0
fi

if [ -z "$product" ]; then
  echo "Fake swift build did not receive --product" >&2
  exit 2
fi

version=$(cat "$FAKE_KIT_ROOT/.build/easybar-build-version")
case "$product" in
EasyBar) version_output="EasyBar $version" ;;
EasyBarCtl) version_output="easybar $version" ;;
*) version_output="$product $version" ;;
esac

cat >"$bin_dir/$product" <<EOF_PRODUCT
#!/usr/bin/env sh
if [ "\${1:-}" = --version ]; then
  printf '%s\\n' '$version_output'
fi
EOF_PRODUCT
chmod +x "$bin_dir/$product"
EOF_SWIFT

cat >"$fake_bin/lipo" <<'EOF_LIPO'
#!/usr/bin/env sh
exit 0
EOF_LIPO

cat >"$fake_bin/rsvg-convert" <<'EOF_RSVG'
#!/usr/bin/env bash
set -euo pipefail
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  --output)
    output=${2:?}
    shift 2
    ;;
  *) shift ;;
  esac
done
: >"$output"
EOF_RSVG

cat >"$fake_bin/magick" <<'EOF_MAGICK'
#!/usr/bin/env sh
printf '0.5'
EOF_MAGICK

cat >"$fake_bin/sips" <<'EOF_SIPS'
#!/usr/bin/env bash
set -euo pipefail
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  --out)
    output=${2:?}
    shift 2
    ;;
  *) shift ;;
  esac
done
: >"$output"
EOF_SIPS

cat >"$fake_bin/iconutil" <<'EOF_ICONUTIL'
#!/usr/bin/env bash
set -euo pipefail
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  -o)
    output=${2:?}
    shift 2
    ;;
  *) shift ;;
  esac
done
printf 'icon\n' >"$output"
EOF_ICONUTIL

cat >"$fake_bin/codesign" <<'EOF_CODESIGN'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${FAKE_CODESIGN_FAIL_MARKER:-}" ] && \
  [ ! -e "$FAKE_CODESIGN_FAIL_MARKER" ]; then
  : >"$FAKE_CODESIGN_FAIL_MARKER"
  exit 1
fi
EOF_CODESIGN

chmod +x "$fake_bin"/*

bundle_args=(
  --kit-root "$kit_root"
  --arch arm64
  --version 1.2.3
  --dist-dir "$dist_dir"
)
fail_marker="$tmp_dir/codesign-failed"

if output="$({
  PATH="$fake_bin:$PATH" \
    FAKE_BUILD_ROOT="$build_root" \
    LOCAL_PACKAGE_DIR="$tmp_dir/local-package" \
    FAKE_KIT_ROOT="$kit_root" \
    FAKE_CODESIGN_FAIL_MARKER="$fail_marker" \
    "$bundle_script" "${bundle_args[@]}"
} 2>&1)"; then
  echo "Expected staged bundle failure" >&2
  exit 1
fi
if [[ "$output" != *"bundle failed"* ]]; then
  echo "Expected bundle failure diagnostic, got: $output" >&2
  exit 1
fi
[ -f "$dist_dir/old-marker" ]
[ ! -e "$dist_dir/EasyBar.app" ]
grep -Fx original "$kit_root/.build/easybar-build-version" >/dev/null

leftovers="$(find "$tmp_dir" \( -name '.dist.build.*' -o -name '.dist.previous.*' \) -print)"
if [ -n "$leftovers" ]; then
  echo "Failed bundle left staging paths:" >&2
  printf '%s\n' "$leftovers" >&2
  exit 1
fi

output="$({
  PATH="$fake_bin:$PATH" \
    FAKE_BUILD_ROOT="$build_root" \
    LOCAL_PACKAGE_DIR="$tmp_dir/local-package" \
    FAKE_KIT_ROOT="$kit_root" \
    FAKE_CODESIGN_FAIL_MARKER="$fail_marker" \
    "$bundle_script" "${bundle_args[@]}"
} 2>&1)"

[ ! -e "$dist_dir/old-marker" ]
[ -x "$dist_dir/EasyBar.app/Contents/MacOS/EasyBar" ]
[ -x "$dist_dir/easybar" ]
[ "$("$dist_dir/EasyBar.app/Contents/MacOS/EasyBar" --version)" = "EasyBar 1.2.3" ]
[ "$("$dist_dir/easybar" --version)" = "easybar 1.2.3" ]
grep -Fx original "$kit_root/.build/easybar-build-version" >/dev/null
if [[ "$output" != *"$dist_dir/EasyBar.app"* ]]; then
  echo "Bundle summary did not report the published distribution: $output" >&2
  exit 1
fi

leftovers="$(find "$tmp_dir" \( -name '.dist.build.*' -o -name '.dist.previous.*' \) -print)"
if [ -n "$leftovers" ]; then
  echo "Successful bundle left staging paths:" >&2
  printf '%s\n' "$leftovers" >&2
  exit 1
fi
