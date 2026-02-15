#!/usr/bin/env bash
# Notifies Spotter that a Claude Code session has ended.
# Reads session JSON from stdin, extracts session_id.
# Sends POST to Spotter's session-end endpoint.
# Fails silently if server is not running.

set -euo pipefail

# Source trace context helper (fail silently if unavailable)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
[ -f "${LIB_DIR}/trace_context.sh" ] && . "${LIB_DIR}/trace_context.sh"
[ -f "${LIB_DIR}/hook_timeouts.sh" ] && . "${LIB_DIR}/hook_timeouts.sh"
[ -f "${LIB_DIR}/spotter_url.sh" ] && . "${LIB_DIR}/spotter_url.sh"
[ -f "${LIB_DIR}/hook_http.sh" ] && . "${LIB_DIR}/hook_http.sh"

# Read the session JSON from stdin
INPUT="$(cat)"

# Extract fields from the JSON input
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"

if [ -z "${SESSION_ID:-}" ]; then
  exit 0
fi

# Generate trace context (fail gracefully if unavailable)
TRACEPARENT="$(spotter_generate_traceparent 2>/dev/null || true)"

# Determine the Spotter port from the worktree .port file
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PORT_FILE="$PLUGIN_DIR/../.port"

if [ -f "$PORT_FILE" ]; then
  PORT="$(cat "$PORT_FILE")"
else
  PORT=1100
fi

# Resolve base URL candidates (container-safe: honours SPOTTER_URL / tailscale / localhost)
SPOTTER_URLS="$(spotter_resolve_urls "${PORT}")"

send_to_spotter() {
  local body="$1"
  local connect_timeout
  local max_time
  connect_timeout="$(resolve_timeout "${SPOTTER_NOTIFY_END_CONNECT_TIMEOUT:-}" "${SPOTTER_HOOK_CONNECT_TIMEOUT:-}" "$SPOTTER_DEFAULT_CONNECT_TIMEOUT")"
  max_time="$(resolve_timeout "${SPOTTER_NOTIFY_END_MAX_TIME:-}" "${SPOTTER_HOOK_MAX_TIME:-}" "$SPOTTER_DEFAULT_MAX_TIME")"

  for BASE_URL in $SPOTTER_URLS; do
    if spotter_post_hook_json \
      "$BASE_URL" \
      "/api/hooks/session-end" \
      "$body" \
      "Stop" \
      "notify-session-end.sh" \
      "${TRACEPARENT:-}" \
      "$connect_timeout" \
      "$max_time"; then
      return 0
    fi
  done

  return 0
}

send_to_spotter "{\"session_id\": \"${SESSION_ID}\"}" || true
