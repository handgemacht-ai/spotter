#!/usr/bin/env bash
# Fetches review context from Spotter API when starting a project review session.
# Only runs when SPOTTER_REVIEW_MODE=1 is set (by Tmux.launch_project_review).
# Outputs hookSpecificOutput JSON with additionalContext on success.
# Exits silently on any failure to avoid blocking Claude startup.

set -euo pipefail

# Only run in review mode
if [ "${SPOTTER_REVIEW_MODE:-}" != "1" ]; then
  exit 0
fi

TOKEN="${SPOTTER_REVIEW_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  exit 0
fi

# Determine port
PORT="${SPOTTER_PORT:-1100}"

# Fetch review context (fail silently)
RESPONSE="$(curl -s \
  "http://127.0.0.1:${PORT}/api/review-context/${TOKEN}" \
  -H "Accept: application/json" \
  --connect-timeout 2 \
  --max-time 10 \
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
