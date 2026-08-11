#!/usr/bin/env bash

# Returns success when a ZIP archive contains an entry with the exact requested path.
archive_contains_exact_entry() {
  local archive="$1"
  local expected_entry="$2"

  # Consume the complete listing: grep -q can give unzip SIGPIPE under pipefail.
  unzip -Z1 "$archive" | grep -Fx "$expected_entry" >/dev/null
}
