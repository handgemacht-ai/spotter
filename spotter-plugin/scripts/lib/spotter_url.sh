#!/usr/bin/env bash
# Shared helper to resolve Spotter endpoints for hook scripts.
# Preference:
#   1) explicit SPOTTER_URL
#   2) localhost (single default to avoid duplicate loopback binds)

spotter_resolve_urls() {
  local port="${1:-1100}"
  local candidates=()
  local candidate
  local seen=""

  if [ -n "${SPOTTER_URL:-}" ]; then
    IFS=',' read -r -a provided_urls <<< "${SPOTTER_URL}"
    for candidate in "${provided_urls[@]}"; do
      candidate="${candidate#"${candidate%%[![:space:]]*}"}"
      candidate="${candidate%"${candidate##*[![:space:]]}"}"
      candidates+=("${candidate%/}")
    done
  fi

  candidates+=("http://localhost:${port}")

  for candidate in "${candidates[@]}"; do
    candidate="${candidate%/}"
    [ -z "$candidate" ] && continue

    if ! printf '%s' ",$seen," | grep -q ",${candidate},"; then
      echo "$candidate"
      seen="${seen}${candidate},"
    fi
  done
}
