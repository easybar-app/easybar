#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --project-root DIR --output DIR" >&2
}

project_root=""
output=""

while [ "$#" -gt 0 ]; do
  case "$1" in
  --project-root)
    project_root="${2:?missing value for --project-root}"
    shift 2
    ;;
  --output)
    output="${2:?missing value for --output}"
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

if [ -z "$project_root" ] || [ -z "$output" ]; then
  usage
  exit 2
fi
if [ ! -f "$project_root/Package.swift" ]; then
  echo "Missing package manifest: $project_root/Package.swift" >&2
  exit 1
fi
if [ ! -d "$project_root/Sources" ] || [ ! -d "$project_root/Tests" ]; then
  echo "Project Sources and Tests directories are required: $project_root" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Required command not found: python3" >&2
  exit 1
fi

project_root="$(cd -- "$project_root" && pwd -P)"
case "$output" in
/*) ;;
*) output="$project_root/$output" ;;
esac
if [ -L "$output" ]; then
  echo "Local package workspace must not be a symbolic link: $output" >&2
  exit 2
fi

output="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$output")"
if [ "$output" = / ]; then
  echo "Local package workspace must not be the filesystem root" >&2
  exit 2
fi

case "$project_root" in
"$output" | "$output"/*)
  echo "Local package workspace must not be the project root or one of its parents: $output" >&2
  exit 2
  ;;
esac

case "$output" in
"$project_root/.build"/*) ;;
"$project_root"/*)
  echo "Project-local package workspaces must be inside .build: $output" >&2
  exit 2
  ;;
esac

if [ -e "$output" ] && [ ! -d "$output" ]; then
  echo "Local package workspace is not a directory: $output" >&2
  exit 2
fi

workspace_marker="$output/.easybar-local-package"
if [ -d "$output" ] && [ ! -f "$workspace_marker" ]; then
  for entry in "$output"/* "$output"/.[!.]* "$output"/..?*; do
    if [ -e "$entry" ] || [ -L "$entry" ]; then
      echo "Refusing to replace an unowned local package workspace: $output" >&2
      exit 2
    fi
  done
fi

mkdir -p "$output"
printf 'EasyBar local package workspace\n' >"$workspace_marker"

manifest_stage="$output/.Package.swift.local.$$"
cleanup() {
  rm -f "$manifest_stage"
}
trap cleanup EXIT

cp "$project_root/Package.swift" "$manifest_stage"
mv -f "$manifest_stage" "$output/Package.swift"

for directory in Sources Tests; do
  rm -rf "$output/$directory"
  ln -s "$project_root/$directory" "$output/$directory"
done
