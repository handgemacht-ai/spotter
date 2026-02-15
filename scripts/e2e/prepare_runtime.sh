#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SPOTTER_ANTHROPIC_API_KEY:-}" ]]; then
  echo "SPOTTER_ANTHROPIC_API_KEY is required for live Claude E2E" >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is not installed in container" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "claude CLI is not installed in container" >&2
  exit 1
fi

claude_home="${HOME}/.claude"
projects_dir="${claude_home}/projects"

mkdir -p "${projects_dir}"

echo "E2E runtime preflight"
echo "  HOME: ${HOME}"
echo "  claude projects dir: ${projects_dir}"
echo "  tmux version: $(tmux -V)"
echo "  claude version: $(claude --version)"
