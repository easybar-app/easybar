#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --tap-dir DIR --version VERSION --sha SHA --calendar-agent-sha SHA --network-agent-sha SHA [--repository OWNER/REPO]" >&2
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/metadata.sh"

tap_dir=""
repository="${GITHUB_REPOSITORY:-easybar-app/easybar}"
version=""
sha=""
calendar_agent_sha=""
network_agent_sha=""

while [ "$#" -gt 0 ]; do
  case "$1" in
  --tap-dir)
    tap_dir="${2:?missing value for --tap-dir}"
    shift 2
    ;;
  --repository)
    repository="${2:?missing value for --repository}"
    shift 2
    ;;
  --version)
    version="${2:?missing value for --version}"
    shift 2
    ;;
  --sha)
    sha="${2:?missing value for --sha}"
    shift 2
    ;;
  --calendar-agent-sha)
    calendar_agent_sha="${2:?missing value for --calendar-agent-sha}"
    shift 2
    ;;
  --network-agent-sha)
    network_agent_sha="${2:?missing value for --network-agent-sha}"
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

if [ -z "$tap_dir" ] || [ -z "$version" ] || [ -z "$sha" ] || \
  [ -z "$calendar_agent_sha" ] || [ -z "$network_agent_sha" ]; then
  usage
  exit 2
fi

if ! git -C "$tap_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Homebrew tap is not a Git working tree: $tap_dir" >&2
  exit 1
fi
if ! is_valid_github_repository "$repository"; then
  echo "Invalid GitHub repository: $repository" >&2
  exit 2
fi
if ! is_valid_release_version "$version"; then
  echo "Invalid release version: $version" >&2
  exit 2
fi
if ! is_valid_sha256 "$sha"; then
  echo "Invalid EasyBar SHA-256: $sha" >&2
  exit 2
fi
if ! is_valid_sha256 "$calendar_agent_sha"; then
  echo "Invalid calendar agent SHA-256: $calendar_agent_sha" >&2
  exit 2
fi
if ! is_valid_sha256 "$network_agent_sha"; then
  echo "Invalid network agent SHA-256: $network_agent_sha" >&2
  exit 2
fi

tag="v${version}"
cask_dir="$tap_dir/Casks"
formula_dir="$tap_dir/Formula"
easybar_cask_file="$cask_dir/easybar.rb"
calendar_agent_formula_file="$formula_dir/easybar-calendar-agent.rb"
network_agent_formula_file="$formula_dir/easybar-network-agent.rb"
asset_url="https://github.com/${repository}/releases/download/${tag}/EasyBar-${version}.zip"

mkdir -p "$cask_dir" "$formula_dir"

easybar_cask_temp="${easybar_cask_file}.tmp.$$"
calendar_agent_formula_temp="${calendar_agent_formula_file}.tmp.$$"
network_agent_formula_temp="${network_agent_formula_file}.tmp.$$"
cleanup() {
  rm -f \
    "$easybar_cask_temp" \
    "$calendar_agent_formula_temp" \
    "$network_agent_formula_temp"
}
trap cleanup EXIT

cat >"$easybar_cask_temp" <<EOF_CASK
cask "easybar" do
  version "${version}"
  sha256 "${sha}"

  url "${asset_url}"
  name "EasyBar"
  desc "Scriptable status bar with SwiftUI and Lua widgets"
  homepage "https://easybar.dev/"

  depends_on formula: [
    "easybar-calendar-agent",
    "easybar-network-agent",
    "lua",
  ]
  depends_on macos: :sonoma

  app "EasyBar.app"
  binary "easybar"

  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-d", "com.apple.quarantine", "{{staged_path}}/easybar"],
        must_succeed: false
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/EasyBar.app"],
        must_succeed: false
    run "{{HOMEBREW_BREW_FILE}}",
        args: ["services", "restart", "easybar-calendar-agent"]
    run "{{HOMEBREW_BREW_FILE}}",
        args: ["services", "restart", "easybar-network-agent"]
  end

  uninstall_preflight_steps do
    run "{{HOMEBREW_BREW_FILE}}",
        args: ["services", "stop", "easybar-calendar-agent"]
    run "{{HOMEBREW_BREW_FILE}}",
        args: ["services", "stop", "easybar-network-agent"]
  end

  zap trash: [
    "~/.config/easybar",
    "~/.local/state/easybar",
  ]
end
EOF_CASK

write_agent_formula() {
  local file="$1"
  local class_name="$2"
  local description="$3"
  local app_name="$4"
  local log_name="$5"
  local asset_sha="$6"

  cat >"$file" <<EOF_FORMULA
class ${class_name} < Formula
  desc "${description}"
  homepage "https://github.com/${repository}"
  url "https://github.com/${repository}/releases/download/${tag}/${app_name}-${version}.zip"
  sha256 "${asset_sha}"
  license "Apache-2.0"
  version "${version}"

  depends_on macos: :sonoma

  def install
    libexec.install "${app_name}.app"
    (var/"log/easybar").mkpath
  end

  service do
    run [opt_libexec/"${app_name}.app/Contents/MacOS/${app_name}"]
    environment_variables PATH: std_service_path_env, LANG: "en_US.UTF-8"
    keep_alive successful_exit: false
    process_type :interactive
    working_dir HOMEBREW_PREFIX
    log_path var/"log/easybar/${log_name}.out.log"
    error_log_path var/"log/easybar/${log_name}.err.log"
  end

  test do
    assert_predicate libexec/"${app_name}.app/Contents/MacOS/${app_name}", :executable?
  end
end
EOF_FORMULA
}

write_agent_formula \
  "$calendar_agent_formula_temp" \
  EasybarCalendarAgent \
  "Calendar EventKit helper service for EasyBar" \
  EasyBarCalendarAgent \
  calendar-agent \
  "$calendar_agent_sha"

write_agent_formula \
  "$network_agent_formula_temp" \
  EasybarNetworkAgent \
  "Wi-Fi and network helper service for EasyBar" \
  EasyBarNetworkAgent \
  network-agent \
  "$network_agent_sha"

ruby -c "$easybar_cask_temp" >/dev/null
ruby -c "$calendar_agent_formula_temp" >/dev/null
ruby -c "$network_agent_formula_temp" >/dev/null

mv -f "$easybar_cask_temp" "$easybar_cask_file"
mv -f "$calendar_agent_formula_temp" "$calendar_agent_formula_file"
mv -f "$network_agent_formula_temp" "$network_agent_formula_file"
