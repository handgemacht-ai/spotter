#!/usr/bin/env bash
set -euo pipefail

# Fail fast if no API key
if [ -z "${SPOTTER_ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: SPOTTER_ANTHROPIC_API_KEY is required" >&2
  exit 1
fi

# Ensure mix tools exist for the runtime user
mkdir -p "${HOME}/.mix"
mix local.hex --force
mix local.rebar --force

# Ensure Claude home dirs exist
mkdir -p "${HOME}/.claude/projects"

# Ensure frontend assets exist (self-heal if missing/empty)
ASSET_PATH="/app/priv/static/assets/app.js"
if [ ! -s "$ASSET_PATH" ]; then
  echo "WARNING: $ASSET_PATH missing or empty, rebuilding assets..." >&2
  node assets/build.js
  if [ ! -s "$ASSET_PATH" ]; then
    echo "ERROR: Asset rebuild failed — $ASSET_PATH still missing or empty. Cannot start." >&2
    exit 1
  fi
  echo "Asset rebuild successful." >&2
fi

# Run migrations
mix ecto.migrate

# Configure live project (transcripts dir, project pattern)
mix spotter.live.configure

# Start tmux session with Claude if not already running
REPO_DIR="${SPOTTER_LIVE_REPO_DIR:-/workspace}"
if ! tmux has-session -t spotter-live 2>/dev/null; then
  tmux new-session -d -s spotter-live -c "${REPO_DIR}" \
    "SPOTTER_URL=http://localhost:1100 claude --dangerously-skip-permissions --plugin-dir /opt/spotter-plugin"
fi

# Start Phoenix server (foreground)
exec mix phx.server
