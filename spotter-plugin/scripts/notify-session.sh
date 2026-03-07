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
[ -f "${LIB_DIR}/hook_timeouts.sh" ] && . "${LIB_DIR}/hook_timeouts.sh"
[ -f "${LIB_DIR}/spotter_url.sh" ] && . "${LIB_DIR}/spotter_url.sh"
[ -f "${LIB_DIR}/hook_http.sh" ] && . "${LIB_DIR}/hook_http.sh"
[ -f "${LIB_DIR}/canonical_dir.sh" ] && . "${LIB_DIR}/canonical_dir.sh"

# Read the session JSON from stdin
INPUT="$(cat)"

# Extract fields from the JSON input
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"
TRANSCRIPT_PATH="$(echo "$INPUT" | jq -r '.transcript_path // empty')"

# Persist session_id for MCP tools via CLAUDE_ENV_FILE
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${SESSION_ID:-}" ]; then
  echo "export SPOTTER_SESSION_ID=\"${SESSION_ID}\"" >> "$CLAUDE_ENV_FILE"
fi

# Resolve canonical project dir and persist for MCP header interpolation
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${CWD:-}" ] && type resolve_canonical_dir >/dev/null 2>&1; then
  CANONICAL_DIR="$(resolve_canonical_dir "$CWD")"
  printf 'export SPOTTER_PROJECT_DIR=%q\n' "${CANONICAL_DIR}" >> "$CLAUDE_ENV_FILE"
fi

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

# Resolve base URL candidates (container-safe: honours SPOTTER_URL / tailscale / localhost)
SPOTTER_URLS="$(spotter_resolve_urls "${PORT}")"

send_to_spotter() {
  local body="$1"
  local connect_timeout
  local max_time
  connect_timeout="$(resolve_timeout "${SPOTTER_NOTIFY_CONNECT_TIMEOUT:-}" "${SPOTTER_HOOK_CONNECT_TIMEOUT:-}" "$SPOTTER_DEFAULT_CONNECT_TIMEOUT")"
  max_time="$(resolve_timeout "${SPOTTER_NOTIFY_MAX_TIME:-}" "${SPOTTER_HOOK_MAX_TIME:-}" "$SPOTTER_DEFAULT_MAX_TIME")"

  for BASE_URL in $SPOTTER_URLS; do
    if spotter_post_hook_json \
      "$BASE_URL" \
      "/api/hooks/session-start" \
      "$body" \
      "SessionStart" \
      "notify-session.sh" \
      "${TRACEPARENT:-}" \
      "$connect_timeout" \
      "$max_time"; then
      return 0
    fi
  done

  return 0
}

# POST the mapping to Spotter (fail silently)
PAYLOAD="$(jq -n \
  --arg session_id "$SESSION_ID" \
  --arg pane_id "$TMUX_PANE" \
  --arg cwd "$CWD" \
  --arg transcript_path "$TRANSCRIPT_PATH" \
  '{session_id: $session_id, pane_id: $pane_id, cwd: $cwd}
  + (if $transcript_path == "" then {} else {transcript_path: $transcript_path} end)')"

send_to_spotter "$PAYLOAD" || true
