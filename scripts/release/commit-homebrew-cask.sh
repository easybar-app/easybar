#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --tap-dir DIR --version VERSION [--dry-run]" >&2
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/metadata.sh"

tap_dir=""
version=""
dry_run=false

while [ "$#" -gt 0 ]; do
  case "$1" in
  --tap-dir)
    tap_dir="${2:?missing value for --tap-dir}"
    shift 2
    ;;
  --version)
    version="${2:?missing value for --version}"
    shift 2
    ;;
  --dry-run)
    dry_run=true
    shift
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

if [ -z "$tap_dir" ] || [ -z "$version" ]; then
  usage
  exit 2
fi
if ! git -C "$tap_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Homebrew tap is not a Git working tree: $tap_dir" >&2
  exit 1
fi
if ! is_valid_release_version "$version"; then
  echo "Invalid release version: $version" >&2
  exit 2
fi

cd "$tap_dir"
git add -A -- \
  Casks/easybar.rb \
  Formula/easybar-calendar-agent.rb \
  Formula/easybar-network-agent.rb

if git diff --cached --quiet; then
  echo "No changes to commit."
  exit 0
fi

if [ "$dry_run" = true ]; then
  echo "Homebrew package changes are ready for EasyBar $version."
  git diff --cached --stat
  exit 0
fi

git \
  -c user.name="github-actions[bot]" \
  -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -m "chore(homebrew): update EasyBar to ${version}"
git push
