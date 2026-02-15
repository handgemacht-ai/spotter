#!/usr/bin/env bash
# Waiting overlay worker: sleeps for the configured delay, then fetches
# a summary from Spotter and shows a pane-targeted tmux popup.
#
# Expected environment:
#   TMUX_PANE        - target pane identifier
#   SESSION_ID       - Claude session id
#   STATE_KEY        - base path for state files (/tmp/spotter-waiting-<pane>-<session>)
#   TRANSCRIPT_PATH  - (optional) path to transcript JSONL
#
# Fails silently to never block anything.

set -euo pipefail
trap 'exit 0' ERR

DELAY="${SPOTTER_WAITING_DELAY_SECONDS:-300}"
OVERLAY_HEIGHT="${SPOTTER_OVERLAY_HEIGHT:-16}"
CANCEL_FILE="${STATE_KEY}.cancel"
PID_FILE="${STATE_KEY}.pid"

# Determine Spotter URL
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PORT_FILE="$PLUGIN_DIR/../.port"
LIB_DIR="${SCRIPT_DIR}/lib"
[ -f "${LIB_DIR}/spotter_url.sh" ] && . "${LIB_DIR}/spotter_url.sh"

if [ -f "$PORT_FILE" ]; then
  PORT="$(cat "$PORT_FILE")"
else
  PORT=1100
fi

SPOTTER_URLS="$(spotter_resolve_urls "${PORT}")"

# Sleep for the configured delay
sleep "$DELAY" || true

# Re-check cancellation after sleep
if [ -f "$CANCEL_FILE" ]; then
  rm -f "$CANCEL_FILE" "$PID_FILE"
  exit 0
fi

# Verify target pane still exists
if ! tmux display-message -p -t "$TMUX_PANE" '#{pane_id}' >/dev/null 2>&1; then
  rm -f "$PID_FILE"
  exit 0
fi

# Get pane width for popup sizing
PANE_WIDTH="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_width}' 2>/dev/null || echo "")"
if [ -z "$PANE_WIDTH" ]; then
  rm -f "$PID_FILE"
  exit 0
fi

# Fetch summary from Spotter endpoint
SUMMARY_TEXT="Claude is waiting for your input."

if [ -n "${TRANSCRIPT_PATH:-}" ]; then
  SUMMARY_RESPONSE=""
  for BASE_URL in $SPOTTER_URLS; do
    TMP_BODY="$(mktemp /tmp/spotter-waiting-body.XXXXXX)"
    TMP_ERR="$(mktemp /tmp/spotter-waiting-err.XXXXXX)"
    HTTP_CODE="$(curl -sS -o "$TMP_BODY" -w '%{http_code}' \
      -X POST \
      "${BASE_URL}/api/hooks/waiting-summary" \
      -H "Content-Type: application/json" \
      -d "{\"session_id\": \"${SESSION_ID}\", \"transcript_path\": \"${TRANSCRIPT_PATH}\"}" \
      --connect-timeout 5 \
      --max-time 20 \
      2>"$TMP_ERR")"
    CURL_RC=$?
    CURL_ERR="$(cat "$TMP_ERR" 2>/dev/null | tr -d '\n' || true)"
    rm -f "$TMP_ERR"

    if [ "$CURL_RC" -eq 0 ] && [[ "$HTTP_CODE" == 2[0-9][0-9] ]]; then
      SUMMARY_RESPONSE="$(cat "$TMP_BODY")"
      rm -f "$TMP_BODY"
      break
    fi

    echo "[spotter-hook] event=WaitingSummary script=waiting-overlay-worker.sh url=${BASE_URL}/api/hooks/waiting-summary status=${HTTP_CODE:-n/a} curl_rc=${CURL_RC} err=${CURL_ERR:-n/a}" >&2
    rm -f "$TMP_BODY"
  done

  if [ -n "$SUMMARY_RESPONSE" ]; then
    PARSED="$(echo "$SUMMARY_RESPONSE" | jq -r '.summary // empty' 2>/dev/null || true)"
    if [ -n "$PARSED" ]; then
      SUMMARY_TEXT="$PARSED"
    fi
  fi
fi

# Re-check cancellation before showing popup (LLM call may take time)
if [ -f "$CANCEL_FILE" ]; then
  rm -f "$CANCEL_FILE" "$PID_FILE"
  exit 0
fi

# Show pane-targeted popup, dismissable by any key
# -t targets exact pane, -x P -y P centers on pane
# The popup runs a subshell that displays text and waits for a keypress
tmux display-popup \
  -t "$TMUX_PANE" \
  -x P -y P \
  -w "$PANE_WIDTH" \
  -h "$OVERLAY_HEIGHT" \
  -E \
  "printf '\\n  %s\\n\\n  Press any key to dismiss.' '${SUMMARY_TEXT}'; read -r -s -n 1" \
  2>/dev/null || true

# Cleanup state files
rm -f "$PID_FILE" "$CANCEL_FILE"

exit 0
