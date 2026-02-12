#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

docker compose -f docker-compose.otel.yml down --remove-orphans
