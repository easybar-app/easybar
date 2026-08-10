#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/dev/install-local.sh [options]

Build artifacts must already exist in dist/. This installer is standalone and
does not require EasyBar or its helper agents to be installed through Homebrew.

Options:
  --dist-dir <dir>          Distribution directory. Default: dist
  --app-dir <dir>           App installation directory. Default: ~/Applications
  --bin-dir <dir>           CLI installation directory. Default: ~/.local/bin
  --agent-dir <dir>         Helper-agent directory. Default: ~/Library/Application Support/EasyBar/Agents
  --launch-agent-dir <dir>  LaunchAgent plist directory. Default: ~/Library/LaunchAgents
  --log-dir <dir>           launchd log directory. Default: ~/Library/Logs/EasyBar
  --state-dir <dir>         Local installer state directory. Default: ~/Library/Application Support/EasyBar/LocalInstall
  --no-launch               Install everything without launching EasyBar.
EOF_USAGE
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"

dist_dir="${DIST_DIR:-dist}"
app_dir="${LOCAL_APP_DIR:-$HOME/Applications}"
bin_dir="${LOCAL_BIN_DIR:-$HOME/.local/bin}"
agent_dir="${LOCAL_AGENT_DIR:-$HOME/Library/Application Support/EasyBar/Agents}"
launch_agent_dir="${LOCAL_LAUNCH_AGENT_DIR:-$HOME/Library/LaunchAgents}"
log_dir="${LOCAL_LOG_DIR:-$HOME/Library/Logs/EasyBar}"
state_dir="${LOCAL_STATE_DIR:-$HOME/Library/Application Support/EasyBar/LocalInstall}"
launch_app=true

while [ "$#" -gt 0 ]; do
  case "$1" in
  --dist-dir)
    dist_dir="${2:?missing value for --dist-dir}"
    shift 2
    ;;
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
  --log-dir)
    log_dir="${2:?missing value for --log-dir}"
    shift 2
    ;;
  --state-dir)
    state_dir="${2:?missing value for --state-dir}"
    shift 2
    ;;
  --no-launch)
    launch_app=false
    shift
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
  echo "Local installation is supported only on macOS." >&2
  exit 1
fi

case "$dist_dir" in
/*) ;;
*) dist_dir="$project_root/$dist_dir" ;;
esac

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

require_path() {
  local path="$1"
  local label="$2"

  if [ ! -e "$path" ]; then
    echo "Missing ${label}: ${path}" >&2
    exit 1
  fi
}

ensure_directory() {
  local directory="$1"

  if [ -d "$directory" ]; then
    return
  fi

  if mkdir -p "$directory" 2>/dev/null; then
    return
  fi

  require_command sudo
  sudo mkdir -p "$directory"
}

replace_bundle() {
  local source="$1"
  local destination="$2"
  local parent
  local stage

  parent="$(dirname -- "$destination")"
  ensure_directory "$parent"
  stage="${parent}/.${destination##*/}.local-install.$$"

  if [ -w "$parent" ]; then
    rm -rf "$stage"
    ditto "$source" "$stage"
    rm -rf "$destination"
    mv "$stage" "$destination"
    return
  fi

  require_command sudo
  sudo rm -rf "$stage"
  sudo ditto "$source" "$stage"
  sudo rm -rf "$destination"
  sudo mv "$stage" "$destination"
}

replace_binary() {
  local source="$1"
  local destination="$2"
  local parent
  local stage

  parent="$(dirname -- "$destination")"
  ensure_directory "$parent"
  stage="${destination}.local-install.$$"

  if [ -w "$parent" ]; then
    cp "$source" "$stage"
    chmod 0755 "$stage"
    mv -f "$stage" "$destination"
    return
  fi

  require_command sudo
  sudo cp "$source" "$stage"
  sudo chmod 0755 "$stage"
  sudo mv -f "$stage" "$destination"
}

