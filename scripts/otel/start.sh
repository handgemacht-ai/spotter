#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

mkdir -p tmp/otel
chmod 777 tmp/otel
rm -f tmp/otel/spotter-traces.json

workspace_obs="${ROOT}/../.runtime/docker/obs-up.sh"
if [[ -x "$workspace_obs" ]]; then
  "$workspace_obs"
  endpoint="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:14318}"
else
  echo "[obs] Shared observability stack helper not found at $workspace_obs" >&2
  echo "[obs] Start it from the workspace root with: cd \"$ROOT/..\" && just obs-up" >&2
  exit 1
fi

cat <<EOF
OTEL collector is running.

Next:
  export OTEL_EXPORTER=otlp
  export OTEL_EXPORTER_OTLP_ENDPOINT=${endpoint}
  mix phx.server

Trace artifacts:
  - JSON file for Claude/Codex: tmp/otel/spotter-traces.json
  - Jaeger UI: http://localhost:14686
EOF
