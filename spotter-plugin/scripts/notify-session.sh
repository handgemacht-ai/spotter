#!/usr/bin/env bash
# Notifies Spotter of the session_id <-> pane_id mapping.
# Reads session JSON from stdin, extracts session_id.
# Sends POST to Spotter's session-start endpoint.
# Fails silently if server is not running.

set -euo pipefail

# Source trace context helper (fail silently if unavailable)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
[ -f "${LIB_DIR}/trace_context.sh" ] && . "${LIB_DIR}/trace_context.sh"

# Read the session JSON from stdin
INPUT="$(cat)"

# Extract fields from the JSON input
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"

if [ -z "${SESSION_ID:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
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

# POST the mapping to Spotter (fail silently)
CURL_ARGS=(
  -s -o /dev/null -X POST
  "http://127.0.0.1:${PORT}/api/hooks/session-start"
  -H "Content-Type: application/json"
  -H "x-spotter-hook-event: SessionStart"
  -H "x-spotter-hook-script: notify-session.sh"
  -d "{\"session_id\": \"${SESSION_ID}\", \"pane_id\": \"${TMUX_PANE}\", \"cwd\": \"${CWD}\"}"
  --connect-timeout 2
  --max-time 4
)

# Add traceparent header if available
[ -n "${TRACEPARENT:-}" ] && CURL_ARGS+=(-H "traceparent: ${TRACEPARENT}")

curl "${CURL_ARGS[@]}" 2>/dev/null || true
