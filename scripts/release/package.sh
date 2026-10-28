#!/usr/bin/env bash
# Create deterministic release packages.
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

# Print supported command-line arguments.
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

# Exit unless a required command is available.
require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

# Exit unless a required file exists.
require_file() {
  local path="$1"
  local label="$2"

  if [ ! -f "$path" ]; then
    echo "Missing ${label}: ${path}" >&2
    exit 1
  fi
}

# Exit unless a required directory exists.
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

# Remove temporary files created by the script.
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

# Publish all archives as one logical transaction, restoring earlier files on failure.
publish_archives() {
  local staged_archives=(
    "$package_zip_stage"
    "$calendar_agent_zip_stage"
    "$network_agent_zip_stage"
  )
  local published_archives=(
    "$package_zip"
    "$calendar_agent_zip"
    "$network_agent_zip"
  )
  local backups_dir="$stage_root/previous"
  local index
  local target
  local backup
  local rollback_failed=false

  mkdir -p "$backups_dir"

  # Capture every previous archive before replacing any of them.
  for index in "${!published_archives[@]}"; do
    target="${published_archives[$index]}"
    if [ -e "$target" ] || [ -L "$target" ]; then
      cp -p "$target" "$backups_dir/$index"
    fi
  done

  for index in "${!published_archives[@]}"; do
    target="${published_archives[$index]}"
    if mv -f "${staged_archives[$index]}" "$target"; then
      continue
    fi

    echo "Could not publish release archive: $target" >&2
    # Roll back every archive that was successfully replaced.
    for ((index -= 1; index >= 0; index--)); do
      target="${published_archives[$index]}"
      backup="$backups_dir/$index"
      if [ -e "$backup" ]; then
        cp -p "$backup" "$target" || rollback_failed=true
      else
        rm -f "$target" || rollback_failed=true
      fi
    done
    if [ "$rollback_failed" = true ]; then
      echo "Could not completely restore previous release archives" >&2
    fi
    return 1
  done
}

publish_archives

echo "Created $package_zip"
echo "Created $calendar_agent_zip"
echo "Created $network_agent_zip"
