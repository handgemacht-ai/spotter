#!/usr/bin/env bash
# Wait for Dolt to become reachable, with timeout.
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

DOLT_HOST="${DOLT_HOST:-${SPOTTER_DOLT_HOST:-127.0.0.1}}"
DOLT_PORT="${DOLT_PORT:-${SPOTTER_DOLT_HOST_PORT:-13307}}"
DOLT_USER="${SPOTTER_DOLT_USERNAME:-spotter}"
DOLT_PASS="${SPOTTER_DOLT_PASSWORD:-spotter}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-${SPOTTER_DOLT_TIMEOUT:-30}}"
DATABASE="${SPOTTER_DOLT_DATABASE:-spotter_product}"
TEST_DATABASE="${SPOTTER_TEST_SPEC_DOLT_DATABASE:-spotter_tests}"

echo "Waiting for Dolt on ${DOLT_HOST}:${DOLT_PORT} (timeout: ${WAIT_TIMEOUT}s)..."

for attempt in $(seq 1 "$WAIT_TIMEOUT"); do
  if mysql --protocol=TCP -h"${DOLT_HOST}" -P"${DOLT_PORT}" -u"${DOLT_USER}" -p"${DOLT_PASS}" -e "SELECT 1" >/dev/null 2>&1; then
    echo "Dolt is reachable."

    # Ensure databases exist
    mysql --protocol=TCP -h"${DOLT_HOST}" -P"${DOLT_PORT}" -u"${DOLT_USER}" -p"${DOLT_PASS}" \
      -e "CREATE DATABASE IF NOT EXISTS \`${DATABASE}\`" 2>/dev/null || true

    if [[ "$TEST_DATABASE" != "$DATABASE" ]]; then
      mysql --protocol=TCP -h"${DOLT_HOST}" -P"${DOLT_PORT}" -u"${DOLT_USER}" -p"${DOLT_PASS}" \
        -e "CREATE DATABASE IF NOT EXISTS \`${TEST_DATABASE}\`" 2>/dev/null || true
    fi

    exit 0
  fi

  if [[ "$attempt" -ge "$WAIT_TIMEOUT" ]]; then
    echo "Timed out waiting for Dolt after ${WAIT_TIMEOUT}s." >&2
    exit 1
  fi

  sleep 1
done
