#!/usr/bin/env bash
# Raw event forward: captures complete hook payload + env vars for Spotter telemetry.
# Fires on ALL hook events. Fails silently to never block Claude.

set -euo pipefail
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
[ -f "${LIB_DIR}/trace_context.sh" ] && . "${LIB_DIR}/trace_context.sh"
[ -f "${LIB_DIR}/hook_timeouts.sh" ] && . "${LIB_DIR}/hook_timeouts.sh"
[ -f "${LIB_DIR}/spotter_url.sh" ] && . "${LIB_DIR}/spotter_url.sh"
[ -f "${LIB_DIR}/hook_http.sh" ] && . "${LIB_DIR}/hook_http.sh"

INPUT="$(cat)"

HOOK_EVENT="$(echo "$INPUT" | jq -r '.hook_event_name // empty')"

# Enrich InstructionsLoaded with file metrics
if [ "$HOOK_EVENT" = "InstructionsLoaded" ]; then
  FILE_PATH="$(echo "$INPUT" | jq -r '.file_path // empty')"
  if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
    BYTES_LOADED="$(wc -c < "$FILE_PATH" 2>/dev/null || echo 0)"
    LINES_LOADED="$(wc -l < "$FILE_PATH" 2>/dev/null || echo 0)"
    SIZE_STATUS="ok"
  elif [ -n "$FILE_PATH" ]; then
    BYTES_LOADED=0
    LINES_LOADED=0
    SIZE_STATUS="unreadable"
  else
    BYTES_LOADED=0
    LINES_LOADED=0
    SIZE_STATUS="missing"
  fi
  INPUT="$(echo "$INPUT" | jq \
    --argjson bytes "$BYTES_LOADED" \
    --argjson lines "$LINES_LOADED" \
    --arg status "$SIZE_STATUS" \
    '.spotter_instruction_metrics = {bytes_loaded: $bytes, lines_loaded: $lines, size_status: $status}')"
fi

# Generate trace context (fail gracefully if unavailable)
TRACEPARENT="$(spotter_generate_traceparent 2>/dev/null || true)"

# Collect curated env vars
ENV_JSON="$(env | grep -E '^(TMUX_PANE|CLAUDE_PROJECT_DIR|USER|SHELL|TERM|GIT_AUTHOR_|SPOTTER_|CLAUDE_)' | \
  jq -Rs 'split("\n") | map(select(length > 0) | split("=") | {(.[0]): (.[1:] | join("="))}) | add // {}' 2>/dev/null || echo '{}')"

# Hash PATH (macOS compat: try sha256sum first, fall back to shasum)
if command -v sha256sum >/dev/null 2>&1; then
  PATH_HASH="$(echo -n "$PATH" | sha256sum | cut -d' ' -f1)"
else
  PATH_HASH="$(echo -n "$PATH" | shasum -a 256 | cut -d' ' -f1)"
fi
ENV_JSON="$(echo "$ENV_JSON" | jq --arg ph "$PATH_HASH" '. + {"PATH_HASH": $ph}')"

# Build envelope
CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
ENVELOPE="$(jq -n \
  --argjson hook_payload "$INPUT" \
  --argjson env "$ENV_JSON" \
  --arg captured_at "$CAPTURED_AT" \
  '{hook_payload: $hook_payload, env: $env, captured_at: $captured_at}')"

# Resolve URL and POST
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PORT_FILE="$PLUGIN_DIR/../.port"

if [ -f "$PORT_FILE" ]; then
  PORT="$(cat "$PORT_FILE")"
else
  PORT=1100
fi

SPOTTER_URLS="$(spotter_resolve_urls "${PORT}")"

connect_timeout="$(resolve_timeout "${SPOTTER_RAW_EVENT_CONNECT_TIMEOUT:-}" "${SPOTTER_HOOK_CONNECT_TIMEOUT:-}" "$SPOTTER_DEFAULT_CONNECT_TIMEOUT")"
max_time="$(resolve_timeout "${SPOTTER_RAW_EVENT_MAX_TIME:-}" "${SPOTTER_HOOK_MAX_TIME:-}" "$SPOTTER_DEFAULT_MAX_TIME")"

for BASE_URL in $SPOTTER_URLS; do
  if spotter_post_hook_json \
    "$BASE_URL" \
    "/api/hooks/raw-event" \
    "$ENVELOPE" \
    "${HOOK_EVENT:-unknown}" \
    "raw-event-forward.sh" \
    "${TRACEPARENT:-}" \
    "$connect_timeout" \
    "$max_time"; then
    break
  fi
done

exit 0
