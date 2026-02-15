#!/usr/bin/env bash
set -euo pipefail

# Fail fast if no API key
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: ANTHROPIC_API_KEY is required" >&2
  exit 1
fi

# Ensure Claude home dirs exist
mkdir -p "${HOME}/.claude/projects"

# Run migrations
mix ecto.migrate

# Configure live project (transcripts dir, project pattern)
mix spotter.live.configure

# Start tmux session with Claude if not already running
REPO_DIR="${SPOTTER_LIVE_REPO_DIR:-/workspace}"
if ! tmux has-session -t spotter-live 2>/dev/null; then
  tmux new-session -d -s spotter-live -c "${REPO_DIR}" \
    "claude --dangerously-skip-permissions --plugin-dir /opt/spotter-plugin"
fi

# Start Phoenix server (foreground)
exec mix phx.server
