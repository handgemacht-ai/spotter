#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-${REPO_ROOT}/docker-compose.dolt.yml}"
COMPOSE_WAIT_TIMEOUT_SECONDS="${COMPOSE_WAIT_TIMEOUT_SECONDS:-30}"

DOLT_HOST="${SPOTTER_DOLT_HOST:-127.0.0.1}"
DOLT_HOST_PORT=13307
DOLT_DATABASE="${SPOTTER_DOLT_DATABASE:-spotter_product}"
DOLT_USERNAME="${SPOTTER_DOLT_USERNAME:-spotter}"
DOLT_PASSWORD="${SPOTTER_DOLT_PASSWORD:-spotter}"

is_port_in_use() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN -n -P >/dev/null 2>&1
    return $?
  fi

  if command -v ss >/dev/null 2>&1; then
    if ss -ltn "sport = :$port" 2>/dev/null | sed 1d | grep -qE ".+"; then
      return 0
    fi
    return 1
  fi

  if command -v netstat >/dev/null 2>&1; then
    if netstat -ltn 2>/dev/null | grep -qE ":[^0-9]*$port([[:space:]]|$)"; then
      return 0
    fi
    return 1
  fi

  if (echo > /dev/tcp/"$DOLT_HOST"/"$port") >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to run this script." >&2
  exit 1
fi

if [ -z "${SPOTTER_ANTHROPIC_API_KEY:-}" ] && [ -z "${SKIP_ANTHROPIC_CHECK:-}" ]; then
  echo "SPOTTER_ANTHROPIC_API_KEY is required to run Spotter in dev/prod mode." >&2
  echo "Export SPOTTER_ANTHROPIC_API_KEY or set SKIP_ANTHROPIC_CHECK=1 to bypass." >&2
  exit 1
fi

if is_port_in_use "$DOLT_HOST_PORT"; then
  echo "Port ${DOLT_HOST_PORT} is already in use."
  echo "Set a different port in scripts/start_spotter_with_dolt.sh or free 13307."
  exit 1
fi

# Keep compose and runtime checks aligned on the host port.
export SPOTTER_DOLT_HOST_PORT="$DOLT_HOST_PORT"
export SPOTTER_DOLT_PORT="$DOLT_HOST_PORT"

cd "$REPO_ROOT"

docker compose -f "$COMPOSE_FILE" up -d dolt

echo "Starting Dolt SQL-server from ${COMPOSE_FILE} on ${DOLT_HOST}:${DOLT_HOST_PORT}..."

for attempt in $(seq 1 "$COMPOSE_WAIT_TIMEOUT_SECONDS"); do
  if mysql --protocol=TCP -h"${DOLT_HOST}" -P"${DOLT_HOST_PORT}" -u"${DOLT_USERNAME}" -p"${DOLT_PASSWORD}" -e "SELECT 1" "${DOLT_DATABASE}" >/dev/null 2>&1; then
    echo "Dolt SQL-server is reachable."
    break
  fi

  if [ "$attempt" -ge "$COMPOSE_WAIT_TIMEOUT_SECONDS" ]; then
    echo "Timed out waiting for Dolt to become reachable." >&2
    docker compose -f "$COMPOSE_FILE" logs --tail=80 dolt >&2
    exit 1
  fi

  sleep 1
done

echo "Running mix phx.server..."
exec mix phx.server
