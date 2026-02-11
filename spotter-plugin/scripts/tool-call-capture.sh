#!/usr/bin/env bash
# Tool call capture: records tool call outcomes (success/failure) to Spotter.
# Handles both PostToolUse (success) and PostToolUseFailure (failure) events.
# Fails silently to never block Claude.

set -euo pipefail
trap 'exit 0' ERR

INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
TOOL_USE_ID="$(echo "$INPUT" | jq -r '.tool_use_id // empty')"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
HOOK_EVENT="$(echo "$INPUT" | jq -r '.hook_event_name // empty')"

if [ -z "$TOOL_USE_ID" ] || [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Determine Spotter URL
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

curl -s -o /dev/null -X POST \
  "${SPOTTER_URL}/api/hooks/tool-call" \
  -H "Content-Type: application/json" \
  -d "$JSON" \
  --connect-timeout 2 \
  --max-time 5 \
  2>/dev/null || true

exit 0
