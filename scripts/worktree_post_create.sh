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

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

upsert_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp_file

  tmp_file="$(mktemp)"
  if [ -f "$file" ]; then
    grep -v "^${key}=" "$file" > "$tmp_file" || true
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
  mv "$tmp_file" "$file"
}

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

TAILNET_ZONE="${TAILNET_INGRESS_ZONE:-dev.handgemacht.internal}"
PROJECT_SLUG="spotter"
WORKTREE_SLUG="$(slugify "${WORKTREE_NAME:-main}")"
PREVIEW_HOST="${PROJECT_SLUG}--${WORKTREE_SLUG}.${TAILNET_ZONE}"
PREVIEW_URL="http://${PREVIEW_HOST}"

upsert_env_var "${WORKTREE_ENV_FILE}" "TAILNET_INGRESS_ZONE" "${TAILNET_ZONE}"
upsert_env_var "${WORKTREE_ENV_FILE}" "PREVIEW_HOST" "${PREVIEW_HOST}"
upsert_env_var "${WORKTREE_ENV_FILE}" "PREVIEW_URL" "${PREVIEW_URL}"

cat > "${WORKTREE_ROOT}/config/dev.local.exs" <<ELIXIR_EOF
import Config

config :spotter, SpotterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: ${SPOTTER_PHX_PORT}]
ELIXIR_EOF

printf "%s\n" "$SPOTTER_PHX_PORT" > "${WORKTREE_ROOT}/.port"

cat > "${WORKTREE_ROOT}/.mcp.json" <<MCP_EOF
{
  "mcpServers": {
    "tidewave": {
      "type": "http",
      "url": "http://localhost:${SPOTTER_PHX_PORT}/tidewave/mcp"
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
