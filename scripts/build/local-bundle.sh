#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "local bundle failed at line $LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/build/local-bundle.sh [options]

Options:
  --kit-root <dir>       EasyBarKit checkout. Default: ../easybar-kit
  --arch <arch>          arm64 or x86_64. Default: current machine architecture
  --version <version>    Version stamped into EasyBar.app. Default: dev
  --bundle-id <id>       EasyBar bundle identifier. Default: com.gi8lino.EasyBar
  --dist-dir <dir>       Distribution directory. Default: dist
EOF_USAGE
}

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
kit_root="${EASYBAR_KIT_ROOT:-${project_root}/../easybar-kit}"
arch="${LOCAL_INSTALL_ARCH:-$(uname -m)}"
version="${VERSION:-dev}"
bundle_id="${BUNDLE_ID:-com.gi8lino.EasyBar}"
dist_dir="${DIST_DIR:-dist}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kit-root)
      kit_root="${2:?missing value for --kit-root}"
      shift 2
      ;;
    --arch)
      arch="${2:?missing value for --arch}"
      shift 2
      ;;
    --version)
      version="${2:?missing value for --version}"
      shift 2
      ;;
    --bundle-id)
      bundle_id="${2:?missing value for --bundle-id}"
      shift 2
      ;;
    --dist-dir)
      dist_dir="${2:?missing value for --dist-dir}"
      shift 2
      ;;
    -h|--help)
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
  arm64|x86_64) ;;
  *)
    echo "Unsupported local install architecture '$arch'. Use arm64 or x86_64." >&2
    exit 2
    ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Local app bundling is supported only on macOS." >&2
  exit 1
fi

if [ ! -f "$kit_root/Package.swift" ]; then
  echo "EasyBarKit checkout not found: $kit_root" >&2
  echo "Keep easybar and easybar-kit as sibling directories or set EASYBAR_KIT_ROOT." >&2
  exit 1
fi

