#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

project_root="$tmp_dir/easybar"
dependency_root="$tmp_dir/easybar-kit"
mkdir -p \
  "$project_root/scripts/dev" \
  "$project_root/scripts/release" \
  "$dependency_root"
cp "$script_dir/local-version.sh" "$project_root/scripts/dev/"
cp "$script_dir/../release/metadata.sh" "$project_root/scripts/release/"

init_repository() {
  local root="$1"
  local fixture="$2"

  git -C "$root" init -q
  git -C "$root" config user.name test
  git -C "$root" config user.email test@example.com
  printf '%s\n' "$fixture" >"$root/fixture.txt"
  git -C "$root" add -A
  git -C "$root" commit -qm fixture
}

init_repository "$project_root" easybar
init_repository "$dependency_root" easybar-kit

git -C "$project_root" tag v1.2.3
git -C "$project_root" tag v99.0.0-01

project_commit="$(git -C "$project_root" rev-parse --short=8 HEAD)"
dependency_commit="$(git -C "$dependency_root" rev-parse --short=8 HEAD)"

version="$($project_root/scripts/dev/local-version.sh)"
test "$version" = "1.2.3-dev.${project_commit}"

version="$($project_root/scripts/dev/local-version.sh --dependency-root "$dependency_root")"
test "$version" = "1.2.3-dev.${project_commit}.kit.${dependency_commit}"

touch "$dependency_root/untracked"
version="$($project_root/scripts/dev/local-version.sh --dependency-root "$dependency_root")"
test "$version" = "1.2.3-dev.${project_commit}.kit.${dependency_commit}-dirty"

if "$project_root/scripts/dev/local-version.sh" --version-prefix v >/dev/null 2>&1; then
  echo "The removed version-prefix option was unexpectedly accepted" >&2
  exit 1
fi
