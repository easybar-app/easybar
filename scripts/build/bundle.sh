#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "bundle failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# Prints supported bundle options to standard error.
usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/build/bundle.sh [options]

Options:
  --kit-root <dir>       Use this EasyBarKit checkout instead of the resolved package dependency.
  --arch <arch>          arm64, x86_64, or universal. Default: universal
  --version <version>    Version stamped into all artifacts. Default: dev
  --bundle-id <id>       EasyBar bundle identifier. Default: io.github.gi8lino.easybar
  --dist-dir <dir>       Distribution directory. Default: dist
EOF_USAGE
}

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
kit_root="${EASYBAR_KIT_ROOT:-}"
arch="${ARCH:-universal}"
version="${VERSION:-dev}"
bundle_id="${BUNDLE_ID:-io.github.gi8lino.easybar}"
dist_dir="${DIST_DIR:-dist}"

while [ "$#" -gt 0 ]; do
  case "$1" in
  --kit-root)
    kit_root="${2:?missing value for --kit-root}"
    shift 2
    ;;
  --arch)
    arch="${2:?missing value for --arch}"
    shift 2
    ;;
  --version)
    version="${2:?missing value for --version}"
    shift 2
    ;;
  --bundle-id)
    bundle_id="${2:?missing value for --bundle-id}"
    shift 2
    ;;
  --dist-dir)
    dist_dir="${2:?missing value for --dist-dir}"
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

case "$arch" in
arm64 | x86_64 | universal) ;;
*)
  echo "Unsupported architecture '$arch'. Use arm64, x86_64, or universal." >&2
  exit 2
  ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
  echo "EasyBar app bundling is supported only on macOS." >&2
  exit 1
fi

# Exits with an installation hint when a required executable is unavailable.
require_command() {
  local command_name="$1"
  local hint="${2:-}"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    if [ -n "$hint" ]; then
      echo "$hint" >&2
    fi
    exit 1
  fi
}

# Exits when a required regular file is missing.
require_file() {
  local path="$1"
  local label="$2"

  if [ ! -f "$path" ]; then
    echo "Missing $label: $path" >&2
    exit 1
  fi
}

# Exits when a required directory is missing.
require_dir() {
  local path="$1"
  local label="$2"

  if [ ! -d "$path" ]; then
    echo "Missing $label: $path" >&2
    exit 1
  fi
}

# Copies one resource into the bundle with deterministic writable permissions.
stage_writable_file() {
  local source="$1"
  local destination="$2"

  install -m 0644 "$source" "$destination"
}

# Returns an absolute path with existing symlinks resolved.
canonical_path() {
  python3 - "$1" <<'PY_PATH'
import os
import sys

print(os.path.realpath(sys.argv[1]))
PY_PATH
}

require_command swift
require_command git
require_command install
require_command codesign
require_command lipo
require_command rsvg-convert "Install librsvg with: brew install librsvg"
require_command magick "Install ImageMagick with: brew install imagemagick"
require_command sips
require_command iconutil
require_command mktemp
require_command python3

# Reject malformed versions before resolving dependencies or changing distribution output.
python3 "$project_root/scripts/build/stamp.py" bundle-version --version "$version" >/dev/null

