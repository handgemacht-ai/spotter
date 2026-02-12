#!/usr/bin/env bash
# Waiting overlay orchestrator: arms or cancels a delayed tmux popup
# when Claude enters waiting/idle state.
#
# Usage:
#   - Notification hook: stdin receives hook JSON, arms a timer.
#   - Stop hook:         called with "clear" argument, cancels pending timer.
#
# Fails silently to never block Claude.

set -euo pipefail
trap 'exit 0' ERR

ACTION="${1:-arm}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Bail out if not running inside tmux
if [ -z "${TMUX_PANE:-}" ]; then
  exit 0
fi

# Read hook JSON from stdin (may be empty for "clear" action from Stop hook)
INPUT=""
if [ "$ACTION" = "arm" ]; then
  INPUT="$(cat)"
fi

# Extract session_id from payload when arming
SESSION_ID=""
if [ -n "$INPUT" ]; then
  SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
fi

# For clear action during Stop hook, we don't have session_id in all cases.
# Use pane-only prefix for cancellation to catch all sessions on this pane.
PANE_SAFE="$(echo "$TMUX_PANE" | tr -cd '[:alnum:]_-')"
STATE_PREFIX="/tmp/spotter-waiting-${PANE_SAFE}"

cancel_pending() {
  # Set cancellation markers and kill any pending worker PIDs
  for pid_file in ${STATE_PREFIX}-*.pid; do
    [ -f "$pid_file" ] || continue
    local cancel_file="${pid_file%.pid}.cancel"
    touch "$cancel_file"
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  done
}

if [ "$ACTION" = "clear" ]; then
  cancel_pending
  exit 0
fi

# --- Arming path ---

# Filter: only arm on waiting/idle notification types
NOTIFICATION_TYPE=""
if [ -n "$INPUT" ]; then
  NOTIFICATION_TYPE="$(echo "$INPUT" | jq -r '.notification_type // empty')"
fi

case "${NOTIFICATION_TYPE}" in
  idle_prompt|permission_prompt|elicitation_dialog)
    # These indicate Claude is waiting for user input - arm the timer
    ;;
  *)
    # Not a waiting state notification - ignore
    exit 0
    ;;
esac

if [ -z "$SESSION_ID" ]; then
  exit 0
fi

SESSION_SAFE="$(echo "$SESSION_ID" | tr -cd '[:alnum:]_-')"
STATE_KEY="${STATE_PREFIX}-${SESSION_SAFE}"

# Cancel any existing timer for this pane/session (last arm wins)
cancel_file="${STATE_KEY}.cancel"
pid_file="${STATE_KEY}.pid"

if [ -f "$pid_file" ]; then
  old_pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
fi

# Remove stale cancel marker before arming
rm -f "$cancel_file"

# Extract transcript_path from notification payload
TRANSCRIPT_PATH=""
if [ -n "$INPUT" ]; then
  TRANSCRIPT_PATH="$(echo "$INPUT" | jq -r '.transcript_path // empty')"
fi

# Export state for the worker
export TMUX_PANE
export SESSION_ID
export STATE_KEY
export TRANSCRIPT_PATH

# Launch worker in background (non-blocking)
nohup "${SCRIPT_DIR}/waiting-overlay-worker.sh" \
  </dev/null >/dev/null 2>&1 &

# Record worker PID
echo $! > "$pid_file"

exit 0
