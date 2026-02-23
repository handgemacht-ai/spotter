#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
_startup_pwd="$PWD"
COMPOSE_FILE="${COMPOSE_FILE:-${REPO_ROOT}/docker-compose.dolt.yml}"
OTEL_COMPOSE_FILE="${OTEL_COMPOSE_FILE:-${REPO_ROOT}/docker-compose.otel.yml}"
COMPOSE_WAIT_TIMEOUT_SECONDS="${COMPOSE_WAIT_TIMEOUT_SECONDS:-30}"
WORKTREE_ENV_FILE="${WORKTREE_ENV_FILE:-${REPO_ROOT}/.worktree.env}"

if [ -f "$WORKTREE_ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$WORKTREE_ENV_FILE"
  set +a
fi

if [ -z "${SPOTTER_PHX_PORT:-}" ] && [ -n "${SPOTTER_PORT:-}" ]; then
  export SPOTTER_PHX_PORT="$SPOTTER_PORT"
fi
if [ -z "${SPOTTER_PORT:-}" ] && [ -n "${SPOTTER_PHX_PORT:-}" ]; then
  export SPOTTER_PORT="$SPOTTER_PHX_PORT"
fi

# Two-switch design:
#   OBS_ENABLED          — startup behavior + OTLP endpoint default (always-on default)
#   SPOTTER_OTEL_ENABLED — Elixir SDK instrumentation at runtime (not managed here)
_obs_enabled=1
case "${OBS_ENABLED:-true}" in
  0|false|FALSE|no|NO)
    echo "[obs] OBS_ENABLED=false is deprecated; forcing observability ON" >&2
    ;;
esac

_obs_fallback=1
case "${SPOTTER_OTEL_LOCAL_FALLBACK:-true}" in
  0|false|FALSE|no|NO) _obs_fallback=0 ;;
esac

# ---------------------------------------------------------------------------
# OTEL_RESOURCE_ATTRIBUTES parsing
# ---------------------------------------------------------------------------
# Format: comma-separated key=value pairs
# Contract attributes with defaults:
#   dev.project.name       → defaults to "spotter"
#   dev.worktree.name      → defaults to basename of $PWD
#   service.instance.id    → defaults to "${dev.project.name}-${dev.worktree.name}"
# ---------------------------------------------------------------------------
parse_resource_attributes() {
  local raw="$1"
  # Associative array to hold parsed attributes
  declare -A attrs

  if [ -n "$raw" ]; then
    local _saved_set="$-"
    set -f
    IFS=',' read -ra _pairs <<< "$raw"
    [[ "$_saved_set" == *f* ]] || set +f
    for pair in "${_pairs[@]}"; do
      # Skip empty segments (e.g. trailing comma)
      [ -z "$pair" ] && continue

      # Split on first '=' only
      local key="${pair%%=*}"
      if [ "$key" = "$pair" ]; then
        echo "[obs] WARNING: malformed resource attribute (no '='): $pair" >&2
        continue
      fi
      local value="${pair#*=}"
      attrs["$key"]="$value"
    done
  fi

  # Fill contract defaults for missing keys
  if [ -z "${attrs[dev.project.name]+set}" ]; then
    attrs[dev.project.name]="spotter"
  fi
  if [ -z "${attrs[dev.worktree.name]+set}" ]; then
    attrs[dev.worktree.name]="$(basename "$_startup_pwd")"
  fi
  if [ -z "${attrs[service.instance.id]+set}" ]; then
    attrs[service.instance.id]="${attrs[dev.project.name]}-${attrs[dev.worktree.name]}"
  fi

  # Reassemble into comma-separated key=value string
  local result=""
  for key in $(printf '%s\n' "${!attrs[@]}" | sort); do
    if [ -n "$result" ]; then
      result="${result},"
    fi
    result="${result}${key}=${attrs[$key]}"
  done
  echo "$result"
}

export OTEL_RESOURCE_ATTRIBUTES="$(parse_resource_attributes "${OTEL_RESOURCE_ATTRIBUTES:-}")"

DOLT_HOST="${SPOTTER_DOLT_HOST:-127.0.0.1}"
DOLT_HOST_PORT="${SPOTTER_DOLT_HOST_PORT:-${SPOTTER_DOLT_PORT:-13307}}"
DOLT_DATABASE="${SPOTTER_DOLT_DATABASE:-spotter_product}"
TEST_SPEC_DOLT_DATABASE="${SPOTTER_TEST_SPEC_DOLT_DATABASE:-spotter_tests}"
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

if [ -z "${OTEL_EXPORTER:-}" ]; then
  export OTEL_EXPORTER=otlp
fi

if [ -z "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ]; then
  if [ "$_obs_enabled" -eq 1 ]; then
    # OBS_ENABLED: point at shared contract port (external collector)
    export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:14318"
  else
    export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"
  fi
fi

_external_obs_mode=0
case "${OTEL_EXPORTER_OTLP_ENDPOINT}" in
  "http://localhost:14318"|"http://127.0.0.1:14318")
    ;;
  *)
    _external_obs_mode=1
    ;;
