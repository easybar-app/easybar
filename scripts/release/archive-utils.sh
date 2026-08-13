#!/usr/bin/env bash

# Returns success when a ZIP archive contains an entry with the exact requested path.
archive_contains_exact_entry() {
  local archive="$1"
  local expected_entry="$2"

  # Consume the complete listing: grep -q can give unzip SIGPIPE under pipefail.
  unzip -Z1 "$archive" | grep -Fx -- "$expected_entry" >/dev/null
}

# Prints the sorted unique top-level paths contained in a ZIP archive.
archive_top_level_entries() {
  local archive="$1"

  unzip -Z1 "$archive" |
    awk -F/ 'NF > 0 && $1 != "" { print $1 }' |
    sort -u
}
