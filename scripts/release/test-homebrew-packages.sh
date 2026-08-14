#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

tap_dir="${tmp_dir}/homebrew-tap"
version="9.8.7"
tag="v${version}"
sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
calendar_agent_sha="1123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
network_agent_sha="2123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

remote_dir="${tmp_dir}/homebrew-tap.git"
mkdir -p "${tap_dir}/Formula"
git -C "${tap_dir}" init -q
git -C "${tap_dir}" config commit.gpgsign false
touch "${tap_dir}/Formula/easybar-calendar-agent.rb" \
  "${tap_dir}/Formula/easybar-network-agent.rb"
git -C "${tap_dir}" add Formula
git -C "${tap_dir}" -c user.name=test -c user.email=test@example.com \
  commit -qm fixture
git -C "${tap_dir}" branch -M main
git init --bare -q "${remote_dir}"
git -C "${tap_dir}" remote add origin "${remote_dir}"
git -C "${tap_dir}" push -qu -u origin main

"${repo_root}/scripts/release/update-homebrew-packages.sh" \
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

assert_no_local_git_identity() {
  if git -C "${tap_dir}" config --local --get user.name >/dev/null 2>&1; then
    echo "Homebrew commit helper unexpectedly changed the tap's local Git user.name." >&2
    exit 1
  fi

  if git -C "${tap_dir}" config --local --get user.email >/dev/null 2>&1; then
    echo "Homebrew commit helper unexpectedly changed the tap's local Git user.email." >&2
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
assert_contains "${calendar_formula}" 'assert_predicate libexec/"EasyBarCalendarAgent.app/Contents/MacOS/EasyBarCalendarAgent", :executable?'
assert_contains "${network_formula}" 'class EasybarNetworkAgent < Formula'
assert_contains "${network_formula}" "url \"https://github.com/easybar-app/easybar/releases/download/${tag}/EasyBarNetworkAgent-${version}.zip\""
assert_contains "${network_formula}" "sha256 \"${network_agent_sha}\""
assert_contains "${network_formula}" 'libexec.install "EasyBarNetworkAgent.app"'
assert_contains "${network_formula}" 'keep_alive successful_exit: false'
assert_contains "${network_formula}" 'process_type :interactive'
assert_contains "${network_formula}" 'assert_predicate libexec/"EasyBarNetworkAgent.app/Contents/MacOS/EasyBarNetworkAgent", :executable?'

if grep -Fq 'system "xattr"' "${calendar_formula}" "${network_formula}"; then
  echo "Agent formulas must not fail installation when no quarantine attribute exists." >&2
  exit 1
fi

ruby -c "${easybar_cask}" >/dev/null
ruby -c "${calendar_formula}" >/dev/null
ruby -c "${network_formula}" >/dev/null

"${repo_root}/scripts/release/commit-homebrew-packages.sh" \
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
assert_no_local_git_identity

# Automated commits must include only generated package files.
printf '%s\n' unrelated >"${tap_dir}/unrelated.txt"
git -C "${tap_dir}" add unrelated.txt
"${repo_root}/scripts/release/commit-homebrew-packages.sh" \
  --tap-dir "${tap_dir}" \
  --version "${version}" >/dev/null

committed_paths="$(git -C "${tap_dir}" show --format= --name-only HEAD | sort)"
expected_paths=$'Casks/easybar.rb\nFormula/easybar-calendar-agent.rb\nFormula/easybar-network-agent.rb'
if [ "${committed_paths}" != "${expected_paths}" ]; then
  echo "Unexpected files in automated Homebrew commit:" >&2
  printf '%s\n' "${committed_paths}" >&2
  exit 1
fi
if [ "$(git -C "${tap_dir}" diff --cached --name-only)" != unrelated.txt ]; then
  echo "Unrelated staged change was not preserved." >&2
  exit 1
fi
no_change_output="$(
  "${repo_root}/scripts/release/commit-homebrew-packages.sh" \
    --tap-dir "${tap_dir}" \
    --version "${version}"
)"
if [ "${no_change_output}" != "No changes to commit." ]; then
  echo "Unexpected no-change output: ${no_change_output}" >&2
  exit 1
fi
if [ "$(git -C "${tap_dir}" diff --cached --name-only)" != unrelated.txt ]; then
  echo "No-change commit check altered an unrelated staged change." >&2
  exit 1
fi
assert_no_local_git_identity

git -C "${tap_dir}" reset -q HEAD -- unrelated.txt
rm "${tap_dir}/unrelated.txt"

# The commit helper must also work on subsequent releases.
"${repo_root}/scripts/release/update-homebrew-packages.sh" \
  --tap-dir "${tap_dir}" \
  --repository easybar-app/easybar \
  --version "9.8.8" \
  --sha "${sha}" \
  --calendar-agent-sha "${calendar_agent_sha}" \
  --network-agent-sha "${network_agent_sha}"
"${repo_root}/scripts/release/commit-homebrew-packages.sh" \
  --tap-dir "${tap_dir}" \
  --version "9.8.8" \
  --dry-run >/dev/null

if ! git -C "${tap_dir}" diff --cached --quiet; then
  echo "Subsequent dry run unexpectedly modified the Git index." >&2
  exit 1
fi

assert_no_local_git_identity

if grep -Fq 'postflight do' "${easybar_cask}"; then
  echo "Legacy Homebrew flight block was generated." >&2
  exit 1
fi

if "${repo_root}/scripts/release/update-homebrew-packages.sh" \
  --tap-dir "${tap_dir}" \
  --repository 'invalid repository' \
  --version "9.8.8" \
  --sha "${sha}" \
  --calendar-agent-sha "${calendar_agent_sha}" \
  --network-agent-sha "${network_agent_sha}" >/dev/null 2>&1; then
  echo "Expected invalid repository metadata to fail." >&2
  exit 1
fi
