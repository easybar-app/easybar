#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
installer="$script_dir/install-local.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
dist_dir="$tmp_dir/dist"
mkdir -p \
  "$fake_bin" \
  "$dist_dir/EasyBar.app/Contents/MacOS" \
  "$dist_dir/EasyBarCalendarAgent.app/Contents/MacOS" \
  "$dist_dir/EasyBarNetworkAgent.app/Contents/MacOS"

cat >"$fake_bin/uname" <<'EOF_UNAME'
#!/usr/bin/env sh
echo Darwin
EOF_UNAME
chmod +x "$fake_bin/uname"

write_executable() {
  local path="$1"
  local output="$2"

  cat >"$path" <<EOF_EXECUTABLE
#!/usr/bin/env sh
printf '%s\n' '$output'
EOF_EXECUTABLE
  chmod +x "$path"
}

app="$dist_dir/EasyBar.app/Contents/MacOS/EasyBar"
calendar_agent="$dist_dir/EasyBarCalendarAgent.app/Contents/MacOS/EasyBarCalendarAgent"
network_agent="$dist_dir/EasyBarNetworkAgent.app/Contents/MacOS/EasyBarNetworkAgent"
cli="$dist_dir/easybar"
write_executable "$calendar_agent" calendar-agent
write_executable "$network_agent" network-agent

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

write_executable "$app" 'EasyBar 1.2.3'
write_executable "$cli" 'easybar 1.2.4'
assert_preflight_failure "Source app and CLI versions do not match"

write_executable "$app" 'unexpected 1.2.3'
write_executable "$cli" 'easybar 1.2.3'
assert_preflight_failure "Unexpected EasyBar version output"

rm -f "$network_agent"
write_executable "$app" 'EasyBar 1.2.3'
assert_preflight_failure "Missing executable network agent"
