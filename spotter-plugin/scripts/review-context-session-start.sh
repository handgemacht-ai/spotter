#!/usr/bin/env bash
# Fetches review context from Spotter API when starting a project review session.
# Only runs when SPOTTER_REVIEW_MODE=1 is set (by Tmux.launch_project_review).
# Outputs hookSpecificOutput JSON with additionalContext on success.
# Exits silently on any failure to avoid blocking Claude startup.

set -euo pipefail

# Source shared timeout helper (fail silently if unavailable)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
[ -f "${LIB_DIR}/hook_timeouts.sh" ] && . "${LIB_DIR}/hook_timeouts.sh"

# Only run in review mode
if [ "${SPOTTER_REVIEW_MODE:-}" != "1" ]; then
  exit 0
fi

TOKEN="${SPOTTER_REVIEW_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  exit 0
fi

# Determine port and base URL (container-safe: honours SPOTTER_URL)
PORT="${SPOTTER_PORT:-1100}"
BASE_URL="${SPOTTER_URL:-http://127.0.0.1:${PORT}}"

# Fetch review context (fail silently)
RESPONSE="$(curl -s \
  "${BASE_URL}/api/review-context/${TOKEN}" \
  -H "Accept: application/json" \
  --connect-timeout "$(resolve_timeout "${SPOTTER_REVIEW_CONTEXT_CONNECT_TIMEOUT:-}" "${SPOTTER_HOOK_CONNECT_TIMEOUT:-}" "$SPOTTER_DEFAULT_CONNECT_TIMEOUT")" \
  --max-time "$(resolve_timeout "${SPOTTER_REVIEW_CONTEXT_MAX_TIME:-}" "${SPOTTER_HOOK_MAX_TIME:-}" "$SPOTTER_DEFAULT_MAX_TIME")" \
  2>/dev/null)" || exit 0

# Extract context field from response
CONTEXT="$(echo "$RESPONSE" | jq -r '.context // empty' 2>/dev/null)" || exit 0

if [ -z "$CONTEXT" ]; then
  exit 0
fi

# Output hook JSON with additionalContext
jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
