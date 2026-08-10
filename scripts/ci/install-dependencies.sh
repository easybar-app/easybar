#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <release>" >&2
}

mode="${1:-}"
case "$mode" in
release) ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage
  exit 2
  ;;
esac

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
