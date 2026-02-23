#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

workspace_obs="${ROOT}/../../../.runtime/docker/obs-status.sh"
if [[ -x "$workspace_obs" ]]; then
  "$workspace_obs"
else
  docker compose -f docker-compose.otel.yml ps
fi
