#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
uninstaller="$script_dir/uninstall-local.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
install_root="$tmp_dir/install"
app_dir="$install_root/Applications"
bin_dir="$install_root/bin"
agent_dir="$install_root/Agents"
launch_agent_dir="$install_root/LaunchAgents"
state_dir="$install_root/State"
command_log="$tmp_dir/commands.log"
mkdir -p "$fake_bin"

cat >"$fake_bin/uname" <<'EOF_UNAME'
#!/usr/bin/env sh
echo Darwin
EOF_UNAME

cat >"$fake_bin/launchctl" <<'EOF_LAUNCHCTL'
#!/usr/bin/env sh
printf 'launchctl %s\n' "$*" >>"$FAKE_COMMAND_LOG"
EOF_LAUNCHCTL

cat >"$fake_bin/pkill" <<'EOF_PKILL'
#!/usr/bin/env sh
printf 'pkill %s\n' "$*" >>"$FAKE_COMMAND_LOG"
EOF_PKILL

chmod +x "$fake_bin"/*

calendar_label="io.github.gi8lino.easybar.local.calendar-agent"
network_label="io.github.gi8lino.easybar.local.network-agent"
calendar_plist="$launch_agent_dir/$calendar_label.plist"
network_plist="$launch_agent_dir/$network_label.plist"
service_state_file="$state_dir/homebrew-services.state"

mkdir -p \
  "$app_dir/EasyBar.app" \
  "$bin_dir" \
  "$agent_dir/EasyBarCalendarAgent.app" \
  "$agent_dir/EasyBarNetworkAgent.app" \
  "$launch_agent_dir" \
  "$state_dir"
touch \
  "$bin_dir/easybar" \
  "$calendar_plist" \
  "$network_plist"
cat >"$service_state_file" <<'EOF_STATE'
calendar=started
network=not-installed
EOF_STATE

uninstaller_args=(
  --app-dir "$app_dir"
  --bin-dir "$bin_dir"
  --agent-dir "$agent_dir"
  --launch-agent-dir "$launch_agent_dir"
  --state-dir "$state_dir"
)

if output="$({
  PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_COMMAND_LOG="$command_log" \
    "$uninstaller" "${uninstaller_args[@]}"
} 2>&1)"; then
  echo "Expected uninstallation without brew to fail" >&2
  exit 1
fi
if [[ "$output" != *"brew is unavailable"* ]]; then
  echo "Unexpected missing-brew error: $output" >&2
  exit 1
fi

[ -d "$app_dir/EasyBar.app" ]
[ -e "$bin_dir/easybar" ]
[ -d "$agent_dir/EasyBarCalendarAgent.app" ]
[ -d "$agent_dir/EasyBarNetworkAgent.app" ]
[ -e "$calendar_plist" ]
[ -e "$network_plist" ]
[ -e "$service_state_file" ]
[ ! -e "$command_log" ]

cat >"$fake_bin/brew" <<'EOF_BREW'
#!/usr/bin/env sh
printf 'brew %s\n' "$*" >>"$FAKE_COMMAND_LOG"
case "${1:-}" in
list)
  [ "${3:-}" = easybar-calendar-agent ]
  ;;
services)
  exit 0
  ;;
*)
  exit 0
  ;;
esac
EOF_BREW
chmod +x "$fake_bin/brew"

PATH="$fake_bin:/usr/bin:/bin" \
  FAKE_COMMAND_LOG="$command_log" \
  "$uninstaller" "${uninstaller_args[@]}" >/dev/null

[ ! -e "$app_dir/EasyBar.app" ]
[ ! -e "$bin_dir/easybar" ]
[ ! -e "$agent_dir/EasyBarCalendarAgent.app" ]
[ ! -e "$agent_dir/EasyBarNetworkAgent.app" ]
[ ! -e "$calendar_plist" ]
[ ! -e "$network_plist" ]
[ ! -e "$service_state_file" ]
grep -Fx 'brew services start easybar-calendar-agent' "$command_log" >/dev/null
if grep -Fq 'easybar-network-agent' "$command_log"; then
  echo "Network Homebrew service should not be restored when it was not installed" >&2
  exit 1
fi
