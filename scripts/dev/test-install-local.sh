#!/usr/bin/env bash
# Test local installation and rollback behavior.
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
installer="$script_dir/install-local.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
dist_dir="$tmp_dir/dist"
mkdir -p "$fake_bin"

cat >"$fake_bin/uname" <<'EOF_UNAME'
#!/usr/bin/env sh
echo Darwin
EOF_UNAME

cat >"$fake_bin/ditto" <<'EOF_DITTO'
#!/usr/bin/env bash
set -euo pipefail
source=$1
destination=$2
rm -rf "$destination"
mkdir -p "$(dirname -- "$destination")"

if [ -n "${FAKE_FAIL_DITTO_MARKER:-}" ] && \
  [ -n "${FAKE_FAIL_DITTO_MATCH:-}" ] && \
  [[ "$destination" == *"$FAKE_FAIL_DITTO_MATCH"* ]] && \
  [ ! -e "$FAKE_FAIL_DITTO_MARKER" ]; then
  mkdir -p "$destination"
  : >"$destination/partial-copy"
  : >"$FAKE_FAIL_DITTO_MARKER"
  exit 1
fi

cp -R "$source" "$destination"
EOF_DITTO

cat >"$fake_bin/plutil" <<'EOF_PLUTIL'
#!/usr/bin/env sh
exit 0
EOF_PLUTIL

cat >"$fake_bin/xattr" <<'EOF_XATTR'
#!/usr/bin/env sh
case "${1:-}" in
-p) exit 1 ;;
-lr) exit 0 ;;
*) exit 0 ;;
esac
EOF_XATTR

cat >"$fake_bin/brew" <<'EOF_BREW'
#!/usr/bin/env bash
set -euo pipefail

state_dir=${FAKE_BREW_STATE:-}
log_file=${FAKE_BREW_LOG:-}
command=${1:-}

# Record a command invocation in the test log.
log() {
  if [ -n "$log_file" ]; then
    printf '%s\n' "$*" >>"$log_file"
  fi
}

case "$command" in
list)
  formula=${3:?}
  [ -n "$state_dir" ] && [ -f "$state_dir/$formula.installed" ]
  ;;
services)
  action=${2:?}
  case "$action" in
  list)
    if [ -n "$state_dir" ]; then
      for installed in "$state_dir"/*.installed; do
        [ -e "$installed" ] || continue
        formula=${installed##*/}
        formula=${formula%.installed}
        status=stopped
        if [ -f "$state_dir/$formula.started" ]; then
          status=started
        fi
        printf '%s %s\n' "$formula" "$status"
      done
    fi
    ;;
  start)
    formula=${3:?}
    log "start $formula"
    [ -n "$state_dir" ]
    : >"$state_dir/$formula.started"
    ;;
  stop)
    formula=${3:?}
    log "stop $formula"
    [ -n "$state_dir" ]
    rm -f "$state_dir/$formula.started"
    ;;
  *) exit 2 ;;
  esac
  ;;
*) exit 2 ;;
esac
EOF_BREW

cat >"$fake_bin/launchctl" <<'EOF_LAUNCHCTL'
#!/usr/bin/env bash
set -euo pipefail

state_dir=${FAKE_LAUNCHCTL_STATE:?}
command=${1:?}
mkdir -p "$state_dir"

case "$command" in
print)
  target=${2:?}
  label=${target##*/}
  test -f "$state_dir/$label"
  ;;
bootout)
  target=${2:?}
  label=${target##*/}
  rm -f "$state_dir/$label"
  ;;
bootstrap)
  plist=${3:?}
  label=$(basename -- "$plist" .plist)
  if [ "$label" = "io.github.gi8lino.easybar.local.network-agent" ] && \
    [ -n "${FAKE_FAIL_NETWORK_MARKER:-}" ] && \
    [ ! -e "$FAKE_FAIL_NETWORK_MARKER" ]; then
    : >"$FAKE_FAIL_NETWORK_MARKER"
    exit 1
  fi
  : >"$state_dir/$label"
  ;;
