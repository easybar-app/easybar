#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
kit_root="${EASYBAR_KIT_ROOT:-${project_root}/../easybar-kit}"

exec "$project_root/scripts/build/bundle.sh" \
  --kit-root "$kit_root" \
  "$@"
