#!/usr/bin/env bash
# Verify release archives and metadata.
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"
source "$script_dir/archive-utils.sh"

# Print supported command-line arguments.
usage() {
  echo "Usage: scripts/release/verify-release.sh [--version <version>] [--arch <arm64|x86_64|universal>] [--bundle-id <id>] [--dist-dir <dir>]" >&2
}

version="${VERSION:-dev}"
arch="${ARCH:-universal}"
bundle_id="${BUNDLE_ID:-io.github.gi8lino.easybar}"
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

if ! command -v python3 >/dev/null 2>&1; then
  echo "Required command not found: python3" >&2
  exit 1
fi
if ! python3 "$project_root/scripts/build/stamp.py" bundle-version --version "$version" >/dev/null; then
  exit 2
fi

case "$dist_dir" in
/*) ;;
*) dist_dir="$project_root/$dist_dir" ;;
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

# Exit unless a required file exists.
require_file() {
  local path="$1"
  local label="$2"

  if [ ! -f "$path" ]; then
    echo "Missing ${label}: ${path}" >&2
    exit 1
  fi
}

# Assert that an archive has the expected top-level entries.
assert_archive_roots() {
  local archive="$1"
  shift
  local expected
  local actual

  expected="$(printf '%s\n' "$@" | LC_ALL=C sort -u)"
  actual="$(archive_top_level_entries "$archive")"

  if [ "$actual" != "$expected" ]; then
    echo "Unexpected top-level paths in $archive" >&2
    echo "Expected:" >&2
    printf '%s\n' "$expected" >&2
    echo "Actual:" >&2
    printf '%s\n' "$actual" >&2
    exit 1
  fi
}

"$project_root/scripts/build/verify-bundle.sh" \
  --arch "$arch" \
  --version "$version" \
  --bundle-id "$bundle_id" \
  --dist-dir "$dist_dir"

require_file "$package_zip" "release package"
require_file "$calendar_agent_zip" "calendar agent release package"
require_file "$network_agent_zip" "network agent release package"
require_file "$app_resource_dir/Lua/easybar_api.lua" "Lua API stub"
require_file "$app_resource_dir/Lua/runtime.lua" "Lua runtime"
require_file "$app_resource_dir/Events/event_catalog.json" "event catalog"
require_file "$app_resource_dir/ThemeTokens/theme_tokens.json" "theme token catalog"
require_file "$app_themes_dir/default.toml" "default bundled theme"

if ! archive_contains_exact_entry "$package_zip" "EasyBar.app/Contents/MacOS/EasyBar"; then
  echo "Main release package is missing EasyBar.app" >&2
  exit 1
fi
if ! archive_contains_exact_entry "$package_zip" easybar; then
  echo "Main release package is missing the easybar CLI" >&2
  exit 1
fi
assert_archive_roots "$package_zip" EasyBar.app easybar

# Verify an agent release archive.
verify_agent_archive() {
  local archive="$1"
  local wrapper="$2"
  local app_name="$3"
  local expected_entry="${wrapper}/${app_name}.app/Contents/MacOS/${app_name}"

  if ! archive_contains_exact_entry "$archive" "$expected_entry"; then
    echo "Agent archive does not contain expected Homebrew layout: ${expected_entry}" >&2
    unzip -Z1 "$archive" >&2
    exit 1
  fi

  assert_archive_roots "$archive" "$wrapper"
}

verify_agent_archive \
  "$calendar_agent_zip" \
  "EasyBarCalendarAgent-$version" \
  EasyBarCalendarAgent
verify_agent_archive \
  "$network_agent_zip" \
  "EasyBarNetworkAgent-$version" \
  EasyBarNetworkAgent

echo "Release package:"
ls -lh "$package_zip" "$calendar_agent_zip" "$network_agent_zip"
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
