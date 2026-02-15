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
[ -f "${LIB_DIR}/hook_timeouts.sh" ] && . "${LIB_DIR}/hook_timeouts.sh"
[ -f "${LIB_DIR}/spotter_url.sh" ] && . "${LIB_DIR}/spotter_url.sh"
[ -f "${LIB_DIR}/hook_http.sh" ] && . "${LIB_DIR}/hook_http.sh"

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

# Determine Spotter URL candidates
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PORT_FILE="$PLUGIN_DIR/../.port"

if [ -f "$PORT_FILE" ]; then
  PORT="$(cat "$PORT_FILE")"
else
  PORT=1100
fi

SPOTTER_URLS="$(spotter_resolve_urls "${PORT}")"

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

connect_timeout="$(resolve_timeout "${SPOTTER_TOOL_CALL_CONNECT_TIMEOUT:-}" "${SPOTTER_HOOK_CONNECT_TIMEOUT:-}" "$SPOTTER_DEFAULT_CONNECT_TIMEOUT")"
max_time="$(resolve_timeout "${SPOTTER_TOOL_CALL_MAX_TIME:-}" "${SPOTTER_HOOK_MAX_TIME:-}" "$SPOTTER_DEFAULT_MAX_TIME")"

for BASE_URL in $SPOTTER_URLS; do
  if spotter_post_hook_json \
    "$BASE_URL" \
    "/api/hooks/tool-call" \
    "$JSON" \
    "${HOOK_EVENT:-PostToolUse}" \
    "tool-call-capture.sh" \
    "${TRACEPARENT:-}" \
    "$connect_timeout" \
    "$max_time"; then
    break
  fi
done

exit 0
