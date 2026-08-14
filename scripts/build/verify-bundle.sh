#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

usage() {
  echo "Usage: scripts/build/verify-bundle.sh [--arch <arm64|x86_64|universal>] [--version <version>] [--bundle-id <id>] [--dist-dir <dir>]" >&2
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"
arch="${ARCH:-universal}"
version="${VERSION:-dev}"
bundle_id="${BUNDLE_ID:-io.github.gi8lino.easybar}"
dist_dir="${DIST_DIR:-dist}"

while [ "$#" -gt 0 ]; do
  case "$1" in
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

case "$dist_dir" in
/*) ;;
*) dist_dir="$project_root/$dist_dir" ;;
esac

bundle_version="$(
  python3 "$project_root/scripts/build/stamp.py" bundle-version --version "$version"
)"

app_name="EasyBar"
calendar_agent_name="EasyBarCalendarAgent"
network_agent_name="EasyBarNetworkAgent"
cli_exec="easybar"

app_bundle="$dist_dir/${app_name}.app"
app_contents="$app_bundle/Contents"
app_macos="$app_contents/MacOS"
app_resources="$app_contents/Resources"
app_resource_dir="$app_resources/$app_name"
app_themes_dir="$app_resources/Themes"
app_bin="$app_macos/$app_name"
lua_runtime_bin="$app_macos/EasyBarLuaRuntime"
plist="$app_contents/Info.plist"
app_icon_file="$app_name"
app_icon_icns="$app_resources/${app_icon_file}.icns"

calendar_agent_bundle="$dist_dir/${calendar_agent_name}.app"
calendar_agent_contents="$calendar_agent_bundle/Contents"
calendar_agent_macos="$calendar_agent_contents/MacOS"
calendar_agent_resources="$calendar_agent_contents/Resources"
calendar_agent_bin="$calendar_agent_macos/$calendar_agent_name"
calendar_plist="$calendar_agent_contents/Info.plist"
calendar_icon_file="$calendar_agent_name"
calendar_icon_icns="$calendar_agent_resources/${calendar_icon_file}.icns"

network_agent_bundle="$dist_dir/${network_agent_name}.app"
network_agent_contents="$network_agent_bundle/Contents"
network_agent_macos="$network_agent_contents/MacOS"
network_agent_resources="$network_agent_contents/Resources"
network_agent_bin="$network_agent_macos/$network_agent_name"
network_plist="$network_agent_contents/Info.plist"
network_icon_file="$network_agent_name"
network_icon_icns="$network_agent_resources/${network_icon_file}.icns"

cli_bin="$dist_dir/$cli_exec"

require_file() {
  local path="$1"
  local label="$2"

  if [ ! -f "$path" ]; then
    echo "Missing ${label}: ${path}" >&2
    exit 1
  fi
}

require_dir() {
  local path="$1"
  local label="$2"

  if [ ! -d "$path" ]; then
    echo "Missing ${label}: ${path}" >&2
    exit 1
  fi
}

require_executable() {
  local path="$1"
  local label="$2"

  require_file "$path" "$label"
  if [ ! -x "$path" ]; then
    echo "${label} is not executable: ${path}" >&2
    exit 1
  fi
}

plist_value() {
  local plist_path="$1"
  local key="$2"

  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path"
}

assert_plist_value() {
  local plist_path="$1"
  local key="$2"
  local expected="$3"
  local actual

  actual="$(plist_value "$plist_path" "$key")"
  if [ "$actual" != "$expected" ]; then
    echo "Unexpected $key in $plist_path: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

verify_architecture() {
  local path="$1"
  local label="$2"
  local arches
  local architecture_list=()

  arches="$(lipo -archs "$path")"

  case "$arch" in
  arm64 | x86_64)
    if [ "$arches" != "$arch" ]; then
      echo "Unexpected architecture for ${label}: expected ${arch}, got ${arches}" >&2
      exit 1
    fi
    ;;
  universal)
    read -r -a architecture_list <<<"$arches"
    if [ "${#architecture_list[@]}" -ne 2 ] || \
      [[ " $arches " != *" arm64 "* ]] || \
      [[ " $arches " != *" x86_64 "* ]]; then
      echo "Unexpected universal architectures for ${label}: ${arches}" >&2
      exit 1
    fi
    ;;
  esac
}

require_dir "$app_bundle" "app bundle"
require_dir "$calendar_agent_bundle" "calendar agent bundle"
require_dir "$network_agent_bundle" "network agent bundle"
require_executable "$app_bin" "EasyBar executable"
require_executable "$lua_runtime_bin" "EasyBarLuaRuntime executable"
require_executable "$calendar_agent_bin" "calendar agent executable"
require_executable "$network_agent_bin" "network agent executable"
require_executable "$cli_bin" "easybar CLI"
require_file "$plist" "app Info.plist"
require_file "$calendar_plist" "calendar agent Info.plist"
require_file "$network_plist" "network agent Info.plist"
require_dir "$app_resource_dir" "app resource directory"
require_file "$app_resource_dir/Assets/easybar-menubar.svg" "menu bar icon resource"
require_file "$app_resource_dir/Lua/runtime.lua" "Lua runtime resource"
require_file "$app_resource_dir/Lua/easybar_api.lua" "Lua API stub"
require_dir "$app_resource_dir/Lua/easybar" "Lua easybar module"
require_file "$app_resource_dir/Events/event_catalog.json" "event catalog"
require_file "$app_resource_dir/ThemeTokens/theme_tokens.json" "theme token catalog"
require_dir "$app_themes_dir" "themes directory"
require_file "$app_themes_dir/default.toml" "default theme"
require_file "$app_icon_icns" "app icon"
require_file "$calendar_icon_icns" "calendar agent icon"
require_file "$network_icon_icns" "network agent icon"

if [ -e "$app_contents/Library/LoginItems" ]; then
  echo "Unexpected nested helper app directory: $app_contents/Library/LoginItems" >&2
  exit 1
fi

printf 'Built %s artifacts:\n' "$arch"
file "$app_bin"
file "$lua_runtime_bin"
file "$calendar_agent_bin"
file "$network_agent_bin"
file "$cli_bin"

verify_architecture "$app_bin" "EasyBar"
verify_architecture "$lua_runtime_bin" "EasyBarLuaRuntime"
verify_architecture "$calendar_agent_bin" "EasyBarCalendarAgent"
verify_architecture "$network_agent_bin" "EasyBarNetworkAgent"
verify_architecture "$cli_bin" "easybar CLI"

assert_plist_value "$plist" CFBundleIdentifier "$bundle_id"
assert_plist_value "$plist" CFBundleExecutable "$app_name"
assert_plist_value "$plist" CFBundleName "$app_name"
assert_plist_value "$plist" CFBundleDisplayName "$app_name"
assert_plist_value "$plist" CFBundleIconFile "$app_icon_file"
assert_plist_value "$plist" CFBundleShortVersionString "$bundle_version"
assert_plist_value "$plist" CFBundleVersion "$bundle_version"
assert_plist_value "$plist" LSMinimumSystemVersion 14.0

assert_plist_value "$calendar_plist" CFBundleExecutable "$calendar_agent_name"
assert_plist_value "$calendar_plist" CFBundleName "$calendar_agent_name"
assert_plist_value "$calendar_plist" CFBundleDisplayName "$calendar_agent_name"
assert_plist_value "$calendar_plist" CFBundleIconFile "$calendar_icon_file"
assert_plist_value "$calendar_plist" CFBundleShortVersionString "$bundle_version"
assert_plist_value "$calendar_plist" CFBundleVersion "$bundle_version"

assert_plist_value "$network_plist" CFBundleExecutable "$network_agent_name"
assert_plist_value "$network_plist" CFBundleName "$network_agent_name"
assert_plist_value "$network_plist" CFBundleDisplayName "$network_agent_name"
assert_plist_value "$network_plist" CFBundleIconFile "$network_icon_file"
assert_plist_value "$network_plist" CFBundleShortVersionString "$bundle_version"
assert_plist_value "$network_plist" CFBundleVersion "$bundle_version"

lua_api="$app_resource_dir/Lua/easybar_api.lua"
grep -Fx -- "-- EasyBar Lua API stub version: $version" "$lua_api" >/dev/null
grep -Fx -- "EasyBar.version = \"$version\"" "$lua_api" >/dev/null

app_version_output="$("$app_bin" --version)"
cli_version_output="$("$cli_bin" --version)"
if [ "$app_version_output" != "EasyBar $version" ]; then
  echo "Unexpected EasyBar version output: $app_version_output" >&2
  exit 1
fi
if [ "$cli_version_output" != "easybar $version" ]; then
  echo "Unexpected easybar CLI version output: $cli_version_output" >&2
  exit 1
fi
printf 'Verified binary versions: %s; %s\n' "$app_version_output" "$cli_version_output"

codesign --verify --deep --strict "$app_bundle"
codesign --verify --deep --strict "$calendar_agent_bundle"
codesign --verify --deep --strict "$network_agent_bundle"
codesign --verify --strict "$cli_bin"

echo "Info.plist:"
plutil -p "$plist"
echo "Calendar agent Info.plist:"
plutil -p "$calendar_plist"
echo "Network agent Info.plist:"
plutil -p "$network_plist"
echo "Packaged app root:"
ls -1 "$app_bundle"
echo "Packaged Contents:"
ls -1 "$app_contents"
echo "Packaged Resources:"
ls -1 "$app_resources"