case "$dist_dir" in
  /*) ;;
  *) dist_dir="$project_root/$dist_dir" ;;
esac

require_command() {
  local command_name="$1"
  local hint="${2:-}"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    if [ -n "$hint" ]; then
      echo "$hint" >&2
    fi
    exit 1
  fi
}

require_file() {
  local path="$1"
  local label="$2"
  if [ ! -f "$path" ]; then
    echo "Missing $label: $path" >&2
    exit 1
  fi
}

require_dir() {
  local path="$1"
  local label="$2"
  if [ ! -d "$path" ]; then
    echo "Missing $label: $path" >&2
    exit 1
  fi
}

require_command swift
require_command codesign
require_command rsvg-convert "Install librsvg with: brew install librsvg"
require_command magick "Install ImageMagick with: brew install imagemagick"
require_command sips
require_command iconutil

rm -rf "$dist_dir"
mkdir -p "$dist_dir"

app_name="EasyBar"
app_bundle="$dist_dir/${app_name}.app"
app_contents="$app_bundle/Contents"
app_macos="$app_contents/MacOS"
app_resources="$app_contents/Resources"
app_resource_dir="$app_resources/EasyBar"
app_themes_dir="$app_resources/Themes"
app_bin="$app_macos/EasyBar"
lua_runtime_bin="$app_macos/EasyBarLuaRuntime"
app_plist="$app_contents/Info.plist"
app_icon_icns="$app_resources/EasyBar.icns"

calendar_name="EasyBarCalendarAgent"
calendar_bundle="$dist_dir/${calendar_name}.app"
calendar_contents="$calendar_bundle/Contents"
calendar_macos="$calendar_contents/MacOS"
calendar_resources="$calendar_contents/Resources"
calendar_bin="$calendar_macos/$calendar_name"
calendar_plist="$calendar_contents/Info.plist"
calendar_icon_icns="$calendar_resources/${calendar_name}.icns"

network_name="EasyBarNetworkAgent"
network_bundle="$dist_dir/${network_name}.app"
network_contents="$network_bundle/Contents"
network_macos="$network_contents/MacOS"
network_resources="$network_contents/Resources"
network_bin="$network_macos/$network_name"
network_plist="$network_contents/Info.plist"
network_icon_icns="$network_resources/${network_name}.icns"

cli_bin="$dist_dir/easybar"

mkdir -p \
  "$app_macos" \
  "$app_resource_dir/Lua" \
  "$app_resource_dir/Events" \
  "$app_resource_dir/ThemeTokens" \
  "$app_resource_dir/Assets" \
  "$app_themes_dir" \
  "$calendar_macos" \
  "$calendar_resources" \
  "$network_macos" \
  "$network_resources"

echo "Building EasyBar frontend ($arch)"
(
  cd "$project_root"
  swift build -c release --arch "$arch" --product EasyBar
)
app_build_dir="$(cd "$project_root" && swift build -c release --arch "$arch" --show-bin-path)"
require_file "$app_build_dir/EasyBar" "EasyBar executable"
cp "$app_build_dir/EasyBar" "$app_bin"

echo "Building EasyBarKit support products ($arch)"
for product in EasyBarLuaRuntime EasyBarCtl EasyBarCalendarAgent EasyBarNetworkAgent; do
  swift build --package-path "$kit_root" -c release --arch "$arch" --product "$product"
done
kit_build_dir="$(swift build --package-path "$kit_root" -c release --arch "$arch" --show-bin-path)"

require_file "$kit_build_dir/EasyBarLuaRuntime" "EasyBarLuaRuntime executable"
require_file "$kit_build_dir/EasyBarCtl" "EasyBarCtl executable"
require_file "$kit_build_dir/EasyBarCalendarAgent" "calendar agent executable"
require_file "$kit_build_dir/EasyBarNetworkAgent" "network agent executable"

cp "$kit_build_dir/EasyBarLuaRuntime" "$lua_runtime_bin"
cp "$kit_build_dir/EasyBarCtl" "$cli_bin"
cp "$kit_build_dir/EasyBarCalendarAgent" "$calendar_bin"
cp "$kit_build_dir/EasyBarNetworkAgent" "$network_bin"

echo "Staging EasyBarKit runtime resources"
require_file "$kit_root/Sources/EasyBarKit/Lua/runtime.lua" "runtime.lua"
require_file "$kit_root/Sources/EasyBarKit/Lua/easybar_api.lua" "Lua API stub"
require_dir "$kit_root/Sources/EasyBarKit/Lua/easybar" "Lua easybar module"
require_file "$kit_root/Sources/EasyBarKit/Events/event_catalog.json" "event catalog"
require_file "$kit_root/Sources/EasyBarKit/Theme/theme_tokens.json" "theme token catalog"
require_file "$kit_root/Sources/EasyBarKit/Assets/easybar-menubar.svg" "menu bar icon"
require_dir "$kit_root/themes" "themes directory"

cp "$kit_root/Sources/EasyBarKit/Lua/runtime.lua" "$app_resource_dir/Lua/runtime.lua"
cp "$kit_root/Sources/EasyBarKit/Lua/easybar_api.lua" "$app_resource_dir/Lua/easybar_api.lua"
cp -R "$kit_root/Sources/EasyBarKit/Lua/easybar" "$app_resource_dir/Lua/easybar"
cp "$kit_root/Sources/EasyBarKit/Events/event_catalog.json" "$app_resource_dir/Events/event_catalog.json"
cp "$kit_root/Sources/EasyBarKit/Theme/theme_tokens.json" "$app_resource_dir/ThemeTokens/theme_tokens.json"
cp "$kit_root/Sources/EasyBarKit/Assets/easybar-menubar.svg" "$app_resource_dir/Assets/easybar-menubar.svg"
cp -R "$kit_root/themes/." "$app_themes_dir/"

python3 "$project_root/scripts/build/stamp.py" lua-api \
  --file "$app_resource_dir/Lua/easybar_api.lua" \
  --version "$version"

echo "Staging bundle metadata"
require_file "$project_root/Sources/EasyBarApp/Info.plist" "EasyBar Info.plist"
require_file "$kit_root/Sources/EasyBarCalendarAgent/Info.plist" "calendar agent Info.plist"
require_file "$kit_root/Sources/EasyBarNetworkAgent/Info.plist" "network agent Info.plist"

cp "$project_root/Sources/EasyBarApp/Info.plist" "$app_plist"
cp "$kit_root/Sources/EasyBarCalendarAgent/Info.plist" "$calendar_plist"
cp "$kit_root/Sources/EasyBarNetworkAgent/Info.plist" "$network_plist"

python3 "$project_root/scripts/build/stamp.py" plist \
  --plist "$app_plist" \
  --bundle-id "$bundle_id" \
  --version "$version" \
  --executable EasyBar \
  --name EasyBar \
  --icon-file EasyBar

python3 "$project_root/scripts/build/stamp.py" plist \
  --plist "$calendar_plist" \
  --version "$version" \
  --executable "$calendar_name" \
  --name "$calendar_name" \
  --icon-file "$calendar_name"

python3 "$project_root/scripts/build/stamp.py" plist \
  --plist "$network_plist" \
  --version "$version" \
  --executable "$network_name" \
  --name "$network_name" \
  --icon-file "$network_name"

echo "Generating local bundle icons"
"$project_root/scripts/assets/app_icons.sh" \
  rsvg-convert \
  magick \
  "$dist_dir" \
  "$project_root/packaging/easybar-icon.svg:$app_icon_icns" \
  "$kit_root/packaging/easybar-calendar-agent-icon.svg:$calendar_icon_icns" \
  "$kit_root/packaging/easybar-network-agent-icon.svg:$network_icon_icns"

chmod +x "$app_bin" "$lua_runtime_bin" "$cli_bin" "$calendar_bin" "$network_bin"

echo "Ad-hoc signing local artifacts"
codesign --force --deep --sign - "$calendar_bundle"
codesign --force --deep --sign - "$network_bundle"
codesign --force --deep --sign - "$app_bundle"
codesign --force --sign - "$cli_bin"

touch "$calendar_bundle" "$network_bundle" "$app_bundle"

require_file "$app_resource_dir/Lua/runtime.lua" "staged runtime.lua"
require_file "$app_resource_dir/Lua/easybar_api.lua" "staged Lua API stub"
require_file "$app_resource_dir/Events/event_catalog.json" "staged event catalog"
require_file "$app_resource_dir/ThemeTokens/theme_tokens.json" "staged theme tokens"
require_file "$app_themes_dir/default.toml" "default theme"
require_file "$app_icon_icns" "EasyBar icon"
require_file "$calendar_icon_icns" "calendar agent icon"
require_file "$network_icon_icns" "network agent icon"

printf '\nLocal bundle ready:\n'
printf '  App:             %s\n' "$app_bundle"
printf '  CLI:             %s\n' "$cli_bin"
printf '  Calendar agent:  %s\n' "$calendar_bundle"
printf '  Network agent:   %s\n' "$network_bundle"
