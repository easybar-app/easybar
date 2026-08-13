#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --tag <tag> [--repository <owner/repo>]" >&2
}

write_output() {
  local name="$1"
  local value="$2"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
  else
    printf '%s=%s\n' "$name" "$value"
  fi
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/metadata.sh"

tag=""
repository="${GITHUB_REPOSITORY:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
  --tag)
    tag="${2:?missing value for --tag}"
    shift 2
    ;;
  --repository)
    repository="${2:?missing value for --repository}"
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

if [ -z "$tag" ]; then
  echo "Missing release tag" >&2
  usage
  exit 2
fi

if ! is_valid_release_tag "$tag"; then
  echo "::error::Invalid release tag: $tag" >&2
  echo "Release tags must use vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-prerelease." >&2
  exit 1
fi

version="${tag#v}"
write_output "tag" "$tag"
write_output "version" "$version"

if [ -n "$repository" ]; then
  write_output "asset_url" "https://github.com/${repository}/releases/download/${tag}/EasyBar-${version}.zip"
  write_output "calendar_agent_asset_url" "https://github.com/${repository}/releases/download/${tag}/EasyBarCalendarAgent-${version}.zip"
  write_output "network_agent_asset_url" "https://github.com/${repository}/releases/download/${tag}/EasyBarNetworkAgent-${version}.zip"
fi

printf 'Tag: %s\n' "$tag"
printf 'Version: %s\n' "$version"
if [ -n "$repository" ]; then
  printf 'Repository: %s\n' "$repository"
fi
