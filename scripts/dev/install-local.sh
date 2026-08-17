#!/usr/bin/env bash
# Install a local development build.
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

# Print supported command-line arguments.
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

# Exit unless a required command is available.
require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
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

# Exit unless a required executable is available.
require_executable() {
  local path="$1"
  local label="$2"

  if [ ! -f "$path" ] || [ ! -x "$path" ]; then
    echo "Missing executable ${label}: ${path}" >&2
    exit 1
  fi
}

# Read and validate an artifact version.
read_artifact_version() {
  local executable="$1"
  local display_name="$2"
  local output
  local version

  if ! output="$("$executable" --version)"; then
    echo "Could not read ${display_name} version from ${executable}" >&2
    exit 1
  fi

  case "$output" in
    "$display_name "*) version=${output#"$display_name "} ;;
    *)
      echo "Unexpected ${display_name} version output: ${output}" >&2
      exit 1
      ;;
  esac
  if [ -z "$version" ]; then
    echo "Empty ${display_name} version output: ${output}" >&2
    exit 1
  fi

  printf '%s\n' "$output"
}

# Create a directory with the expected permissions.
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

# Return whether a path or symlink exists.
path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

# Remove an installed path when present.
remove_installation_path() {
  local path="$1"
  local parent

  if ! path_exists "$path"; then
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

# Move an installation path to a new location.
move_installation_path() {
  local source="$1"
  local destination="$2"
  local parent

  parent="$(dirname -- "$destination")"
  if [ -w "$parent" ]; then
    mv "$source" "$destination"
    return
  fi

  require_command sudo
  sudo mv "$source" "$destination"
}

# Back up an existing installation path.
backup_installation_path() {
  local source="$1"
  local backup="$2"
  local parent

  remove_installation_path "$backup"
  if ! path_exists "$source"; then
    return
  fi

  parent="$(dirname -- "$source")"
  if [ -w "$parent" ]; then
    if [ -d "$source" ] && [ ! -L "$source" ]; then
      ditto "$source" "$backup"
    else
      cp -pP "$source" "$backup"
    fi
    return
  fi

  require_command sudo
  if [ -d "$source" ] && [ ! -L "$source" ]; then
    sudo ditto "$source" "$backup"
  else
    sudo cp -pP "$source" "$backup"
  fi
}

# Restore a backed-up installation path.
restore_installation_path() {
  local destination="$1"
  local backup="$2"

  remove_installation_path "$destination"
  if path_exists "$backup"; then
    move_installation_path "$backup" "$destination"
  fi
}

# Replace the installed application bundle.
replace_bundle() {
  local source="$1"
  local destination="$2"
  local parent
  local stage

  parent="$(dirname -- "$destination")"
  ensure_directory "$parent"
  stage="${parent}/.${destination##*/}.local-install.$$"

  remove_installation_path "$stage"
  if [ -w "$parent" ]; then
    if ! ditto "$source" "$stage" || \
      ! rm -rf "$destination" || \
      ! mv "$stage" "$destination"; then
      remove_installation_path "$stage"
      return 1
    fi
    return
  fi

  require_command sudo
  if ! sudo ditto "$source" "$stage" || \
    ! sudo rm -rf "$destination" || \
    ! sudo mv "$stage" "$destination"; then
    remove_installation_path "$stage"
    return 1
  fi
}

# Replace an installed command-line binary.
replace_binary() {
  local source="$1"
  local destination="$2"
  local parent
  local stage

  parent="$(dirname -- "$destination")"
  ensure_directory "$parent"
  stage="${destination}.local-install.$$"

  remove_installation_path "$stage"
  if [ -w "$parent" ]; then
    if ! cp "$source" "$stage" || \
      ! chmod 0755 "$stage" || \
      ! mv -f "$stage" "$destination"; then
      remove_installation_path "$stage"
      return 1
    fi
    return
  fi

  require_command sudo
  if ! sudo cp "$source" "$stage" || \
    ! sudo chmod 0755 "$stage" || \
    ! sudo mv -f "$stage" "$destination"; then
    remove_installation_path "$stage"
    return 1
  fi
}

# Escape text for XML content.
xml_escape() {
  local value="$1"

  value=${value//&/\&amp;}
  value=${value//</\&lt;}
  value=${value//>/\&gt;}
  value=${value//\"/\&quot;}
  value=${value//\'/\&apos;}
  printf '%s' "$value"
}

# Write the launch agent property list.
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

  if ! cat >"$stage" <<EOF_PLIST
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
  then
    rm -f "$stage"
    return 1
  fi

  if ! plutil -lint "$stage" >/dev/null || \
    ! chmod 0644 "$stage" || \
    ! mv -f "$stage" "$plist"; then
    rm -f "$stage"
    return 1
  fi
}

# Return the launchd target for the local service.
service_target() {
  local label="$1"
  printf 'gui/%s/%s' "$user_id" "$label"
}

# Return whether the local service is loaded.
service_is_loaded() {
  local label="$1"

  launchctl print "$(service_target "$label")" >/dev/null 2>&1
}

# Unload the local service from launchd.
bootout_service() {
  local label="$1"

  launchctl bootout "$(service_target "$label")" >/dev/null 2>&1 || true
}

# Load the local service into launchd.
bootstrap_service() {
  local label="$1"
  local plist="$2"
  local target

  target="$(service_target "$label")"
  launchctl bootstrap "$user_domain" "$plist"
  launchctl enable "$target"
  launchctl kickstart -k "$target"
}

# Read the current Homebrew formula state.
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

# Return whether stored Homebrew state is valid.
is_valid_homebrew_state() {
  case "$1" in
  started | stopped | not-installed) return 0 ;;
  *) return 1 ;;
  esac
}

# Load saved Homebrew service state.
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

# Persist Homebrew service state.
write_homebrew_state() {
  local stage="${service_state_file}.local-install.$$"

  if ! cat >"$stage" <<EOF_STATE
calendar=$brew_calendar_previous_state
network=$brew_network_previous_state
EOF_STATE
  then
    rm -f "$stage"
    return 1
  fi

  if ! chmod 0600 "$stage" || ! mv -f "$stage" "$service_state_file"; then
    rm -f "$stage"
    return 1
  fi
}

# Stop a Homebrew service before local installation.
stop_homebrew_service_if_started() {
  local formula="$1"
  local state="$2"

  if [ "$state" != started ]; then
    return
  fi

  echo "Stopping conflicting Homebrew service: $formula"
  "$brew_command" services stop "$formula" >/dev/null
}

app_source="$dist_dir/EasyBar.app"
calendar_agent_source="$dist_dir/EasyBarCalendarAgent.app"
network_agent_source="$dist_dir/EasyBarNetworkAgent.app"
cli_source="$dist_dir/easybar"
app_source_executable="$app_source/Contents/MacOS/EasyBar"
calendar_agent_source_executable="$calendar_agent_source/Contents/MacOS/EasyBarCalendarAgent"
network_agent_source_executable="$network_agent_source/Contents/MacOS/EasyBarNetworkAgent"

require_directory "$app_source" "EasyBar app bundle"
require_directory "$calendar_agent_source" "calendar agent bundle"
require_directory "$network_agent_source" "network agent bundle"
require_executable "$app_source_executable" "EasyBar app"
require_executable "$calendar_agent_source_executable" "calendar agent"
require_executable "$network_agent_source_executable" "network agent"
require_executable "$cli_source" "EasyBar CLI"

source_app_version_output="$(read_artifact_version "$app_source_executable" EasyBar)"
source_cli_version_output="$(read_artifact_version "$cli_source" easybar)"
if [ "${source_app_version_output#EasyBar }" != "${source_cli_version_output#easybar }" ]; then
  echo "Source app and CLI versions do not match: ${source_app_version_output}; ${source_cli_version_output}" >&2
  exit 1
fi

require_command awk
require_command ditto
require_command grep
require_command launchctl
require_command xattr
if [ "$launch_app" = true ]; then
  require_command open
fi
require_command plutil

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
backup_suffix=".local-backup.$$"
app_backup="${app_destination}${backup_suffix}"
calendar_agent_backup="${calendar_agent_destination}${backup_suffix}"
network_agent_backup="${network_agent_destination}${backup_suffix}"
cli_backup="${cli_destination}${backup_suffix}"
calendar_plist_backup="${calendar_plist}${backup_suffix}"
network_plist_backup="${network_plist}${backup_suffix}"

# Back up all paths replaced by installation.
backup_installation_paths() {
  backup_installation_path "$app_destination" "$app_backup"
  backup_installation_path "$calendar_agent_destination" "$calendar_agent_backup"
  backup_installation_path "$network_agent_destination" "$network_agent_backup"
  backup_installation_path "$cli_destination" "$cli_backup"
  backup_installation_path "$calendar_plist" "$calendar_plist_backup"
  backup_installation_path "$network_plist" "$network_plist_backup"
}

# Restore all backed-up installation paths.
restore_installation_paths() {
  local failed=false

  restore_installation_path "$calendar_plist" "$calendar_plist_backup" || failed=true
  restore_installation_path "$network_plist" "$network_plist_backup" || failed=true
  restore_installation_path "$app_destination" "$app_backup" || failed=true
  restore_installation_path "$calendar_agent_destination" "$calendar_agent_backup" || failed=true
  restore_installation_path "$network_agent_destination" "$network_agent_backup" || failed=true
  restore_installation_path "$cli_destination" "$cli_backup" || failed=true

  [ "$failed" = false ]
}

# Remove installation backups after success.
discard_installation_backups() {
  local failed=false

  remove_installation_path "$app_backup" || failed=true
  remove_installation_path "$calendar_agent_backup" || failed=true
  remove_installation_path "$network_agent_backup" || failed=true
  remove_installation_path "$cli_backup" || failed=true
  remove_installation_path "$calendar_plist_backup" || failed=true
  remove_installation_path "$network_plist_backup" || failed=true

  [ "$failed" = false ]
}

user_id="$(id -u)"
user_domain="gui/$user_id"
brew_command="$(command -v brew || true)"
brew_calendar_previous_state=""
brew_network_previous_state=""
brew_calendar_state_before_install="$(homebrew_formula_state easybar-calendar-agent)"
brew_network_state_before_install="$(homebrew_formula_state easybar-network-agent)"
calendar_local_service_was_loaded=false
network_local_service_was_loaded=false
service_state_file_created=false
backups_ready=false
artifacts_modified=false
services_modified=false
installation_complete=false

if service_is_loaded "$calendar_label"; then
  calendar_local_service_was_loaded=true
fi
if service_is_loaded "$network_label"; then
  network_local_service_was_loaded=true
fi

# Restore service state after a failed installation.
restore_service_after_failure() {
  local label="$1"
  local plist="$2"
  local executable="$3"
  local formula="$4"
  local homebrew_state_before_install="$5"
  local local_service_was_loaded="$6"
  local failed=false

  # Remove any partially bootstrapped replacement before restoring prior state.
  bootout_service "$label"

  if [ "$local_service_was_loaded" = true ]; then
    if [ ! -f "$plist" ] || [ ! -x "$executable" ] || \
      ! bootstrap_service "$label" "$plist" >/dev/null 2>&1; then
      echo "Could not restore local service: $label" >&2
      failed=true
    fi
  fi

  if [ "$homebrew_state_before_install" = started ]; then
    if [ -z "$brew_command" ] || \
      ! "$brew_command" services start "$formula" >/dev/null 2>&1; then
      echo "Could not restore Homebrew service: $formula" >&2
      failed=true
    fi
  fi

  [ "$failed" = false ]
}

# Remove temporary files created by the script.
cleanup() {
  local status=$?
  local restore_failed=false
  trap - EXIT
  set +e

  if [ "$status" -ne 0 ] && [ "$installation_complete" = false ]; then
    echo "Local installation failed; restoring the previous installation" >&2

    if [ "$artifacts_modified" = true ] && [ "$backups_ready" = true ]; then
      restore_installation_paths || restore_failed=true
    else
      discard_installation_backups || restore_failed=true
    fi

    if [ "$services_modified" = true ]; then
      restore_service_after_failure \
        "$calendar_label" \
        "$calendar_plist" \
        "$calendar_agent_destination/Contents/MacOS/EasyBarCalendarAgent" \
        easybar-calendar-agent \
        "$brew_calendar_state_before_install" \
        "$calendar_local_service_was_loaded" || restore_failed=true
      restore_service_after_failure \
        "$network_label" \
        "$network_plist" \
        "$network_agent_destination/Contents/MacOS/EasyBarNetworkAgent" \
        easybar-network-agent \
        "$brew_network_state_before_install" \
        "$network_local_service_was_loaded" || restore_failed=true
    fi

    if [ "$service_state_file_created" = true ]; then
      rm -f "$service_state_file" || restore_failed=true
    fi

    if [ "$restore_failed" = true ]; then
      echo "One or more previous installation resources could not be restored" >&2
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
if [ ! -w "$state_dir" ]; then
  echo "Local installer state directory must be writable by the current user: $state_dir" >&2
  exit 1
fi

backup_installation_paths
backups_ready=true

if [ -f "$service_state_file" ]; then
  load_homebrew_state
else
  brew_calendar_previous_state="$brew_calendar_state_before_install"
  brew_network_previous_state="$brew_network_state_before_install"
  write_homebrew_state
  service_state_file_created=true
fi

services_modified=true
stop_homebrew_service_if_started \
  easybar-calendar-agent \
  "$brew_calendar_state_before_install"
stop_homebrew_service_if_started \
  easybar-network-agent \
  "$brew_network_state_before_install"

bootout_service "$calendar_label"
bootout_service "$network_label"
"$project_root/scripts/dev/stop-app.sh" --app-dir "$app_dir"

artifacts_modified=true
echo "Installing EasyBar.app into $app_destination"
replace_bundle "$app_source" "$app_destination"

echo "Installing calendar agent into $calendar_agent_destination"
replace_bundle "$calendar_agent_source" "$calendar_agent_destination"

echo "Installing network agent into $network_agent_destination"
replace_bundle "$network_agent_source" "$network_agent_destination"

echo "Installing CLI into $cli_destination"
replace_binary "$cli_source" "$cli_destination"

# Clear quarantine attributes from a directory tree.
clear_quarantine_recursive() {
  local path="$1"
  local label="$2"

  xattr -dr com.apple.quarantine "$path" >/dev/null 2>&1 || true

  if xattr -lr "$path" 2>/dev/null | grep -Fq "com.apple.quarantine"; then
    echo "Failed to remove quarantine from ${label}: ${path}" >&2
    exit 1
  fi
}

# Clear quarantine attributes from a file.
clear_quarantine_file() {
  local path="$1"
  local label="$2"

  xattr -d com.apple.quarantine "$path" >/dev/null 2>&1 || true

  if xattr -p com.apple.quarantine "$path" >/dev/null 2>&1; then
    echo "Failed to remove quarantine from ${label}: ${path}" >&2
    exit 1
  fi
}

echo "Removing quarantine from local EasyBar artifacts"
clear_quarantine_recursive "$app_destination" "EasyBar.app"
clear_quarantine_recursive "$calendar_agent_destination" "calendar agent"
clear_quarantine_recursive "$network_agent_destination" "network agent"
clear_quarantine_file "$cli_destination" "EasyBar CLI"

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
if [ "$installed_app_version" != "$source_app_version_output" ] || \
  [ "$installed_cli_version" != "$source_cli_version_output" ]; then
  echo "Installed artifact versions changed during installation: $installed_app_version; $installed_cli_version" >&2
  exit 1
fi
echo "Installed $installed_app_version"
echo "Installed $installed_cli_version"

if [ "$launch_app" = true ]; then
  echo "Launching $app_destination"
  open "$app_destination"
fi

installation_complete=true
if ! discard_installation_backups; then
  echo "Warning: one or more local installation backups could not be removed" >&2
fi
backups_ready=false

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
