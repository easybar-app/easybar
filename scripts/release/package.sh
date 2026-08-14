#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

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

require_file() {
  local path="$1"
  local label="$2"

  if [ ! -f "$path" ]; then
    echo "Missing ${label}: ${path}" >&2
    exit 1
  fi
}

require_directory() {
  local path="$1"
  local label="$2"

  if [ ! -d "$path" ]; then
    echo "Missing ${label}: ${path}" >&2
    exit 1
  fi
}

require_command python3
require_command cp
require_command mktemp
require_command mv
require_command unzip
require_command zip

if ! python3 "$project_root/scripts/build/stamp.py" \
  bundle-version \
  --version "$version" >/dev/null; then
  exit 2
fi

case "$dist_dir" in
/*) ;;
*) dist_dir="$project_root/$dist_dir" ;;
esac

require_directory "$dist_dir" "distribution"

dist_dir="$(cd -- "$dist_dir" && pwd -P)"

package_zip="$dist_dir/EasyBar-$version.zip"
calendar_agent_zip="$dist_dir/EasyBarCalendarAgent-$version.zip"
network_agent_zip="$dist_dir/EasyBarNetworkAgent-$version.zip"

app_bundle="$dist_dir/EasyBar.app"
calendar_agent_bundle="$dist_dir/EasyBarCalendarAgent.app"
network_agent_bundle="$dist_dir/EasyBarNetworkAgent.app"
cli_bin="$dist_dir/easybar"

require_directory "$app_bundle" "app bundle"
require_directory "$calendar_agent_bundle" "calendar agent bundle"
require_directory "$network_agent_bundle" "network agent bundle"
require_file "$cli_bin" "CLI binary"

stage_root="$(mktemp -d "$dist_dir/.easybar-package.XXXXXX")"
package_stage="$stage_root/main"
calendar_agent_stage="$stage_root/calendar-agent"
network_agent_stage="$stage_root/network-agent"

package_zip_stage="$stage_root/EasyBar-$version.zip"
calendar_agent_zip_stage="$stage_root/EasyBarCalendarAgent-$version.zip"
network_agent_zip_stage="$stage_root/EasyBarNetworkAgent-$version.zip"

cleanup() {
  rm -rf "$stage_root"
}
trap cleanup EXIT

mkdir -p \
  "$package_stage" \
  "$calendar_agent_stage" \
  "$network_agent_stage"

# Do not copy Finder/resource-fork metadata into release staging.
COPYFILE_DISABLE=1 cp -R "$app_bundle" "$package_stage/EasyBar.app"
COPYFILE_DISABLE=1 cp "$cli_bin" "$package_stage/easybar"

calendar_agent_wrapper="EasyBarCalendarAgent-$version"
network_agent_wrapper="EasyBarNetworkAgent-$version"

mkdir -p \
  "$calendar_agent_stage/$calendar_agent_wrapper" \
  "$network_agent_stage/$network_agent_wrapper"

COPYFILE_DISABLE=1 cp -R \
  "$calendar_agent_bundle" \
  "$calendar_agent_stage/$calendar_agent_wrapper/EasyBarCalendarAgent.app"

COPYFILE_DISABLE=1 cp -R \
  "$network_agent_bundle" \
  "$network_agent_stage/$network_agent_wrapper/EasyBarNetworkAgent.app"

# -X strips platform-specific extra file attributes from the ZIP.
(
  cd "$package_stage"
  COPYFILE_DISABLE=1 zip -Xqry "$package_zip_stage" \
    "EasyBar.app" \
    "easybar"
)

(
  cd "$calendar_agent_stage"
  COPYFILE_DISABLE=1 zip -Xqry \
    "$calendar_agent_zip_stage" \
    "$calendar_agent_wrapper"
)

(
  cd "$network_agent_stage"
  COPYFILE_DISABLE=1 zip -Xqry \
    "$network_agent_zip_stage" \
    "$network_agent_wrapper"
)

for archive in \
  "$package_zip_stage" \
  "$calendar_agent_zip_stage" \
  "$network_agent_zip_stage"; do
  if [ ! -s "$archive" ]; then
    echo "Package archive is empty: $archive" >&2
    exit 1
  fi

  if ! unzip -tqq "$archive"; then
    echo "Package archive failed integrity validation: $archive" >&2
    exit 1
  fi
done

mv -f "$package_zip_stage" "$package_zip"
mv -f "$calendar_agent_zip_stage" "$calendar_agent_zip"
mv -f "$network_agent_zip_stage" "$network_agent_zip"

echo "Created $package_zip"
echo "Created $calendar_agent_zip"
echo "Created $network_agent_zip"
