#!/usr/bin/env bash
# Stop running EasyBar application processes.
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

# Print supported command-line arguments.
usage() {
  echo "Usage: scripts/dev/stop-app.sh [--app-dir DIR]" >&2
}

app_dir="${LOCAL_APP_DIR:-$HOME/Applications}"

while [ "$#" -gt 0 ]; do
  case "$1" in
  --app-dir)
    app_dir="${2:?missing value for --app-dir}"
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

# Escape text for an extended regular expression.
escape_extended_regex() {
  sed 's/[][\\.^$*+?(){}|]/\\&/g'
}

app_executable="${app_dir%/}/EasyBar.app/Contents/MacOS/EasyBar"
app_pattern="^$(printf '%s' "$app_executable" | escape_extended_regex)([[:space:]]|$)"

# Match the complete installed executable path, including paths with regex metacharacters.
pkill -f "$app_pattern" >/dev/null 2>&1 || true
