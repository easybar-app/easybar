#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/dev/uninstall-local.sh [options]

Remove the standalone local EasyBar installation created by make install-local.
The Homebrew agent service states recorded by the first local installation are
restored after the local LaunchAgents are removed.

Options:
  --app-dir <dir>           App installation directory. Default: ~/Applications
  --bin-dir <dir>           CLI installation directory. Default: ~/.local/bin
  --agent-dir <dir>         Helper-agent directory. Default: ~/Library/Application Support/EasyBar/Agents
  --launch-agent-dir <dir>  LaunchAgent plist directory. Default: ~/Library/LaunchAgents
  --state-dir <dir>         Local installer state directory. Default: ~/Library/Application Support/EasyBar/LocalInstall
EOF_USAGE
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"

app_dir="${LOCAL_APP_DIR:-$HOME/Applications}"
bin_dir="${LOCAL_BIN_DIR:-$HOME/.local/bin}"
agent_dir="${LOCAL_AGENT_DIR:-$HOME/Library/Application Support/EasyBar/Agents}"
launch_agent_dir="${LOCAL_LAUNCH_AGENT_DIR:-$HOME/Library/LaunchAgents}"
state_dir="${LOCAL_STATE_DIR:-$HOME/Library/Application Support/EasyBar/LocalInstall}"

while [ "$#" -gt 0 ]; do
  case "$1" in
  --app-dir)
    app_dir="${2:?missing value for --app-dir}"
    shift 2
    ;;
  --bin-dir)
    bin_dir="${2:?missing value for --bin-dir}"
    shift 2
    ;;
  --agent-dir)
    agent_dir="${2:?missing value for --agent-dir}"
    shift 2
    ;;
  --launch-agent-dir)
    launch_agent_dir="${2:?missing value for --launch-agent-dir}"
    shift 2
    ;;
  --state-dir)
    state_dir="${2:?missing value for --state-dir}"
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

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Local uninstallation is supported only on macOS." >&2
  exit 1
fi

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

remove_path() {
  local path="$1"
  local parent

  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return
  fi

  parent="$(dirname -- "$path")"
  if [ -w "$parent" ]; then
    rm -rf "$path"
    return
  fi

  require_command sudo
  sudo rm -rf "$path"
}

restore_homebrew_service_state() {
  local formula="$1"
  local desired_state="$2"

  if [ "$desired_state" = not-installed ] || [ -z "$desired_state" ]; then
    return
  fi
  if [ -z "$brew_command" ]; then
    echo "Cannot restore Homebrew service state without brew: $formula" >&2
    return
  fi
  if ! "$brew_command" list --formula "$formula" >/dev/null 2>&1; then
    echo "Homebrew formula is no longer installed; skipping state restore: $formula" >&2
    return
  fi

  case "$desired_state" in
  started)
    echo "Restoring Homebrew service to started: $formula"
    "$brew_command" services start "$formula" >/dev/null
    ;;
  stopped)
    echo "Restoring Homebrew service to stopped: $formula"
    "$brew_command" services stop "$formula" >/dev/null 2>&1 || true
    ;;
  *)
    echo "Invalid stored Homebrew service state for $formula: $desired_state" >&2
    exit 1
    ;;
  esac
}

load_homebrew_state() {
  local key
  local value

  while IFS='=' read -r key value; do
    case "$key" in
    calendar) brew_calendar_previous_state="$value" ;;
    network) brew_network_previous_state="$value" ;;
    esac
  done <"$service_state_file"
}

require_command launchctl

calendar_label="io.github.gi8lino.easybar.local.calendar-agent"
network_label="io.github.gi8lino.easybar.local.network-agent"
user_domain="gui/$(id -u)"

app_destination="${app_dir%/}/EasyBar.app"
calendar_agent_destination="${agent_dir%/}/EasyBarCalendarAgent.app"
network_agent_destination="${agent_dir%/}/EasyBarNetworkAgent.app"
cli_destination="${bin_dir%/}/easybar"
calendar_plist="${launch_agent_dir%/}/${calendar_label}.plist"
network_plist="${launch_agent_dir%/}/${network_label}.plist"
service_state_file="${state_dir%/}/homebrew-services.state"
brew_calendar_previous_state=""
brew_network_previous_state=""

if [ -f "$service_state_file" ]; then
  load_homebrew_state
fi

launchctl bootout "$user_domain/$calendar_label" >/dev/null 2>&1 || true
launchctl bootout "$user_domain/$network_label" >/dev/null 2>&1 || true
bash "$project_root/scripts/dev/stop-local.sh" --dist-dir "$project_root/dist"

remove_path "$calendar_plist"
remove_path "$network_plist"
remove_path "$app_destination"
remove_path "$calendar_agent_destination"
remove_path "$network_agent_destination"
remove_path "$cli_destination"

brew_command="$(command -v brew || true)"
restore_homebrew_service_state easybar-calendar-agent "$brew_calendar_previous_state"
restore_homebrew_service_state easybar-network-agent "$brew_network_previous_state"
remove_path "$service_state_file"

cat <<EOF_SUMMARY
Local EasyBar installation removed.

Removed app:            $app_destination
Removed CLI:            $cli_destination
Removed calendar agent: $calendar_agent_destination
Removed network agent:  $network_agent_destination
EOF_SUMMARY
