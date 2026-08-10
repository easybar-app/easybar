#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "release verification failed at line $LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/release/verify-release.sh [--version <version>] [--arch <arm64|x86_64|universal>] [--dist-dir <dir>]
EOF_USAGE
}

version="${VERSION:-dev}"
arch="${ARCH:-universal}"
dist_dir="${DIST_DIR:-dist}"

while [ "$#" -gt 0 ]; do
  case "$1" in
  --version)
    version="${2:?missing value for --version}"
    shift 2
    ;;
  --arch)
    arch="${2:?missing value for --arch}"
    shift 2
    ;;
  --dist-dir)
    dist_dir="${2:?missing value for --dist-dir}"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage
    exit 2
    ;;
  esac
done

case "$arch" in
arm64 | x86_64 | universal) ;;
*)
  echo "Unsupported architecture '$arch'. Use arm64, x86_64, or universal." >&2
  exit 2
  ;;
esac

app_bundle="$dist_dir/EasyBar.app"
app_contents="$app_bundle/Contents"
app_resources="$app_contents/Resources"
app_resource_dir="$app_resources/EasyBar"
app_themes_dir="$app_resources/Themes"
app_bin="$app_contents/MacOS/EasyBar"
plist="$app_contents/Info.plist"
app_icon_icns="$app_resources/EasyBar.icns"
calendar_icon_icns="$dist_dir/EasyBarCalendarAgent.app/Contents/Resources/EasyBarCalendarAgent.icns"
network_icon_icns="$dist_dir/EasyBarNetworkAgent.app/Contents/Resources/EasyBarNetworkAgent.icns"
package_zip="$dist_dir/EasyBar-$version.zip"
calendar_agent_zip="$dist_dir/EasyBarCalendarAgent-$version.zip"
network_agent_zip="$dist_dir/EasyBarNetworkAgent-$version.zip"

require_file() {
  local path="$1"
  local label="$2"

  if [ ! -f "$path" ]; then
    echo "Missing ${label}: ${path}" >&2
    exit 1
  fi
}

scripts/build/verify-bundle.sh --arch "$arch" --version "$version" --dist-dir "$dist_dir"

require_file "$package_zip" "release package"
require_file "$calendar_agent_zip" "calendar agent release package"
require_file "$network_agent_zip" "network agent release package"
require_file "$app_resource_dir/Lua/easybar_api.lua" "Lua API stub"
require_file "$app_resource_dir/Lua/runtime.lua" "Lua runtime"
require_file "$app_resource_dir/Events/event_catalog.json" "event catalog"
require_file "$app_resource_dir/ThemeTokens/theme_tokens.json" "theme token catalog"
require_file "$app_themes_dir/default.toml" "default bundled theme"

verify_agent_archive() {
  local archive="$1"
  local wrapper="$2"
  local app_name="$3"
  local expected_entry="${wrapper}/${app_name}.app/Contents/MacOS/${app_name}"

  if ! unzip -Z1 "$archive" | grep -Fxq "$expected_entry"; then
    echo "Agent archive does not contain expected Homebrew layout: ${expected_entry}" >&2
    unzip -Z1 "$archive" >&2
    exit 1
  fi

  if unzip -Z1 "$archive" | grep -Fqx "${app_name}.app/Contents/MacOS/${app_name}"; then
    echo "Agent archive must use a wrapper directory so Homebrew preserves ${app_name}.app" >&2
    exit 1
  fi
}

verify_agent_archive \
  "$calendar_agent_zip" \
  "EasyBarCalendarAgent-$version" \
  "EasyBarCalendarAgent"
verify_agent_archive \
  "$network_agent_zip" \
  "EasyBarNetworkAgent-$version" \
  "EasyBarNetworkAgent"

echo "Release package:"
ls -lh "$package_zip"
ls -lh "$calendar_agent_zip"
ls -lh "$network_agent_zip"
echo "Build fingerprints:"
shasum -a 256 "$app_bin"
shasum -a 256 "$plist"
shasum -a 256 "$app_icon_icns"
shasum -a 256 "$calendar_icon_icns"
shasum -a 256 "$network_icon_icns"
shasum -a 256 "$app_resource_dir/Lua/easybar_api.lua"
shasum -a 256 "$app_themes_dir/default.toml"
shasum -a 256 "$package_zip"
shasum -a 256 "$calendar_agent_zip"
shasum -a 256 "$network_agent_zip"
codesign -dv --verbose=4 "$app_bundle" 2>&1 || true
