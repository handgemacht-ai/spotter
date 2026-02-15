#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

mkdir -p tmp/otel
chmod 777 tmp/otel
rm -f tmp/otel/spotter-traces.json

docker compose -f docker-compose.otel.yml up -d

cat <<'EOF'
OTEL collector is running.

Next:
  export OTEL_EXPORTER=otlp
  export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
  mix phx.server

Trace artifacts:
  - JSON file for Claude/Codex: tmp/otel/spotter-traces.json
  - Jaeger UI: http://localhost:16686
EOF
