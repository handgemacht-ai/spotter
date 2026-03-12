#!/usr/bin/env bash
# Install repo-local dev dependencies required by `just up`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
WORKTREE_ENV_FILE="${WORKTREE_ENV_FILE:-${PROJECT_ROOT}/.worktree.env}"

if [ -f "$WORKTREE_ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$WORKTREE_ENV_FILE"
  set +a
fi

needs_mix=0
needs_npm=0

if [[ ! -d "$PROJECT_ROOT/deps" ]]; then
  needs_mix=1
fi

if [[ "${SPOTTER_DISABLE_ASSET_WATCH:-0}" != "1" && ! -d "$PROJECT_ROOT/assets/node_modules" ]]; then
  needs_npm=1
fi

if [[ "$needs_mix" -eq 0 && "$needs_npm" -eq 0 ]]; then
  exit 0
fi

echo "Bootstrapping local dev dependencies..."

if [[ "$needs_mix" -eq 1 ]]; then
  echo "Running mix deps.get..."
  (
    cd "$PROJECT_ROOT"
    mix deps.get
  )
fi

if [[ "$needs_npm" -eq 1 ]]; then
  assets_dir="$PROJECT_ROOT/assets"

  if [[ -f "$assets_dir/package-lock.json" ]]; then
    npm_args=(ci)
    npm_label="npm ci"
  else
    npm_args=(install)
    npm_label="npm install"
  fi

  echo "Running ${npm_label}..."
  (
    cd "$assets_dir"
    npm "${npm_args[@]}"
  )
fi

exit 0