enable | kickstart)
  ;;
*)
  echo "Unexpected launchctl command: $*" >&2
  exit 2
  ;;
esac
EOF_LAUNCHCTL

chmod +x "$fake_bin"/*

# Create an executable test fixture.
write_executable() {
  local path="$1"
  local output="$2"

  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<EOF_EXECUTABLE
#!/usr/bin/env sh
printf '%s\n' '$output'
EOF_EXECUTABLE
  chmod +x "$path"
}

# Create source artifacts used by installation tests.
write_source_artifacts() {
  local version="$1"

  rm -rf "$dist_dir"
  mkdir -p \
    "$dist_dir/EasyBar.app/Contents/MacOS" \
    "$dist_dir/EasyBarCalendarAgent.app/Contents/MacOS" \
    "$dist_dir/EasyBarNetworkAgent.app/Contents/MacOS"

  write_executable "$dist_dir/EasyBar.app/Contents/MacOS/EasyBar" "EasyBar $version"
  write_executable \
    "$dist_dir/EasyBarCalendarAgent.app/Contents/MacOS/EasyBarCalendarAgent" \
    calendar-agent
  write_executable \
    "$dist_dir/EasyBarNetworkAgent.app/Contents/MacOS/EasyBarNetworkAgent" \
    network-agent
  write_executable "$dist_dir/easybar" "easybar $version"

  printf 'new app\n' >"$dist_dir/EasyBar.app/source-marker"
  printf 'new calendar agent\n' >"$dist_dir/EasyBarCalendarAgent.app/source-marker"
  printf 'new network agent\n' >"$dist_dir/EasyBarNetworkAgent.app/source-marker"
}

# Assert that preflight rejects invalid input.
assert_preflight_failure() {
  local expected="$1"
  local output

  if output="$(PATH="$fake_bin:$PATH" "$installer" --dist-dir "$dist_dir" --no-launch 2>&1)"; then
    echo "Expected local installer preflight to fail" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    echo "Unexpected local installer error: $output" >&2
    exit 1
  fi
}

write_source_artifacts 1.2.3
write_executable "$dist_dir/easybar" 'easybar 1.2.4'
assert_preflight_failure "Source app and CLI versions do not match"

write_source_artifacts 1.2.3
write_executable "$dist_dir/EasyBar.app/Contents/MacOS/EasyBar" 'unexpected 1.2.3'
assert_preflight_failure "Unexpected EasyBar version output"

write_source_artifacts 1.2.3
rm -f "$dist_dir/EasyBarNetworkAgent.app/Contents/MacOS/EasyBarNetworkAgent"
assert_preflight_failure "Missing executable network agent"

write_source_artifacts 1.2.3
install_root="$tmp_dir/install"
app_dir="$install_root/Applications"
bin_dir="$install_root/bin"
agent_dir="$install_root/Agents"
launch_agent_dir="$install_root/LaunchAgents"
log_dir="$install_root/Logs"
state_dir="$install_root/State"
launchctl_state="$tmp_dir/launchctl-state"
fail_marker="$tmp_dir/network-bootstrap-failed"
calendar_label="io.github.gi8lino.easybar.local.calendar-agent"
network_label="io.github.gi8lino.easybar.local.network-agent"
calendar_plist="$launch_agent_dir/$calendar_label.plist"
network_plist="$launch_agent_dir/$network_label.plist"
service_state_file="$state_dir/homebrew-services.state"

mkdir -p \
  "$app_dir/EasyBar.app/Contents/MacOS" \
  "$bin_dir" \
  "$agent_dir/EasyBarCalendarAgent.app/Contents/MacOS" \
  "$agent_dir/EasyBarNetworkAgent.app/Contents/MacOS" \
  "$launch_agent_dir" \
  "$log_dir" \
  "$state_dir" \
  "$launchctl_state"

write_executable "$app_dir/EasyBar.app/Contents/MacOS/EasyBar" 'EasyBar 0.9.0'
write_executable \
  "$agent_dir/EasyBarCalendarAgent.app/Contents/MacOS/EasyBarCalendarAgent" \
  old-calendar-agent
write_executable \
  "$agent_dir/EasyBarNetworkAgent.app/Contents/MacOS/EasyBarNetworkAgent" \
  old-network-agent
write_executable "$bin_dir/easybar" 'easybar 0.9.0'
printf 'old app\n' >"$app_dir/EasyBar.app/old-marker"
printf 'old calendar agent\n' >"$agent_dir/EasyBarCalendarAgent.app/old-marker"
printf 'old network agent\n' >"$agent_dir/EasyBarNetworkAgent.app/old-marker"
printf 'old calendar plist\n' >"$calendar_plist"
printf 'old network plist\n' >"$network_plist"
cp "$calendar_plist" "$tmp_dir/calendar.plist.expected"
cp "$network_plist" "$tmp_dir/network.plist.expected"
: >"$launchctl_state/$calendar_label"
: >"$launchctl_state/$network_label"

installer_args=(
  --dist-dir "$dist_dir"
  --app-dir "$app_dir"
  --bin-dir "$bin_dir"
  --agent-dir "$agent_dir"
  --launch-agent-dir "$launch_agent_dir"
  --log-dir "$log_dir"
  --state-dir "$state_dir"
  --no-launch
)

# Assert that rollback restores the previous installation.
assert_previous_installation_restored() {
  [ "$("$app_dir/EasyBar.app/Contents/MacOS/EasyBar" --version)" = "EasyBar 0.9.0" ]
  [ "$("$bin_dir/easybar" --version)" = "easybar 0.9.0" ]
  [ -f "$app_dir/EasyBar.app/old-marker" ]
  [ -f "$agent_dir/EasyBarCalendarAgent.app/old-marker" ]
  [ -f "$agent_dir/EasyBarNetworkAgent.app/old-marker" ]
  [ ! -e "$app_dir/EasyBar.app/source-marker" ]
  [ ! -e "$agent_dir/EasyBarCalendarAgent.app/source-marker" ]
  [ ! -e "$agent_dir/EasyBarNetworkAgent.app/source-marker" ]
  cmp -s "$calendar_plist" "$tmp_dir/calendar.plist.expected"
  cmp -s "$network_plist" "$tmp_dir/network.plist.expected"
  [ -f "$launchctl_state/$calendar_label" ]
  [ -f "$launchctl_state/$network_label" ]
  [ ! -e "$service_state_file" ]

  local leftovers
  leftovers="$(find "$install_root" \
    \( -name '*.local-backup.*' -o -name '*.local-install.*' \) -print)"
  if [ -n "$leftovers" ]; then
    echo "Rollback left temporary installation paths:" >&2
    printf '%s\n' "$leftovers" >&2
    exit 1
  fi
}

if output="$({
  PATH="$fake_bin:$PATH" \
    FAKE_LAUNCHCTL_STATE="$launchctl_state" \
    FAKE_FAIL_NETWORK_MARKER="$fail_marker" \
    "$installer" "${installer_args[@]}"
} 2>&1)"; then
  echo "Expected local installation to fail during network-agent bootstrap" >&2
  exit 1
fi
if [[ "$output" != *"restoring the previous installation"* ]]; then
  echo "Expected rollback message, got: $output" >&2
  exit 1
fi

assert_previous_installation_restored

ditto_fail_marker="$tmp_dir/calendar-copy-failed"
if output="$({
  PATH="$fake_bin:$PATH" \
    FAKE_LAUNCHCTL_STATE="$launchctl_state" \
    FAKE_FAIL_DITTO_MARKER="$ditto_fail_marker" \
    FAKE_FAIL_DITTO_MATCH='.EasyBarCalendarAgent.app.local-install.' \
    "$installer" "${installer_args[@]}"
} 2>&1)"; then
  echo "Expected local installation to fail during calendar-agent copy" >&2
  exit 1
fi
if [[ "$output" != *"restoring the previous installation"* ]]; then
  echo "Expected rollback message after copy failure, got: $output" >&2
  exit 1
fi
assert_previous_installation_restored

PATH="$fake_bin:$PATH" \
  FAKE_LAUNCHCTL_STATE="$launchctl_state" \
  FAKE_FAIL_NETWORK_MARKER="$fail_marker" \
  "$installer" "${installer_args[@]}" >/dev/null

[ "$("$app_dir/EasyBar.app/Contents/MacOS/EasyBar" --version)" = "EasyBar 1.2.3" ]
[ "$("$bin_dir/easybar" --version)" = "easybar 1.2.3" ]
[ -f "$app_dir/EasyBar.app/source-marker" ]
[ -f "$agent_dir/EasyBarCalendarAgent.app/source-marker" ]
[ -f "$agent_dir/EasyBarNetworkAgent.app/source-marker" ]
[ ! -e "$app_dir/EasyBar.app/old-marker" ]
[ ! -e "$agent_dir/EasyBarCalendarAgent.app/old-marker" ]
[ ! -e "$agent_dir/EasyBarNetworkAgent.app/old-marker" ]
[ -f "$launchctl_state/$calendar_label" ]
[ -f "$launchctl_state/$network_label" ]
[ -f "$service_state_file" ]

leftovers="$(find "$install_root" \( -name '*.local-backup.*' -o -name '*.local-install.*' \) -print)"
if [ -n "$leftovers" ]; then
  echo "Successful installation left temporary paths:" >&2
  printf '%s\n' "$leftovers" >&2
  exit 1
fi

# A failed reinstall must restore the services that were active immediately
# before this attempt, not the Homebrew states saved by the first installation.
rm -f "$launchctl_state/$calendar_label" "$launchctl_state/$network_label"
printf 'calendar=started\nnetwork=started\n' >"$service_state_file"
brew_state="$tmp_dir/brew-state"
brew_log="$tmp_dir/brew.log"
reinstall_fail_marker="$tmp_dir/reinstall-network-bootstrap-failed"
mkdir -p "$brew_state"
: >"$brew_state/easybar-calendar-agent.installed"
: >"$brew_state/easybar-network-agent.installed"
: >"$brew_log"

if output="$({
  PATH="$fake_bin:$PATH" \
    FAKE_BREW_STATE="$brew_state" \
    FAKE_BREW_LOG="$brew_log" \
    FAKE_LAUNCHCTL_STATE="$launchctl_state" \
    FAKE_FAIL_NETWORK_MARKER="$reinstall_fail_marker" \
    "$installer" "${installer_args[@]}"
} 2>&1)"; then
  echo "Expected local reinstallation to fail during network-agent bootstrap" >&2
  exit 1
fi
if [[ "$output" != *"restoring the previous installation"* ]]; then
  echo "Expected reinstall rollback message, got: $output" >&2
  exit 1
fi
if [ -s "$brew_log" ]; then
  echo "Reinstall rollback changed Homebrew services that were stopped before the attempt:" >&2
  cat "$brew_log" >&2
  exit 1
fi
[ ! -e "$launchctl_state/$calendar_label" ]
[ ! -e "$launchctl_state/$network_label" ]
[ "$("$app_dir/EasyBar.app/Contents/MacOS/EasyBar" --version)" = "EasyBar 1.2.3" ]
[ "$("$bin_dir/easybar" --version)" = "easybar 1.2.3" ]
grep -Fx 'calendar=started' "$service_state_file" >/dev/null
grep -Fx 'network=started' "$service_state_file" >/dev/null

leftovers="$(find "$install_root" \( -name '*.local-backup.*' -o -name '*.local-install.*' \) -print)"
if [ -n "$leftovers" ]; then
  echo "Reinstall rollback left temporary paths:" >&2
  printf '%s\n' "$leftovers" >&2
  exit 1
fi
