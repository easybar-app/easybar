#!/usr/bin/env bash
# Serialize local launchd agent definitions for the EasyBar installer.
# Caller scripts own shell options, logging, and transaction handling.

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

