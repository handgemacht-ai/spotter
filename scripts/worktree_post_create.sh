#!/usr/bin/env bash
set -euo pipefail

WORKTREE_ROOT="${WORKTREE_PATH:-$(pwd)}"
WORKTREE_ENV_FILE="${WORKTREE_ENV_FILE:-${WORKTREE_ROOT}/.worktree.env}"

if [ ! -f "$WORKTREE_ENV_FILE" ]; then
  echo "[spotter worktree post-create] Missing env file: $WORKTREE_ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$WORKTREE_ENV_FILE"
set +a

cd "$WORKTREE_ROOT"

if [ -z "${SPOTTER_PHX_PORT:-}" ] && [ -n "${SPOTTER_PORT:-}" ]; then
  SPOTTER_PHX_PORT="$SPOTTER_PORT"
fi
if [ -z "${SPOTTER_PORT:-}" ] && [ -n "${SPOTTER_PHX_PORT:-}" ]; then
  SPOTTER_PORT="$SPOTTER_PHX_PORT"
fi
if [ -z "${SPOTTER_DOLT_HOST_PORT:-}" ] && [ -n "${SPOTTER_DOLT_PORT:-}" ]; then
  SPOTTER_DOLT_HOST_PORT="$SPOTTER_DOLT_PORT"
fi
if [ -z "${SPOTTER_DOLT_PORT:-}" ] && [ -n "${SPOTTER_DOLT_HOST_PORT:-}" ]; then
  SPOTTER_DOLT_PORT="$SPOTTER_DOLT_HOST_PORT"
fi

SPOTTER_PHX_PORT="${SPOTTER_PHX_PORT:-1100}"
SPOTTER_PORT="${SPOTTER_PORT:-$SPOTTER_PHX_PORT}"
SPOTTER_DOLT_HOST_PORT="${SPOTTER_DOLT_HOST_PORT:-13307}"
SPOTTER_DOLT_PORT="${SPOTTER_DOLT_PORT:-$SPOTTER_DOLT_HOST_PORT}"

TS_IP="127.0.0.1"
if command -v tailscale >/dev/null 2>&1; then
  TS_IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
fi
if [ -z "${TS_IP:-}" ]; then
  TS_IP="127.0.0.1"
fi

cat > "${WORKTREE_ROOT}/config/dev.local.exs" <<ELIXIR_EOF
import Config

config :spotter, SpotterWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: ${SPOTTER_PHX_PORT}]
ELIXIR_EOF

printf "%s\n" "$SPOTTER_PHX_PORT" > "${WORKTREE_ROOT}/.port"

cat > "${WORKTREE_ROOT}/.mcp.json" <<MCP_EOF
{
  "mcpServers": {
    "tidewave": {
      "type": "http",
      "url": "http://${TS_IP}:${SPOTTER_PHX_PORT}/tidewave/mcp"
    },
    "chrome-devtools": {
      "command": "npx",
      "args": [
        "-y",
        "chrome-devtools-mcp@latest",
        "--headless",
        "--chromeArg=--no-sandbox",
        "--chromeArg=--disable-setuid-sandbox"
      ]
    }
  }
}
MCP_EOF

if [ -n "${WORKTREE_MAIN_PATH:-}" ] && [ "$WORKTREE_MAIN_PATH" != "$WORKTREE_ROOT" ]; then
  if [ -L "${WORKTREE_ROOT}/.envrc" ] && [ ! -e "${WORKTREE_ROOT}/.envrc" ]; then
    rm -f "${WORKTREE_ROOT}/.envrc"
  fi
  if [ ! -e "${WORKTREE_ROOT}/.envrc" ] && [ -e "${WORKTREE_MAIN_PATH}/.envrc" ]; then
    cp "${WORKTREE_MAIN_PATH}/.envrc" "${WORKTREE_ROOT}/.envrc"
    if command -v direnv >/dev/null 2>&1; then
      direnv allow "$WORKTREE_ROOT" >/dev/null 2>&1 || true
    fi
  fi
fi
