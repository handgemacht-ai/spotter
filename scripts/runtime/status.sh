#!/usr/bin/env bash
# Report service status using ● (running), ✕ (stopped), ! (warning) symbols.
# No ANSI escapes when stdout is piped (not a TTY).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKTREE_ENV_FILE="${WORKTREE_ENV_FILE:-${PROJECT_ROOT}/.worktree.env}"

if [ -f "$WORKTREE_ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$WORKTREE_ENV_FILE"
  set +a
fi

# Disable ANSI colors when stdout is not a TTY
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  NC='\033[0m'
else
  GREEN=''
  RED=''
  YELLOW=''
  NC=''
fi

DOLT_HOST="${SPOTTER_DOLT_HOST:-127.0.0.1}"
DOLT_PORT="${SPOTTER_DOLT_HOST_PORT:-13307}"
PHX_HOST="${SPOTTER_PHX_HOST:-127.0.0.1}"
PHX_PORT="${SPOTTER_PHX_PORT:-1100}"

echo "Spotter Service Status"
echo "======================"

# --- Phoenix / web ---
PHX_HTTP_CODE="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 2 "http://${PHX_HOST}:${PHX_PORT}/" 2>/dev/null || true)"
if [[ "$PHX_HTTP_CODE" =~ ^[23] ]]; then
  printf "${GREEN}● Phoenix (web)${NC}  — running on port %s\n" "$PHX_PORT"
elif [[ "$PHX_HTTP_CODE" =~ ^4 ]]; then
  printf "${GREEN}● Phoenix (web)${NC}  — running on port %s (HTTP %s at /)\n" "$PHX_PORT" "$PHX_HTTP_CODE"
elif [[ "$PHX_HTTP_CODE" =~ ^5 ]]; then
  printf "${YELLOW}! Phoenix (web)${NC}  — running on port %s but returning HTTP %s at /\n" "$PHX_PORT" "$PHX_HTTP_CODE"
elif lsof -iTCP:"$PHX_PORT" -sTCP:LISTEN -n -P -t >/dev/null 2>&1; then
  printf "${YELLOW}! Phoenix (web)${NC}  — listening on port %s (HTTP not ready)\n" "$PHX_PORT"
else
  printf "${RED}✕ Phoenix (web)${NC}  — stopped (port %s)\n" "$PHX_PORT"
fi

# --- Dolt / database ---
if docker compose -f "$PROJECT_ROOT/docker-compose.dolt.yml" ps --status running 2>/dev/null | grep -q dolt; then
  printf "${GREEN}● Dolt (database)${NC} — running on port %s\n" "$DOLT_PORT"
elif docker ps 2>/dev/null | grep -q dolt; then
  printf "${GREEN}● Dolt (database)${NC} — running on port %s\n" "$DOLT_PORT"
else
  printf "${RED}✕ Dolt (database)${NC} — stopped (port %s)\n" "$DOLT_PORT"
fi

# --- OTEL (shared or local fallback) ---
JAEGER_SHARED_PORT="${OBS_JAEGER_UI_PORT:-14686}"
JAEGER_LOCAL_PORT="${SPOTTER_LOCAL_JAEGER_PORT:-16686}"
if curl -sf "http://127.0.0.1:${JAEGER_SHARED_PORT}/" >/dev/null 2>&1; then
  printf "${GREEN}● Jaeger (OTEL)${NC}  — shared stack running on port %s\n" "$JAEGER_SHARED_PORT"
elif curl -sf "http://127.0.0.1:${JAEGER_LOCAL_PORT}/" >/dev/null 2>&1; then
  printf "${YELLOW}! Jaeger (OTEL)${NC}  — local fallback running on port %s\n" "$JAEGER_LOCAL_PORT"
else
  printf "${YELLOW}! Jaeger (OTEL)${NC}  — not running (start with: just otel-up)\n"
fi
