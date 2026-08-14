#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "$(basename "${BASH_SOURCE[0]}") failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

if [ "$#" -ne 0 ]; then
  echo "Usage: scripts/ci/install-release-dependencies.sh" >&2
  exit 2
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install release build dependencies." >&2
  exit 1
fi

install_if_missing() {
  local command_name="$1"
  local formula="$2"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install "$formula"
  fi
}

install_if_missing magick imagemagick
install_if_missing rsvg-convert librsvg

magick -version
rsvg-convert --version
