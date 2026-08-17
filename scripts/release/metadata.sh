#!/usr/bin/env bash
# Provide release metadata validation helpers.
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

# Returns success for release versions accepted by EasyBar tags and package publishing.
is_valid_release_version() {
  local version="$1"
  local prerelease
  local identifier
  local identifiers=()

  if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
    return 1
  fi

  if [[ "$version" != *-* ]]; then
    return 0
  fi

  prerelease="${version#*-}"
  IFS=. read -r -a identifiers <<<"$prerelease"
  for identifier in "${identifiers[@]}"; do
    if [[ "$identifier" =~ ^[0-9]+$ ]] && [ "$identifier" != 0 ] && [[ "$identifier" == 0* ]]; then
      return 1
    fi
  done
}

# Returns success for canonical v-prefixed EasyBar release tags.
is_valid_release_tag() {
  local tag="$1"

  [[ "$tag" == v* ]] && is_valid_release_version "${tag#v}"
}

# Returns success for safe GitHub owner/repository identifiers.
is_valid_github_repository() {
  [[ "$1" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*/[0-9A-Za-z][0-9A-Za-z._-]*$ ]]
}

# Returns success for lowercase SHA-256 digests emitted by the release workflow.
is_valid_sha256() {
  [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

# Prints the highest valid SemVer release tag reachable from a Git revision.
latest_release_tag() {
  local repository_root="$1"
  local revision="${2:-HEAD}"
  local tag
  local tags=()

  if ! git -C "$repository_root" rev-parse --verify "${revision}^{commit}" >/dev/null 2>&1; then
    echo "Invalid Git revision for release tag lookup: $revision" >&2
    return 1
  fi

  while IFS= read -r tag; do
    if is_valid_release_tag "$tag"; then
      tags+=("$tag")
    fi
  done < <(git -C "$repository_root" tag --merged "$revision" --list 'v*')

  if [ "${#tags[@]}" -eq 0 ]; then
    return 0
  fi

  printf '%s\n' "${tags[@]}" | python3 -c '
import sys


def prerelease_key(identifier):
    if identifier.isdigit():
        return (0, int(identifier))
    return (1, identifier)


def version_key(tag):
    version = tag[1:]
    core, separator, prerelease = version.partition("-")
    major, minor, patch = (int(component) for component in core.split("."))
    if not separator:
        return (major, minor, patch, 1, ())
    identifiers = tuple(prerelease_key(value) for value in prerelease.split("."))
    return (major, minor, patch, 0, identifiers)


print(max((line.rstrip("\n") for line in sys.stdin), key=version_key))
'
}
