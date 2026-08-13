#!/usr/bin/env bash
set -euo pipefail

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

app_executable="${app_dir%/}/EasyBar.app/Contents/MacOS/EasyBar"

# Match the installed executable path instead of every process named EasyBar.
pkill -f "$app_executable" >/dev/null 2>&1 || true
