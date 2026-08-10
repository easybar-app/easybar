#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/dev/stop-local.sh [--dist-dir DIR]" >&2
}

dist_dir="${DIST_DIR:-dist}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dist-dir)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --dist-dir" >&2
        exit 2
      fi
      dist_dir="$2"
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

app_exec="EasyBar"
calendar_agent_exec="EasyBarCalendarAgent"
network_agent_exec="EasyBarNetworkAgent"
app_bundle="$dist_dir/EasyBar.app"
calendar_agent_bundle="$dist_dir/EasyBarCalendarAgent.app"
network_agent_bundle="$dist_dir/EasyBarNetworkAgent.app"

pkill -x "$app_exec" >/dev/null 2>&1 || true
pkill -x "$calendar_agent_exec" >/dev/null 2>&1 || true
pkill -x "$network_agent_exec" >/dev/null 2>&1 || true
pkill -f "$app_bundle/Contents/MacOS/$app_exec" >/dev/null 2>&1 || true
pkill -f "$calendar_agent_bundle/Contents/MacOS/$calendar_agent_exec" >/dev/null 2>&1 || true
pkill -f "$network_agent_bundle/Contents/MacOS/$network_agent_exec" >/dev/null 2>&1 || true