case "$dist_dir" in
/*) ;;
*) dist_dir="$project_root/$dist_dir" ;;
esac
if [ -L "$dist_dir" ]; then
  echo "Distribution directory must not be a symbolic link: $dist_dir" >&2
  exit 2
fi
dist_dir="$(canonical_path "$dist_dir")"

if [ "$dist_dir" = / ]; then
  echo "Distribution directory must not be the filesystem root" >&2
  exit 2
fi

case "$project_root" in
"$dist_dir" | "$dist_dir"/*)
  echo "Distribution directory must not be the project root or one of its parents: $dist_dir" >&2
  exit 2
  ;;
esac

case "$dist_dir" in
"$project_root/.git" | "$project_root/.git"/*)
  echo "Distribution directory must not be inside Git metadata: $dist_dir" >&2
  exit 2
  ;;
esac

case "$dist_dir" in
"$project_root"/*)
  relative_dist_dir=${dist_dir#"$project_root/"}
  if [ -n "$(git -C "$project_root" ls-files -- ":(literal)$relative_dist_dir")" ]; then
    echo "Distribution directory contains tracked project files: $dist_dir" >&2
    exit 2
  fi
  ;;
esac

# Resolves the EasyBarKit checkout selected by SwiftPM.
resolve_easybar_kit_dependency_path() {
  (
    cd "$project_root"
    swift package show-dependencies --format json
  ) | python3 -c 'import json, os, sys
root = json.load(sys.stdin)
stack = [root]
while stack:
    item = stack.pop()
    if item.get("identity") == "easybar-kit":
        print(os.path.realpath(item["path"]))
        raise SystemExit(0)
    stack.extend(item.get("dependencies", []))
raise SystemExit("easybar-kit dependency not found")'
}

final_dist_dir="$dist_dir"
root_package_path="$project_root"
local_package_path="${LOCAL_PACKAGE_DIR:-$project_root/.build/local-package}"
dist_stage=""
dist_backup=""
build_version_file=""
build_version_file_existed=false
build_version_state_active=false
previous_build_version=""

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

# Restores the EasyBarKit version file changed for this build.
restore_build_version() {
  if [ "$build_version_state_active" = false ]; then
    return
  fi

  if [ "$build_version_file_existed" = true ]; then
    printf '%s\n' "$previous_build_version" >"$build_version_file" || return
  else
    rm -f "$build_version_file" || return
  fi

  build_version_state_active=false
}

# Removes incomplete staging and restores any distribution moved during publication.
cleanup() {
  local status=$?
  trap - EXIT
  set +e

  if ! restore_build_version; then
    echo "Failed to restore EasyBarKit build-version state" >&2
    status=1
  fi

  if [ -n "$dist_stage" ]; then
    rm -rf "$dist_stage" || status=1
  fi

  if [ -n "$dist_backup" ]; then
    if path_exists "$final_dist_dir"; then
      rm -rf "$dist_backup" || status=1
    else
      mv "$dist_backup" "$final_dist_dir" || status=1
    fi
  fi

  exit "$status"
}
trap cleanup EXIT

# Replaces the previous distribution only after the staged build is complete.
publish_distribution() {
  local dist_parent
  local dist_name

  dist_parent="$(dirname -- "$final_dist_dir")"
  dist_name="$(basename -- "$final_dist_dir")"

  if path_exists "$final_dist_dir"; then
    dist_backup="$(mktemp -d "$dist_parent/.${dist_name}.previous.XXXXXX")"
    rmdir "$dist_backup"
    mv "$final_dist_dir" "$dist_backup"
  fi

  if ! mv "$dist_stage" "$final_dist_dir"; then
    if [ -n "$dist_backup" ]; then
      mv "$dist_backup" "$final_dist_dir"
      dist_backup=""
    fi
    return 1
  fi
  dist_stage=""

  if [ -n "$dist_backup" ]; then
    rm -rf "$dist_backup"
    dist_backup=""
  fi
}

if [ -n "$kit_root" ]; then
  if [ ! -f "$kit_root/Package.swift" ]; then
    echo "EasyBarKit checkout not found: $kit_root" >&2
    exit 1
  fi
  kit_root="$(cd -- "$kit_root" && pwd -P)"
  export EASYBAR_KIT_ROOT="$kit_root"
  root_package_path="$local_package_path"
  "$project_root/scripts/build/prepare-local-package.sh" \
    --project-root "$project_root" \
    --output "$root_package_path"
  root_package_path="$(cd -- "$root_package_path" && pwd -P)"
  echo "Using local EasyBarKit checkout: $kit_root"
else
  unset EASYBAR_KIT_ROOT
  kit_root="$(resolve_easybar_kit_dependency_path)"
fi

build_version_file="$kit_root/.build/easybar-build-version"
if [ -f "$build_version_file" ]; then
  build_version_file_existed=true
  previous_build_version="$(<"$build_version_file")"
fi
mkdir -p "$(dirname "$build_version_file")"
build_version_state_active=true
printf '%s\n' "$version" >"$build_version_file"

dist_parent="$(dirname -- "$final_dist_dir")"
dist_name="$(basename -- "$final_dist_dir")"
mkdir -p "$dist_parent"
dist_stage="$(mktemp -d "$dist_parent/.${dist_name}.build.XXXXXX")"
dist_dir="$dist_stage"

app_name="EasyBar"
app_bundle="$dist_dir/${app_name}.app"
app_contents="$app_bundle/Contents"
app_macos="$app_contents/MacOS"
app_resources="$app_contents/Resources"
app_resource_dir="$app_resources/EasyBar"
app_themes_dir="$app_resources/Themes"
app_bin="$app_macos/EasyBar"
lua_runtime_bin="$app_macos/EasyBarLuaRuntime"
app_plist="$app_contents/Info.plist"
app_icon_icns="$app_resources/EasyBar.icns"

calendar_name="EasyBarCalendarAgent"
calendar_bundle="$dist_dir/${calendar_name}.app"
calendar_contents="$calendar_bundle/Contents"
calendar_macos="$calendar_contents/MacOS"
calendar_resources="$calendar_contents/Resources"
calendar_bin="$calendar_macos/$calendar_name"
calendar_plist="$calendar_contents/Info.plist"
calendar_icon_icns="$calendar_resources/${calendar_name}.icns"

network_name="EasyBarNetworkAgent"
network_bundle="$dist_dir/${network_name}.app"
network_contents="$network_bundle/Contents"
network_macos="$network_contents/MacOS"
network_resources="$network_contents/Resources"
network_bin="$network_macos/$network_name"
network_plist="$network_contents/Info.plist"
network_icon_icns="$network_resources/${network_name}.icns"

cli_bin="$dist_dir/easybar"

mkdir -p \
  "$app_macos" \
  "$app_resource_dir/Lua" \
  "$app_resource_dir/Events" \
  "$app_resource_dir/ThemeTokens" \
  "$app_resource_dir/Assets" \
  "$app_themes_dir" \
  "$calendar_macos" \
  "$calendar_resources" \
  "$network_macos" \
  "$network_resources"

# Builds one frontend product for an architecture and returns its binary path.
root_product_path() {
  local build_arch="$1"
  local product="$2"
  local bin_dir

  swift build \
    --package-path "$root_package_path" \
    -c release \
    --arch "$build_arch" \
    --product "$product" >&2
  bin_dir="$(
    swift build \
      --package-path "$root_package_path" \
      -c release \
      --arch "$build_arch" \
      --show-bin-path
  )"
  printf '%s/%s\n' "$bin_dir" "$product"
}

# Builds one EasyBarKit product for an architecture and returns its binary path.
kit_product_path() {
  local build_arch="$1"
  local product="$2"
  local bin_dir

  swift build --package-path "$kit_root" -c release --arch "$build_arch" --product "$product" >&2
  bin_dir="$(swift build --package-path "$kit_root" -c release --arch "$build_arch" --show-bin-path)"
  printf '%s/%s\n' "$bin_dir" "$product"
}

# Copies one architecture-specific product into its final bundle location.
stage_product() {
  local owner="$1"
  local product="$2"
  local destination="$3"
  local arm64_path
  local x86_64_path
  local source_path

  echo "Building $product ($arch)"

  if [ "$arch" = universal ]; then
    if [ "$owner" = root ]; then
      arm64_path="$(root_product_path arm64 "$product")"
      x86_64_path="$(root_product_path x86_64 "$product")"
    else
      arm64_path="$(kit_product_path arm64 "$product")"
      x86_64_path="$(kit_product_path x86_64 "$product")"
    fi

    require_file "$arm64_path" "$product arm64 executable"
    require_file "$x86_64_path" "$product x86_64 executable"
    lipo -create "$arm64_path" "$x86_64_path" -output "$destination"
  else
    if [ "$owner" = root ]; then
      source_path="$(root_product_path "$arch" "$product")"
    else
      source_path="$(kit_product_path "$arch" "$product")"
    fi

    require_file "$source_path" "$product executable"
    cp "$source_path" "$destination"
  fi

  require_file "$destination" "staged $product executable"
}

stage_product root EasyBar "$app_bin"
stage_product kit EasyBarLuaRuntime "$lua_runtime_bin"
stage_product kit EasyBarCtl "$cli_bin"
stage_product kit EasyBarCalendarAgent "$calendar_bin"
stage_product kit EasyBarNetworkAgent "$network_bin"

app_version_output="$("$app_bin" --version)"
cli_version_output="$("$cli_bin" --version)"
if [ "$app_version_output" != "EasyBar $version" ]; then
  echo "EasyBar binary version mismatch: expected 'EasyBar $version', got '$app_version_output'" >&2
  exit 1
fi
if [ "$cli_version_output" != "easybar $version" ]; then
  echo "EasyBar CLI version mismatch: expected 'easybar $version', got '$cli_version_output'" >&2
  exit 1
fi
echo "Verified binary versions: $app_version_output; $cli_version_output"

echo "Staging EasyBarKit runtime resources"
require_file "$kit_root/Sources/EasyBarKit/Lua/runtime.lua" "runtime.lua"
require_file "$kit_root/Sources/EasyBarKit/Lua/easybar_api.lua" "Lua API stub"
require_dir "$kit_root/Sources/EasyBarKit/Lua/easybar" "Lua easybar module"
require_file "$kit_root/Sources/EasyBarKit/Events/event_catalog.json" "event catalog"
require_file "$kit_root/Sources/EasyBarKit/Theme/theme_tokens.json" "theme token catalog"
require_file "$kit_root/Sources/EasyBarKit/Assets/easybar-menubar.svg" "menu bar icon"
require_dir "$kit_root/themes" "themes directory"

stage_writable_file "$kit_root/Sources/EasyBarKit/Lua/runtime.lua" "$app_resource_dir/Lua/runtime.lua"
stage_writable_file "$kit_root/Sources/EasyBarKit/Lua/easybar_api.lua" "$app_resource_dir/Lua/easybar_api.lua"
cp -R "$kit_root/Sources/EasyBarKit/Lua/easybar" "$app_resource_dir/Lua/easybar"
stage_writable_file "$kit_root/Sources/EasyBarKit/Events/event_catalog.json" "$app_resource_dir/Events/event_catalog.json"
stage_writable_file "$kit_root/Sources/EasyBarKit/Theme/theme_tokens.json" "$app_resource_dir/ThemeTokens/theme_tokens.json"
stage_writable_file "$kit_root/Sources/EasyBarKit/Assets/easybar-menubar.svg" "$app_resource_dir/Assets/easybar-menubar.svg"
cp -R "$kit_root/themes/." "$app_themes_dir/"

python3 "$project_root/scripts/build/stamp.py" lua-api \
  --file "$app_resource_dir/Lua/easybar_api.lua" \
  --version "$version"

echo "Staging bundle metadata"
require_file "$project_root/Sources/EasyBarApp/Info.plist" "EasyBar Info.plist"
require_file "$kit_root/Sources/EasyBarCalendarAgent/Info.plist" "calendar agent Info.plist"
require_file "$kit_root/Sources/EasyBarNetworkAgent/Info.plist" "network agent Info.plist"

stage_writable_file "$project_root/Sources/EasyBarApp/Info.plist" "$app_plist"
stage_writable_file "$kit_root/Sources/EasyBarCalendarAgent/Info.plist" "$calendar_plist"
stage_writable_file "$kit_root/Sources/EasyBarNetworkAgent/Info.plist" "$network_plist"

python3 "$project_root/scripts/build/stamp.py" plist \
  --plist "$app_plist" \
  --bundle-id "$bundle_id" \
  --version "$version" \
  --executable EasyBar \
  --name EasyBar \
  --icon-file EasyBar

python3 "$project_root/scripts/build/stamp.py" plist \
  --plist "$calendar_plist" \
  --version "$version" \
  --executable "$calendar_name" \
  --name "$calendar_name" \
  --icon-file "$calendar_name"

python3 "$project_root/scripts/build/stamp.py" plist \
  --plist "$network_plist" \
  --version "$version" \
  --executable "$network_name" \
  --name "$network_name" \
  --icon-file "$network_name"

echo "Generating bundle icons"
"$project_root/scripts/assets/app_icons.sh" \
  rsvg-convert \
  magick \
  "$dist_dir" \
  "$project_root/packaging/easybar-icon.svg:$app_icon_icns" \
  "$kit_root/packaging/easybar-calendar-agent-icon.svg:$calendar_icon_icns" \
  "$kit_root/packaging/easybar-network-agent-icon.svg:$network_icon_icns"

chmod +x "$app_bin" "$lua_runtime_bin" "$cli_bin" "$calendar_bin" "$network_bin"

echo "Ad-hoc signing artifacts"
codesign --force --deep --sign - "$calendar_bundle"
codesign --force --deep --sign - "$network_bundle"
codesign --force --deep --sign - "$app_bundle"
codesign --force --sign - "$cli_bin"

require_file "$app_resource_dir/Lua/runtime.lua" "staged runtime.lua"
require_file "$app_resource_dir/Lua/easybar_api.lua" "staged Lua API stub"
require_file "$app_resource_dir/Events/event_catalog.json" "staged event catalog"
require_file "$app_resource_dir/ThemeTokens/theme_tokens.json" "staged theme tokens"
require_file "$app_themes_dir/default.toml" "default theme"
require_file "$app_icon_icns" "EasyBar icon"
require_file "$calendar_icon_icns" "calendar agent icon"
require_file "$network_icon_icns" "network agent icon"

restore_build_version
publish_distribution

printf '\nBundle ready:\n'
printf '  App:             %s/EasyBar.app\n' "$final_dist_dir"
printf '  CLI:             %s/easybar\n' "$final_dist_dir"
printf '  Calendar agent:  %s/EasyBarCalendarAgent.app\n' "$final_dist_dir"
printf '  Network agent:   %s/EasyBarNetworkAgent.app\n' "$final_dist_dir"
