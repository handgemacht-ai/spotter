# Spotter Local Development Runtime
# Scope: local-dev only

set dotenv-load := false

project_root := justfile_directory()
compose_dolt := project_root / "docker-compose.dolt.yml"
compose_otel := project_root / "docker-compose.otel.yml"

export COMPOSE_PROJECT_NAME := "spotter"

# Private: check all prerequisites are installed
[private]
_check-prereqs:
    @bash {{project_root}}/scripts/runtime/prereqs.sh

# Start all services (Dolt + Phoenix)
up: _check-prereqs
    docker compose -f {{compose_dolt}} up -d 2>/dev/null || true
    bash {{project_root}}/scripts/runtime/wait-for-dolt.sh
    overmind start -f {{project_root}}/Procfile.dev -D 2>/dev/null || true

# Stop all services
down:
    #!/usr/bin/env bash
    set +e
    # Stop overmind-managed processes (Phoenix)
    overmind quit 2>/dev/null
    for i in $(seq 1 15); do
      if [ ! -S "{{project_root}}/.overmind.sock" ]; then break; fi
      sleep 1
    done
    overmind kill 2>/dev/null
    rm -f "{{project_root}}/.overmind.sock" 2>/dev/null
    # Kill any remaining process on the Phoenix port
    port="${SPOTTER_PORT:-1100}"
    pid=$(lsof -iTCP:"$port" -sTCP:LISTEN -n -P -t 2>/dev/null) || true
    if [ -n "$pid" ]; then
      kill "$pid" 2>/dev/null || true
    fi
    # Stop Docker services
    docker compose -f "{{compose_dolt}}" down --timeout 10 2>/dev/null
    # Wait for port release
    for i in $(seq 1 10); do
      if ! curl -sf --max-time 1 "http://localhost:$port" >/dev/null 2>&1; then break; fi
      sleep 1
    done
    true

# Show service health
status:
    @bash {{project_root}}/scripts/runtime/status.sh

# Tail service logs
logs:
    overmind echo

# Stop, wipe state, restart clean
reset: down
    docker compose -f {{compose_dolt}} down -v 2>/dev/null || true
    just up

# Start OTEL Collector + Jaeger (opt-in)
otel-up:
    docker compose -f {{compose_otel}} up -d

# Stop OTEL stack
otel-down:
    docker compose -f {{compose_otel}} down

# Run runtime smoke tests
test-smoke:
    bash test/scripts/smoke_test.sh
