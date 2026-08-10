#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/dev/local-version.sh [--version-prefix PREFIX] [--dependency-root DIR]

Print the version used by make install-local. The version contains the latest
release version reachable from HEAD and the current short EasyBar commit. When
a dependency root is supplied, its short commit is included as well. A -dirty
suffix is appended when either checkout contains staged, unstaged, or untracked
changes.
EOF_USAGE
}

version_prefix="${VERSION_PREFIX:-v}"
dependency_root=""

while [ "$#" -gt 0 ]; do
  case "$1" in
  --version-prefix)
    if [ "$#" -lt 2 ]; then
      echo "Missing value for --version-prefix" >&2
      exit 2
    fi
    version_prefix="$2"
    shift 2
    ;;
  --dependency-root)
    if [ "$#" -lt 2 ]; then
      echo "Missing value for --dependency-root" >&2
      exit 2
    fi
    dependency_root="$2"
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

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"

require_git_worktree() {
  local root="$1"
  local label="$2"

  if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "$label requires a Git working tree: $root" >&2
    exit 1
  fi
}

short_commit() {
  git -C "$1" rev-parse --short=8 HEAD
}

is_dirty() {
  local root="$1"

  if ! git -C "$root" diff --quiet HEAD -- .; then
    return 0
  fi

  if [ -n "$(git -C "$root" ls-files --others --exclude-standard)" ]; then
    return 0
  fi

  return 1
}

require_git_worktree "$project_root" "Local version"

head_commit="$(git -C "$project_root" rev-parse --verify HEAD)"
project_commit="$(short_commit "$project_root")"
latest_tag="$({
  git -C "$project_root" tag --merged "$head_commit" --list "${version_prefix}*" --sort=-v:refname |
    sed -n '1p'
})"

if [ -n "$latest_tag" ]; then
  base_version="${latest_tag#"$version_prefix"}"
else
  base_version="0.0.0"
fi

version="${base_version}-dev.${project_commit}"
dirty=false

if is_dirty "$project_root"; then
  dirty=true
fi

if [ -n "$dependency_root" ]; then
  dependency_root="$(cd -- "$dependency_root" && pwd -P)"
  require_git_worktree "$dependency_root" "Dependency version"

  dependency_commit="$(short_commit "$dependency_root")"
  version="${version}.kit.${dependency_commit}"

  if is_dirty "$dependency_root"; then
    dirty=true
  fi
fi

if [ "$dirty" = true ]; then
  version="${version}-dirty"
fi

printf '%s\n' "$version"
