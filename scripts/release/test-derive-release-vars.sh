#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

output_file="$tmp_dir/github-output"
GITHUB_OUTPUT="$output_file" \
  "$repo_root/scripts/release/derive-release-vars.sh" \
  --tag v9.8.7-beta.1 \
  --repository easybar-app/easybar >/dev/null

grep -Fx 'tag=v9.8.7-beta.1' "$output_file" >/dev/null
grep -Fx 'version=9.8.7-beta.1' "$output_file" >/dev/null
grep -Fx 'asset_url=https://github.com/easybar-app/easybar/releases/download/v9.8.7-beta.1/EasyBar-9.8.7-beta.1.zip' "$output_file" >/dev/null
grep -Fx 'calendar_agent_asset_url=https://github.com/easybar-app/easybar/releases/download/v9.8.7-beta.1/EasyBarCalendarAgent-9.8.7-beta.1.zip' "$output_file" >/dev/null
grep -Fx 'network_agent_asset_url=https://github.com/easybar-app/easybar/releases/download/v9.8.7-beta.1/EasyBarNetworkAgent-9.8.7-beta.1.zip' "$output_file" >/dev/null

for invalid_tag in v1.2 v01.2.3 v1.02.3 v1.2.03 v1.2.3-01 v1.2.3-; do
  if "$repo_root/scripts/release/derive-release-vars.sh" --tag "$invalid_tag" >/dev/null 2>&1; then
    echo "Expected invalid release tag to fail: $invalid_tag" >&2
    exit 1
  fi
done

if "$repo_root/scripts/release/derive-release-vars.sh" \
  --tag v1.2.3 \
  --version 1.2.3 >/dev/null 2>&1; then
  echo "The removed --version compatibility option was unexpectedly accepted" >&2
  exit 1
fi

if "$repo_root/scripts/release/derive-release-vars.sh" \
  --tag v1.2.3 \
  --repository 'invalid repository' >/dev/null 2>&1; then
  echo "Expected invalid GitHub repository metadata to fail" >&2
  exit 1
fi
