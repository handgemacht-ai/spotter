#!/usr/bin/env bash
set -euo pipefail

# Configuration
BASE_PORT=1100
PORT_STEP=2

# Determine the worktree root
WORKTREE_ROOT="$(git rev-parse --show-toplevel)"
cd "$WORKTREE_ROOT"

# Auto-detect Tailscale IP
if command -v tailscale &>/dev/null; then
  TS_IP="$(tailscale ip -4 2>/dev/null || true)"
fi

if [ -z "${TS_IP:-}" ]; then
  echo "WARNING: Could not detect Tailscale IP. Using 127.0.0.1"
  TS_IP="127.0.0.1"
fi

# Convert dotted IP to Elixir tuple format: 100.105.15.12 -> {100, 105, 15, 12}
IFS='.' read -ra IP_PARTS <<< "$TS_IP"
ELIXIR_IP="{${IP_PARTS[0]}, ${IP_PARTS[1]}, ${IP_PARTS[2]}, ${IP_PARTS[3]}}"

# Determine worktree index for port calculation
this_path="$(realpath "$WORKTREE_ROOT")"
main_path="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
main_path="$(realpath "$main_path")"

if [ "$this_path" = "$main_path" ]; then
  INDEX=0
else
  INDEX=0
  while IFS= read -r line; do
    wt_path="$(echo "$line" | sed 's/^worktree //')"
    wt_path="$(realpath "$wt_path")"
    INDEX=$((INDEX + 1))
    if [ "$wt_path" = "$this_path" ]; then
      break
    fi
  done < <(git worktree list --porcelain | grep '^worktree ')
fi

PORT=$((BASE_PORT + INDEX * PORT_STEP))
echo "$PORT" > .port
echo "==> Worktree index: $INDEX, assigned port: $PORT"
echo "==> Tailscale IP: $TS_IP"

# Generate config/dev.local.exs
cat > config/dev.local.exs << ELIXIR_EOF
import Config

config :spotter, SpotterWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: ${PORT}]
ELIXIR_EOF
echo "==> Generated config/dev.local.exs (ip: $TS_IP, port: $PORT)"

# Generate .mcp.json
cat > .mcp.json << JSON_EOF
{
  "mcpServers": {
    "tidewave": {
      "type": "http",
      "url": "http://${TS_IP}:${PORT}/tidewave/mcp"
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
JSON_EOF
echo "==> Generated .mcp.json (url: http://${TS_IP}:${PORT}/tidewave/mcp)"

# Fetch deps and set up database
echo "==> Fetching dev dependencies..."
mix deps.get
echo "==> Fetching test dependencies..."
MIX_ENV=test mix deps.get
echo "==> Running migrations..."
mix ecto.migrate

# Create tmux session for this worktree
BRANCH="$(git branch --show-current 2>/dev/null || echo "detached")"
SESSION_NAME="spotter-${BRANCH}"

if command -v tmux &>/dev/null; then
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "==> tmux session '$SESSION_NAME' already exists"
  else
    tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE_ROOT" 'claude --dangerously-skip-permissions'
    echo "==> Created tmux session '$SESSION_NAME'"
  fi
fi

echo "==> Setup complete! Attach with: tmux attach -t $SESSION_NAME"
