#!/usr/bin/env bash
# Report service status using ● (running), ✕ (stopped), ! (warning) symbols.
# No ANSI escapes when stdout is piped (not a TTY).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
PHX_PORT="${SPOTTER_PHX_PORT:-1100}"

echo "Spotter Service Status"
echo "======================"

# --- Phoenix / web ---
if curl -sf "http://127.0.0.1:${PHX_PORT}/" >/dev/null 2>&1; then
  printf "${GREEN}● Phoenix (web)${NC}  — running on port %s\n" "$PHX_PORT"
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

# --- OTEL (optional) ---
if curl -sf "http://127.0.0.1:16686/" >/dev/null 2>&1; then
  printf "${GREEN}● Jaeger (OTEL)${NC}  — running on port 16686\n"
else
  printf "${YELLOW}! Jaeger (OTEL)${NC}  — not running (opt-in: just otel-up)\n"
fi
