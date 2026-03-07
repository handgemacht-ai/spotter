#!/usr/bin/env bash
set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is not installed in container" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "claude CLI is not installed in container" >&2
  exit 1
fi

claude_projects="${HOME}/.claude/projects"
agents_projects="${HOME}/.claude_agents/projects"

mkdir -p "${claude_projects}" "${agents_projects}"

echo "E2E runtime preflight"
echo "  HOME: ${HOME}"
echo "  claude projects dir: ${claude_projects}"
echo "  agents projects dir: ${agents_projects}"
echo "  tmux version: $(tmux -V)"
echo "  claude version: $(claude --version)"
