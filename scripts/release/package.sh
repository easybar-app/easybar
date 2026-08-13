#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "package failed at line $LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/release/package.sh [--version <version>] [--dist-dir <dir>]

Options:
  --version <version>  Package version. Default: VERSION or dev
  --dist-dir <dir>    Distribution directory. Default: DIST_DIR or dist
EOF_USAGE
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"
version="${VERSION:-dev}"
dist_dir="${DIST_DIR:-dist}"

while [ "$#" -gt 0 ]; do
  case "$1" in
  --version)
    version="${2:?missing value for --version}"
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

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

require_command python3
if ! python3 "$project_root/scripts/build/stamp.py" bundle-version --version "$version" >/dev/null; then
  exit 2
fi

case "$dist_dir" in
/*) ;;
*) dist_dir="$project_root/$dist_dir" ;;
esac
if [ ! -d "$dist_dir" ]; then
  echo "Missing distribution directory: $dist_dir" >&2
  exit 1
fi
dist_dir="$(cd -- "$dist_dir" && pwd -P)"

package_zip="$dist_dir/EasyBar-$version.zip"
calendar_agent_zip="$dist_dir/EasyBarCalendarAgent-$version.zip"
network_agent_zip="$dist_dir/EasyBarNetworkAgent-$version.zip"
app_bundle="$dist_dir/EasyBar.app"
calendar_agent_bundle="$dist_dir/EasyBarCalendarAgent.app"
network_agent_bundle="$dist_dir/EasyBarNetworkAgent.app"
cli_bin="$dist_dir/easybar"

require_directory() {
  local path="$1"
  local label="$2"

  if [ ! -d "$path" ]; then
    echo "Missing ${label} directory: ${path}" >&2
    exit 1
  fi
}

require_executable() {
  local path="$1"
  local label="$2"

  if [ ! -f "$path" ] || [ ! -x "$path" ]; then
    echo "Missing executable ${label}: ${path}" >&2
    exit 1
  fi
}

require_command cp
require_command mktemp
require_command mv
require_command zip
require_directory "$app_bundle" "app bundle"
require_directory "$calendar_agent_bundle" "calendar agent bundle"
require_directory "$network_agent_bundle" "network agent bundle"
require_executable "$app_bundle/Contents/MacOS/EasyBar" "EasyBar app"
require_executable \
  "$calendar_agent_bundle/Contents/MacOS/EasyBarCalendarAgent" \
  "calendar agent"
require_executable \
  "$network_agent_bundle/Contents/MacOS/EasyBarNetworkAgent" \
  "network agent"
require_executable "$cli_bin" "EasyBar CLI"

stage_root="$(mktemp -d "$dist_dir/.easybar-package.XXXXXX")"
cleanup() {
  rm -rf "$stage_root"
}
trap cleanup EXIT

package_zip_stage="$stage_root/$(basename -- "$package_zip")"
calendar_agent_zip_stage="$stage_root/$(basename -- "$calendar_agent_zip")"
network_agent_zip_stage="$stage_root/$(basename -- "$network_agent_zip")"

(
  cd "$dist_dir"
  zip -qry -y "$package_zip_stage" EasyBar.app easybar
)

package_agent() {
  local app_bundle="$1"
  local app_name="$2"
  local archive="$3"
  local wrapper="${app_name}-$version"
  local stage="$stage_root/$app_name"

  mkdir -p "$stage/$wrapper"
  cp -R "$app_bundle" "$stage/$wrapper/$app_name.app"
  (
    cd "$stage"
    zip -qry -y "$archive" "$wrapper"
  )
}

package_agent "$calendar_agent_bundle" EasyBarCalendarAgent "$calendar_agent_zip_stage"
package_agent "$network_agent_bundle" EasyBarNetworkAgent "$network_agent_zip_stage"

for archive in \
  "$package_zip_stage" \
  "$calendar_agent_zip_stage" \
  "$network_agent_zip_stage"; do
  if [ ! -s "$archive" ]; then
    echo "Package archive is empty: $archive" >&2
    exit 1
  fi
done

mv -f "$package_zip_stage" "$package_zip"
mv -f "$calendar_agent_zip_stage" "$calendar_agent_zip"
mv -f "$network_agent_zip_stage" "$network_agent_zip"

echo "Created $package_zip"
echo "Created $calendar_agent_zip"
echo "Created $network_agent_zip"
