#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/metadata.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

git -C "$tmp_dir" init -q
git -C "$tmp_dir" -c user.name=test -c user.email=test@example.com \
  commit --allow-empty -qm fixture

for tag in \
  v1.2.2 \
  v1.2.3-alpha.10 \
  v1.2.3-alpha.2 \
  v1.2.3-beta.1 \
  v1.2.3 \
  v99.0.0-01; do
  git -C "$tmp_dir" tag "$tag"
done

test "$(latest_release_tag "$tmp_dir")" = v1.2.3

git -C "$tmp_dir" tag v1.2.4-alpha.2
git -C "$tmp_dir" tag v1.2.4-alpha.10
test "$(latest_release_tag "$tmp_dir")" = v1.2.4-alpha.10

git -C "$tmp_dir" tag v1.2.4
test "$(latest_release_tag "$tmp_dir")" = v1.2.4

if latest_release_tag "$tmp_dir" missing-revision >/dev/null 2>&1; then
  echo "Expected an invalid release-tag lookup revision to fail" >&2
  exit 1
fi