xml_escape() {
  local value="$1"

  value=${value//&/\&amp;}
  value=${value//</\&lt;}
  value=${value//>/\&gt;}
  value=${value//\"/\&quot;}
  value=${value//\'/\&apos;}
  printf '%s' "$value"
}

write_launch_agent() {
  local plist="$1"
  local label="$2"
  local executable="$3"
  local stdout_path="$4"
  local stderr_path="$5"
  local stage="${plist}.local-install.$$"
  local escaped_label
  local escaped_executable
  local escaped_home
  local escaped_stdout
  local escaped_stderr

  escaped_label="$(xml_escape "$label")"
  escaped_executable="$(xml_escape "$executable")"
  escaped_home="$(xml_escape "$HOME")"
  escaped_stdout="$(xml_escape "$stdout_path")"
  escaped_stderr="$(xml_escape "$stderr_path")"

  cat >"$stage" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${escaped_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${escaped_executable}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>LANG</key>
    <string>en_US.UTF-8</string>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>${escaped_home}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>StandardOutPath</key>
  <string>${escaped_stdout}</string>
  <key>StandardErrorPath</key>
  <string>${escaped_stderr}</string>
</dict>
</plist>
EOF_PLIST

  chmod 0644 "$stage"
  mv -f "$stage" "$plist"
}

service_target() {
  local label="$1"
  printf 'gui/%s/%s' "$user_id" "$label"
}

bootout_service() {
  local label="$1"

  launchctl bootout "$(service_target "$label")" >/dev/null 2>&1 || true
}

bootstrap_service() {
  local label="$1"
  local plist="$2"
  local target

  target="$(service_target "$label")"
  launchctl bootstrap "$user_domain" "$plist"
  launchctl enable "$target"
  launchctl kickstart -k "$target"
}

homebrew_formula_state() {
  local formula="$1"

  if [ -z "$brew_command" ]; then
    printf '%s' not-installed
    return
  fi
  if ! "$brew_command" list --formula "$formula" >/dev/null 2>&1; then
    printf '%s' not-installed
    return
  fi

  if "$brew_command" services list 2>/dev/null | awk -v formula="$formula" '
    $1 == formula && $2 == "started" { found = 1 }
    END { exit found ? 0 : 1 }
  '; then
    printf '%s' started
  else
    printf '%s' stopped
  fi
}

is_valid_homebrew_state() {
  case "$1" in
  started | stopped | not-installed) return 0 ;;
  *) return 1 ;;
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

  if ! is_valid_homebrew_state "$brew_calendar_previous_state"; then
    echo "Invalid calendar-agent state in $service_state_file" >&2
    exit 1
  fi
  if ! is_valid_homebrew_state "$brew_network_previous_state"; then
    echo "Invalid network-agent state in $service_state_file" >&2
    exit 1
  fi
}

write_homebrew_state() {
  local stage="${service_state_file}.local-install.$$"

  cat >"$stage" <<EOF_STATE
calendar=$brew_calendar_previous_state
network=$brew_network_previous_state
EOF_STATE
  chmod 0600 "$stage"
  mv -f "$stage" "$service_state_file"
}

stop_homebrew_service_if_started() {
  local formula="$1"

  if [ "$(homebrew_formula_state "$formula")" != started ]; then
    return
  fi

  echo "Stopping conflicting Homebrew service: $formula"
  "$brew_command" services stop "$formula" >/dev/null
}

require_command awk
require_command ditto
require_command launchctl
require_command open
require_command xattr

app_source="$dist_dir/EasyBar.app"
calendar_agent_source="$dist_dir/EasyBarCalendarAgent.app"
network_agent_source="$dist_dir/EasyBarNetworkAgent.app"
cli_source="$dist_dir/easybar"

require_path "$app_source" "EasyBar app bundle"
require_path "$calendar_agent_source" "calendar agent bundle"
require_path "$network_agent_source" "network agent bundle"
require_path "$cli_source" "EasyBar CLI"

app_destination="${app_dir%/}/EasyBar.app"
calendar_agent_destination="${agent_dir%/}/EasyBarCalendarAgent.app"
network_agent_destination="${agent_dir%/}/EasyBarNetworkAgent.app"
cli_destination="${bin_dir%/}/easybar"

calendar_label="io.github.gi8lino.easybar.local.calendar-agent"
network_label="io.github.gi8lino.easybar.local.network-agent"
calendar_plist="${launch_agent_dir%/}/${calendar_label}.plist"
network_plist="${launch_agent_dir%/}/${network_label}.plist"
calendar_stdout="${log_dir%/}/calendar-agent.out.log"
calendar_stderr="${log_dir%/}/calendar-agent.err.log"
network_stdout="${log_dir%/}/network-agent.out.log"
network_stderr="${log_dir%/}/network-agent.err.log"
service_state_file="${state_dir%/}/homebrew-services.state"

user_id="$(id -u)"
user_domain="gui/$user_id"
brew_command="$(command -v brew || true)"
brew_calendar_previous_state=""
brew_network_previous_state=""
service_state_file_created=false
installation_complete=false

restore_service_after_failure() {
  local label="$1"
  local plist="$2"
  local executable="$3"
  local formula="$4"
  local previous_state="$5"

  if [ -f "$plist" ] && [ -x "$executable" ]; then
    if bootstrap_service "$label" "$plist" >/dev/null 2>&1; then
      return
    fi
  fi

  if [ "$previous_state" = started ] && [ -n "$brew_command" ]; then
    "$brew_command" services start "$formula" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  local status=$?
  trap - EXIT

  if [ "$status" -ne 0 ] && [ "$installation_complete" = false ]; then
    echo "Local installation failed; restoring previously active agent services" >&2
    restore_service_after_failure \
      "$calendar_label" \
      "$calendar_plist" \
      "$calendar_agent_destination/Contents/MacOS/EasyBarCalendarAgent" \
      easybar-calendar-agent \
      "$brew_calendar_previous_state"
    restore_service_after_failure \
      "$network_label" \
      "$network_plist" \
      "$network_agent_destination/Contents/MacOS/EasyBarNetworkAgent" \
      easybar-network-agent \
      "$brew_network_previous_state"

    if [ "$service_state_file_created" = true ]; then
      rm -f "$service_state_file"
    fi
  fi

  exit "$status"
}
trap cleanup EXIT

ensure_directory "$app_dir"
ensure_directory "$bin_dir"
ensure_directory "$agent_dir"
ensure_directory "$launch_agent_dir"
ensure_directory "$log_dir"
ensure_directory "$state_dir"

if [ ! -w "$launch_agent_dir" ]; then
  echo "LaunchAgent directory must be writable by the current user: $launch_agent_dir" >&2
  exit 1
fi
if [ ! -w "$log_dir" ]; then
  echo "Agent log directory must be writable by the current user: $log_dir" >&2
  exit 1
fi

if [ -f "$service_state_file" ]; then
  load_homebrew_state
else
  brew_calendar_previous_state="$(homebrew_formula_state easybar-calendar-agent)"
  brew_network_previous_state="$(homebrew_formula_state easybar-network-agent)"
  write_homebrew_state
  service_state_file_created=true
fi

stop_homebrew_service_if_started easybar-calendar-agent
stop_homebrew_service_if_started easybar-network-agent

bootout_service "$calendar_label"
bootout_service "$network_label"
bash "$project_root/scripts/dev/stop-local.sh" --dist-dir "$dist_dir"

echo "Installing EasyBar.app into $app_destination"
replace_bundle "$app_source" "$app_destination"

echo "Installing calendar agent into $calendar_agent_destination"
replace_bundle "$calendar_agent_source" "$calendar_agent_destination"

echo "Installing network agent into $network_agent_destination"
replace_bundle "$network_agent_source" "$network_agent_destination"

echo "Installing CLI into $cli_destination"
replace_binary "$cli_source" "$cli_destination"

xattr -dr com.apple.quarantine "$app_destination" >/dev/null 2>&1 || true
xattr -dr com.apple.quarantine "$calendar_agent_destination" >/dev/null 2>&1 || true
xattr -dr com.apple.quarantine "$network_agent_destination" >/dev/null 2>&1 || true
xattr -d com.apple.quarantine "$cli_destination" >/dev/null 2>&1 || true

write_launch_agent \
  "$calendar_plist" \
  "$calendar_label" \
  "$calendar_agent_destination/Contents/MacOS/EasyBarCalendarAgent" \
  "$calendar_stdout" \
  "$calendar_stderr"

write_launch_agent \
  "$network_plist" \
  "$network_label" \
  "$network_agent_destination/Contents/MacOS/EasyBarNetworkAgent" \
  "$network_stdout" \
  "$network_stderr"

echo "Starting local EasyBar agent services"
bootstrap_service "$calendar_label" "$calendar_plist"
bootstrap_service "$network_label" "$network_plist"

launchctl print "$(service_target "$calendar_label")" >/dev/null
launchctl print "$(service_target "$network_label")" >/dev/null

installed_app_version="$("$app_destination/Contents/MacOS/EasyBar" --version)"
installed_cli_version="$("$cli_destination" --version)"
echo "Installed $installed_app_version"
echo "Installed $installed_cli_version"

if [ "$launch_app" = true ]; then
  echo "Launching $app_destination"
  open "$app_destination"
fi

installation_complete=true

cat <<EOF_SUMMARY

Local EasyBar build installed successfully without a Homebrew EasyBar installation.

App:             $app_destination
CLI:             $cli_destination
Calendar agent:  $calendar_agent_destination
Network agent:   $network_agent_destination
LaunchAgents:    $calendar_plist
                 $network_plist

Repeat 'make install-local' after further changes.
EOF_SUMMARY

case ":$PATH:" in
*":$bin_dir:"*) ;;
*)
  cat <<EOF_PATH

The CLI directory is not currently in PATH. Add this to your shell configuration:
  export PATH="$bin_dir:\$PATH"
EOF_PATH
  ;;
esac
