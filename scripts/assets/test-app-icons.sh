#!/usr/bin/env bash
# Test application icon generation and validation.
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script="$script_dir/app_icons.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Assert that invalid input is rejected.
assert_rejected() {
  local expected="$1"
  shift
  local output

  if output="$("$script" missing-svg-tool missing-image-tool dist "$@" 2>&1)"; then
    echo "Expected invalid icon arguments to fail: $*" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    echo "Unexpected validation error for $*: $output" >&2
    exit 1
  fi
}

if output="$("$script" missing-svg-tool missing-image-tool '' icon.svg:EasyBar.icns 2>&1)"; then
  echo "Expected an empty icon staging directory to fail" >&2
  exit 1
fi
if [[ "$output" != *"must not be empty"* ]]; then
  echo "Unexpected empty staging-directory error: $output" >&2
  exit 1
fi

if output="$("$script" missing-svg-tool missing-image-tool / icon.svg:EasyBar.icns 2>&1)"; then
  echo "Expected the filesystem root icon staging directory to fail" >&2
  exit 1
fi
if [[ "$output" != *"must not be the filesystem root"* ]]; then
  echo "Unexpected root staging-directory error: $output" >&2
  exit 1
fi

assert_rejected "expected SVG:ICNS" icon.svg
assert_rejected "paths must not be empty" :EasyBar.icns
assert_rejected "paths must not be empty" icon.svg:
assert_rejected ".icns extension" icon.svg:EasyBar.png
assert_rejected "must be different paths" EasyBar.icns:EasyBar.icns
mkdir "$tmp_dir/EasyBar.icns"
assert_rejected "must not be a directory" "icon.svg:$tmp_dir/EasyBar.icns"

# A successful render must not remove another process's similarly named paths.
fake_bin="$tmp_dir/bin"
icon_dist="$tmp_dir/icons"
mkdir -p "$fake_bin" "$icon_dist/.EasyBar.iconset" "$icon_dist/.EasyBar.render"
printf 'keep\n' >"$icon_dist/.EasyBar.iconset/marker"
printf 'keep\n' >"$icon_dist/.EasyBar.render/marker"
printf '<svg/>\n' >"$tmp_dir/icon.svg"

cat >"$fake_bin/svg-render" <<'EOF_SVG'
#!/usr/bin/env bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then
    printf 'rendered\n' >"$2"
    exit 0
  fi
  shift
done
exit 2
EOF_SVG

cat >"$fake_bin/image-convert" <<'EOF_IMAGE'
#!/usr/bin/env sh
printf '0.5\n'
EOF_IMAGE

cat >"$fake_bin/sips" <<'EOF_SIPS'
#!/usr/bin/env bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  if [ "$1" = --out ]; then
    printf 'resized\n' >"$2"
    exit 0
  fi
  shift
done
exit 2
EOF_SIPS

cat >"$fake_bin/iconutil" <<'EOF_ICONUTIL'
#!/usr/bin/env bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then
    printf 'icon\n' >"$2"
    exit 0
  fi
  shift
done
exit 2
EOF_ICONUTIL
chmod +x "$fake_bin"/*

PATH="$fake_bin:$PATH" "$script" \
  "$fake_bin/svg-render" \
  "$fake_bin/image-convert" \
  "$icon_dist" \
  "$tmp_dir/icon.svg:$icon_dist/EasyBar.icns"

grep -Fx keep "$icon_dist/.EasyBar.iconset/marker" >/dev/null
grep -Fx keep "$icon_dist/.EasyBar.render/marker" >/dev/null
grep -Fx icon "$icon_dist/EasyBar.icns" >/dev/null
if find "$icon_dist" -name '.easybar-icon.*' -print | grep -q .; then
  echo "Icon generation left temporary files behind" >&2
  exit 1
fi