esac

if is_port_in_use "$DOLT_HOST_PORT"; then
  echo "Port ${DOLT_HOST_PORT} is already in use."
  echo "Set SPOTTER_DOLT_HOST_PORT/ SPOTTER_DOLT_PORT or free that port."
  exit 1
fi

# Keep compose and runtime checks aligned on the host port.
export SPOTTER_DOLT_HOST_PORT="$DOLT_HOST_PORT"
if [ -z "${SPOTTER_DOLT_PORT:-}" ]; then
  export SPOTTER_DOLT_PORT="$DOLT_HOST_PORT"
fi

cd "$REPO_ROOT"

compose_args=(
  -f "$COMPOSE_FILE"
)

# ---------------------------------------------------------------------------
# Observability stack decision
# ---------------------------------------------------------------------------
# _include_local_otel tracks whether to merge docker-compose.otel.yml
_include_local_otel=0

if [ "$_obs_enabled" -eq 1 ]; then
  if [ "$_external_obs_mode" -eq 1 ]; then
    echo "[obs] External endpoint mode: OTEL_EXPORTER_OTLP_ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT}"
    echo "[obs] Skipping local/shared stack checks"
  else
  # Resolve path to workspace obs-dev-check.sh
  _workspace_root="$(cd -- "${REPO_ROOT}/.." 2>/dev/null && pwd)"
  OBS_CHECK="${OBS_CHECK:-${_workspace_root}/.runtime/docker/obs-dev-check.sh}"

  _obs_check_args=()
  if [ ! -t 1 ]; then
    _obs_check_args+=(--quiet)
  fi

  if [ ! -f "$OBS_CHECK" ]; then
    echo "[obs] WARNING: workspace obs-dev-check.sh not found at $OBS_CHECK" >&2
    echo "[obs] Treating as: no contract collector available" >&2
    _obs_check_exit=1
  else
    # Run the check; capture exit code without letting set -e kill us
    _obs_check_exit=0
    "$OBS_CHECK" "${_obs_check_args[@]}" || _obs_check_exit=$?
  fi

  case "$_obs_check_exit" in
    0)
      # Contract collector running and healthy — skip local stack
      echo "[obs] Contract collector detected, skipping local OTEL stack"
      ;;
    2)
      # Port conflict with non-contract services — script already printed remediation
      echo "[obs] ERROR: Port conflict detected (see above)." >&2
      echo "[obs] Observability is required. Resolve the conflict or run shared stack restart (just obs-restart)." >&2
      exit 1
      ;;
    1)
      # Expected: no contract collector available
      if [ "$_obs_fallback" -eq 1 ] && [ -f "$OTEL_COMPOSE_FILE" ]; then
        echo "[obs] No contract collector found, starting local OTEL stack (fallback)"
        _include_local_otel=1
      else
        echo "[obs] ERROR: No contract collector detected and local fallback unavailable." >&2
        echo "[obs] Set OTEL_EXPORTER_OTLP_ENDPOINT to an external collector, or provide docker-compose.otel.yml fallback." >&2
        exit 1
      fi
      ;;
    *)
      echo "[obs] WARNING: obs-dev-check.sh exited with unexpected code $_obs_check_exit, skipping observability" >&2
      ;;
  esac
  fi
else
  # OBS_ENABLED off — preserve current behavior: include local OTEL compose if it exists
  if [ -f "$OTEL_COMPOSE_FILE" ]; then
    _include_local_otel=1
  fi
fi

if [ "$_include_local_otel" -eq 1 ]; then
  compose_args+=(-f "$OTEL_COMPOSE_FILE")
fi

docker compose "${compose_args[@]}" up -d

echo "Starting Dolt SQL-server from ${COMPOSE_FILE} on ${DOLT_HOST}:${DOLT_HOST_PORT}..."

for attempt in $(seq 1 "$COMPOSE_WAIT_TIMEOUT_SECONDS"); do
  if mysql --protocol=TCP -h"${DOLT_HOST}" -P"${DOLT_HOST_PORT}" -u"${DOLT_USERNAME}" -p"${DOLT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
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

# Ensure both product and test databases exist
mysql --protocol=TCP -h"${DOLT_HOST}" -P"${DOLT_HOST_PORT}" -u"${DOLT_USERNAME}" -p"${DOLT_PASSWORD}" \
  -e "CREATE DATABASE IF NOT EXISTS \`${DOLT_DATABASE}\`" 2>/dev/null || true

if [ "${TEST_SPEC_DOLT_DATABASE}" != "${DOLT_DATABASE}" ]; then
  mysql --protocol=TCP -h"${DOLT_HOST}" -P"${DOLT_HOST_PORT}" -u"${DOLT_USERNAME}" -p"${DOLT_PASSWORD}" \
    -e "CREATE DATABASE IF NOT EXISTS \`${TEST_SPEC_DOLT_DATABASE}\`" 2>/dev/null || true
fi

echo "Running mix phx.server..."
exec mix phx.server
