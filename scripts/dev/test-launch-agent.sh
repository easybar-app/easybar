#!/usr/bin/env bash
# Test launchd plist serialization without requiring macOS tools.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/launch-agent.sh"

# Keep test inputs isolated from the user's launch-agent directory.
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Validate generated XML using Python's plist parser in place of macOS plutil.
mkdir -p "$work_dir/bin"
cat >"$work_dir/bin/plutil" <<'EOF_PLUTIL'
#!/usr/bin/env bash
set -euo pipefail
python3 - "$2" <<'PY_PLIST'
import plistlib
import sys
with open(sys.argv[1], 'rb') as handle:
    plistlib.load(handle)
PY_PLIST
EOF_PLUTIL
chmod +x "$work_dir/bin/plutil"

# Assert that XML escaping preserves special characters without changing values.
plist="$work_dir/calendar.plist"
label='io.easybar.test&<agent>'
executable="$work_dir/App & <Helper>.app/bin/agent"
stdout_path="$work_dir/out&<file>.log"
stderr_path="$work_dir/err&<file>.log"
PATH="$work_dir/bin:$PATH" write_launch_agent \
  "$plist" "$label" "$executable" "$stdout_path" "$stderr_path"

python3 - "$plist" "$label" "$executable" "$stdout_path" "$stderr_path" <<'PY_CHECK'
import plistlib
import sys

with open(sys.argv[1], 'rb') as handle:
    content = plistlib.load(handle)
assert content['Label'] == sys.argv[2]
assert content['ProgramArguments'] == [sys.argv[3]]
assert content['StandardOutPath'] == sys.argv[4]
assert content['StandardErrorPath'] == sys.argv[5]
assert content['RunAtLoad'] is True
PY_CHECK
