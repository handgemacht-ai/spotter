#!/usr/bin/env bash
# Shared helper to resolve Spotter endpoints for hook scripts.
# Preference:
#   1) explicit SPOTTER_URL
#   2) explicit SPOTTER_TAILSCALE_URL / SPOTTER_TAILSCALE_IP
#   3) discovered Tailscale IP (when available)
#   4) localhost

spotter_resolve_urls() {
  local port="${1:-1100}"
  local candidates=()
  local tailscale_ip
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

  if [ -n "${SPOTTER_TAILSCALE_URL:-}" ]; then
    candidates+=("${SPOTTER_TAILSCALE_URL%/}")
  fi

  if [ -n "${SPOTTER_TAILSCALE_IP:-}" ]; then
    candidates+=("http://${SPOTTER_TAILSCALE_IP}:${port}")
  elif command -v tailscale >/dev/null 2>&1; then
    tailscale_ip="$(tailscale ip -4 2>/dev/null | awk 'NR==1 {print $1}')"
    if [ -n "$tailscale_ip" ]; then
      candidates+=("http://${tailscale_ip}:${port}")
    fi
  fi

  candidates+=("http://127.0.0.1:${port}")
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
