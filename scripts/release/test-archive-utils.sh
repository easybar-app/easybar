#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/scripts/release/archive-utils.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

archive="${tmp_dir}/release.zip"
fixture_dir="${tmp_dir}/fixture"
expected_entry="EasyBarCalendarAgent-9.8.7/EasyBarCalendarAgent.app/Contents/MacOS/EasyBarCalendarAgent"

mkdir -p "${fixture_dir}/$(dirname "${expected_entry}")" "${fixture_dir}/trailing"
touch "${fixture_dir}/${expected_entry}"

# Keep enough entries after the match to reproduce grep -q's SIGPIPE under pipefail.
for index in $(seq 1 4096); do
  touch "${fixture_dir}/trailing/release-entry-${index}"
done

(
  cd "${fixture_dir}"
  zip -qr "${archive}" EasyBarCalendarAgent-9.8.7 trailing
)

if ! archive_contains_exact_entry "${archive}" "${expected_entry}"; then
  echo "Expected archive entry was not found: ${expected_entry}" >&2
  exit 1
fi

if archive_contains_exact_entry "${archive}" "EasyBarCalendarAgent.app/Contents/MacOS/EasyBarCalendarAgent"; then
  echo "Unexpected unwrapped archive entry was found." >&2
  exit 1
fi
