#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="docker-compose.e2e.yml"

cleanup() {
  docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup EXIT

docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans || true

docker compose -f "${COMPOSE_FILE}" up \
  --build \
  --abort-on-container-exit \
  --exit-code-from playwright
