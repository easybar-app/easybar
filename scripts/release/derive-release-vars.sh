#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --tag <tag> [--version <version>] [--repository <owner/repo>]" >&2
}

write_output() {
  local name="$1"
  local value="$2"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  else
    echo "${name}=${value}"
  fi
}

tag=""
version=""
repository="${GITHUB_REPOSITORY:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      tag="$2"
      shift 2
      ;;
    --version)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      version="$2"
      shift 2
      ;;
    --repository)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      repository="$2"
      shift 2
      ;;
    -h|--help)
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

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "::error::Invalid release tag: ${tag}" >&2
  echo "Release tags must use vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-prerelease." >&2
  exit 1
fi

if [ -z "$version" ]; then
  version="${tag#v}"
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "::error::Invalid release version: ${version}" >&2
  echo "Versions must use MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-prerelease." >&2
  exit 1
fi

if [ "$tag" != "v${version}" ]; then
  echo "::error::Release tag must match version: expected v${version}, got ${tag}" >&2
  exit 1
fi

write_output "tag" "$tag"
write_output "version" "$version"

if [ -n "$repository" ]; then
  write_output "asset_url" "https://github.com/${repository}/releases/download/${tag}/EasyBar-${version}.zip"
  write_output "calendar_agent_asset_url" "https://github.com/${repository}/releases/download/${tag}/EasyBarCalendarAgent-${version}.zip"
  write_output "network_agent_asset_url" "https://github.com/${repository}/releases/download/${tag}/EasyBarNetworkAgent-${version}.zip"
fi

echo "Tag: ${tag}"
echo "Version: ${version}"
if [ -n "$repository" ]; then
  echo "Repository: ${repository}"
fi
