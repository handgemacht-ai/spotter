#!/usr/bin/env bash
# Tool call capture: records tool call outcomes (success/failure) to Spotter.
# Handles both PostToolUse (success) and PostToolUseFailure (failure) events.
# Fails silently to never block Claude.

set -euo pipefail
trap 'exit 0' ERR

# Source trace context helper (fail silently if unavailable)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
[ -f "${LIB_DIR}/trace_context.sh" ] && . "${LIB_DIR}/trace_context.sh"

INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
TOOL_USE_ID="$(echo "$INPUT" | jq -r '.tool_use_id // empty')"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
HOOK_EVENT="$(echo "$INPUT" | jq -r '.hook_event_name // empty')"

if [ -z "$TOOL_USE_ID" ] || [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Generate trace context (fail gracefully if unavailable)
TRACEPARENT="$(spotter_generate_traceparent 2>/dev/null || true)"

# Determine Spotter URL
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PORT_FILE="$PLUGIN_DIR/../.port"

if [ -f "$PORT_FILE" ]; then
  PORT="$(cat "$PORT_FILE")"
else
  PORT=1100
fi

SPOTTER_URL="${SPOTTER_URL:-http://127.0.0.1:${PORT}}"

# Determine success vs failure
IS_ERROR=false
ERROR_CONTENT=""

if [ "$HOOK_EVENT" = "PostToolUseFailure" ]; then
  IS_ERROR=true
  ERROR_CONTENT="$(echo "$INPUT" | jq -r '(.error // "") | tostring | .[0:500]')"
fi

JSON="$(jq -n \
  --arg session_id "$SESSION_ID" \
  --arg tool_use_id "$TOOL_USE_ID" \
  --arg tool_name "$TOOL_NAME" \
  --argjson is_error "$IS_ERROR" \
  --arg error_content "$ERROR_CONTENT" \
  '{session_id: $session_id, tool_use_id: $tool_use_id, tool_name: $tool_name, is_error: $is_error, error_content: (if $error_content == "" then null else $error_content end)}'
)"

CURL_ARGS=(
  -s -o /dev/null -X POST
  "${SPOTTER_URL}/api/hooks/tool-call"
  -H "Content-Type: application/json"
  -H "x-spotter-hook-event: ${HOOK_EVENT:-PostToolUse}"
  -H "x-spotter-hook-script: tool-call-capture.sh"
  -d "$JSON"
  --connect-timeout 2
  --max-time 5
)

# Add traceparent header if available
[ -n "${TRACEPARENT:-}" ] && CURL_ARGS+=(-H "traceparent: ${TRACEPARENT}")

curl "${CURL_ARGS[@]}" 2>/dev/null || true

exit 0
