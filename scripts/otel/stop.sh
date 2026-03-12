#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

workspace_obs="${ROOT}/../.runtime/docker/obs-down.sh"
if [[ -x "$workspace_obs" ]]; then
  "$workspace_obs"
else
  echo "[obs] Shared observability stack helper not found at $workspace_obs" >&2
  exit 1
fi
