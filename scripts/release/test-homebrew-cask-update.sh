#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

tap_dir="${tmp_dir}/homebrew-tap"
version="9.8.7"
tag="v${version}"
sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
calendar_agent_sha="1123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
network_agent_sha="2123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

mkdir -p "${tap_dir}/Formula"
git -C "${tap_dir}" init -q
touch "${tap_dir}/Formula/easybar-calendar-agent.rb" \
  "${tap_dir}/Formula/easybar-network-agent.rb"
git -C "${tap_dir}" add Formula
git -C "${tap_dir}" -c user.name=test -c user.email=test@example.com \
  -c commit.gpgsign=false commit -qm fixture

"${repo_root}/scripts/release/update-homebrew-cask.sh" \
  --tap-dir "${tap_dir}" \
  --repository easybar-app/easybar \
  --version "${version}" \
  --sha "${sha}" \
  --calendar-agent-sha "${calendar_agent_sha}" \
  --network-agent-sha "${network_agent_sha}"

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq "${expected}" "${file}"; then
    echo "Expected ${file} to contain: ${expected}" >&2
    cat "${file}" >&2
    exit 1
  fi
}

easybar_cask="${tap_dir}/Casks/easybar.rb"
test -s "${easybar_cask}"
assert_contains "${easybar_cask}" 'cask "easybar" do'
assert_contains "${easybar_cask}" "url \"https://github.com/easybar-app/easybar/releases/download/${tag}/EasyBar-${version}.zip\""
assert_contains "${easybar_cask}" "sha256 \"${sha}\""
assert_contains "${easybar_cask}" "version \"${version}\""
assert_contains "${easybar_cask}" '"easybar-calendar-agent",'
assert_contains "${easybar_cask}" '"easybar-network-agent",'
assert_contains "${easybar_cask}" 'depends_on macos: :sonoma'
assert_contains "${easybar_cask}" 'postflight_steps do'
assert_contains "${easybar_cask}" 'run "/usr/bin/xattr",'
assert_contains "${easybar_cask}" 'args: ["-d", "com.apple.quarantine", "{{staged_path}}/easybar"]'
assert_contains "${easybar_cask}" 'args: ["-dr", "com.apple.quarantine", "{{appdir}}/EasyBar.app"]'
assert_contains "${easybar_cask}" 'must_succeed: false'
assert_contains "${easybar_cask}" 'run "{{HOMEBREW_BREW_FILE}}",'
assert_contains "${easybar_cask}" '"services", "restart", "easybar-calendar-agent"'
assert_contains "${easybar_cask}" '"services", "restart", "easybar-network-agent"'
assert_contains "${easybar_cask}" '"services", "stop", "easybar-calendar-agent"'
assert_contains "${easybar_cask}" '"services", "stop", "easybar-network-agent"'
assert_contains "${easybar_cask}" 'uninstall_preflight_steps do'
assert_contains "${easybar_cask}" 'app "EasyBar.app"'
assert_contains "${easybar_cask}" 'binary "easybar"'


calendar_formula="${tap_dir}/Formula/easybar-calendar-agent.rb"
network_formula="${tap_dir}/Formula/easybar-network-agent.rb"
test -s "${calendar_formula}"
test -s "${network_formula}"
assert_contains "${calendar_formula}" 'class EasybarCalendarAgent < Formula'
assert_contains "${calendar_formula}" "url \"https://github.com/easybar-app/easybar/releases/download/${tag}/EasyBarCalendarAgent-${version}.zip\""
assert_contains "${calendar_formula}" "sha256 \"${calendar_agent_sha}\""
assert_contains "${calendar_formula}" 'libexec.install "EasyBarCalendarAgent.app"'
assert_contains "${calendar_formula}" 'keep_alive successful_exit: false'
assert_contains "${calendar_formula}" 'process_type :interactive'
assert_contains "${network_formula}" 'class EasybarNetworkAgent < Formula'
assert_contains "${network_formula}" "url \"https://github.com/easybar-app/easybar/releases/download/${tag}/EasyBarNetworkAgent-${version}.zip\""
assert_contains "${network_formula}" "sha256 \"${network_agent_sha}\""
assert_contains "${network_formula}" 'libexec.install "EasyBarNetworkAgent.app"'
assert_contains "${network_formula}" 'keep_alive successful_exit: false'
assert_contains "${network_formula}" 'process_type :interactive'

if grep -Fq 'system "xattr"' "${calendar_formula}" "${network_formula}"; then
  echo "Agent formulas must not fail installation when no quarantine attribute exists." >&2
  exit 1
fi

ruby -c "${easybar_cask}" >/dev/null
ruby -c "${calendar_formula}" >/dev/null
ruby -c "${network_formula}" >/dev/null

"${repo_root}/scripts/release/commit-homebrew-cask.sh" \
  --tap-dir "${tap_dir}" \
  --version "${version}" \
  --dry-run >/dev/null

if ! git -C "${tap_dir}" diff --cached --quiet; then
  echo "Dry-run commit script unexpectedly modified the Git index." >&2
  exit 1
fi
if [ -z "$(git -C "${tap_dir}" status --short -- Casks Formula)" ]; then
  echo "Expected generated Homebrew package changes after dry run." >&2
  exit 1
fi
if git -C "${tap_dir}" config --get user.name >/dev/null 2>&1; then
  echo "Dry-run unexpectedly changed the tap's Git identity." >&2
  exit 1
fi

# The commit helper must also work on subsequent releases.
git -C "${tap_dir}" add -A -- Casks Formula
git -C "${tap_dir}" -c user.name=test -c user.email=test@example.com \
  -c commit.gpgsign=false commit -qm "publish cask"
"${repo_root}/scripts/release/update-homebrew-cask.sh" \
  --tap-dir "${tap_dir}" \
  --repository easybar-app/easybar \
  --version "9.8.8" \
  --sha "${sha}" \
  --calendar-agent-sha "${calendar_agent_sha}" \
  --network-agent-sha "${network_agent_sha}"
"${repo_root}/scripts/release/commit-homebrew-cask.sh" \
  --tap-dir "${tap_dir}" \
  --version "9.8.8" \
  --dry-run >/dev/null

if ! git -C "${tap_dir}" diff --cached --quiet; then
  echo "Subsequent dry run unexpectedly modified the Git index." >&2
  exit 1
fi

if grep -Fq 'postflight do' "${easybar_cask}"; then
  echo "Legacy Homebrew flight block was generated." >&2
  exit 1
fi

if "${repo_root}/scripts/release/update-homebrew-cask.sh" \
  --tap-dir "${tap_dir}" \
  --repository 'invalid repository' \
  --version "9.8.8" \
  --sha "${sha}" \
  --calendar-agent-sha "${calendar_agent_sha}" \
  --network-agent-sha "${network_agent_sha}" >/dev/null 2>&1; then
  echo "Expected invalid repository metadata to fail." >&2
  exit 1
fi
