#!/usr/bin/env bash
# Wait for Phoenix to become reachable, with timeout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKTREE_ENV_FILE="${WORKTREE_ENV_FILE:-${PROJECT_ROOT}/.worktree.env}"

if [ -f "$WORKTREE_ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$WORKTREE_ENV_FILE"
  set +a
fi

PHX_HOST="${PHX_HOST:-${SPOTTER_PHX_HOST:-127.0.0.1}}"
PHX_PORT="${PHX_PORT:-${SPOTTER_PHX_PORT:-1100}}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-${SPOTTER_PHX_TIMEOUT:-30}}"

echo "Waiting for Phoenix on ${PHX_HOST}:${PHX_PORT} (timeout: ${WAIT_TIMEOUT}s)..."

for attempt in $(seq 1 "$WAIT_TIMEOUT"); do
  http_code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 2 "http://${PHX_HOST}:${PHX_PORT}/" 2>/dev/null || true)"
  if [[ -n "$http_code" && "$http_code" != "000" ]]; then
    echo "Phoenix is reachable (HTTP ${http_code})."
    exit 0
  fi

  if [[ "$attempt" -ge "$WAIT_TIMEOUT" ]]; then
    echo "Timed out waiting for Phoenix after ${WAIT_TIMEOUT}s." >&2
    exit 1
  fi

  sleep 1
done
