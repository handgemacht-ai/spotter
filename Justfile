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
    #!/usr/bin/env bash
    set -euo pipefail
    workspace_obs="{{project_root}}/../../../.runtime/docker/obs-up.sh"
    if [[ -x "$workspace_obs" ]]; then
      "$workspace_obs" --quiet
    else
      docker compose -f {{compose_otel}} up -d 2>/dev/null || true
    fi
    docker compose -f {{compose_dolt}} up -d 2>/dev/null || true
    bash {{project_root}}/scripts/runtime/wait-for-dolt.sh

    phx_host="${SPOTTER_PHX_HOST:-127.0.0.1}"
    phx_port="${SPOTTER_PHX_PORT:-1100}"
    needs_restart=1

    if overmind status >/dev/null 2>&1; then
      phx_http_code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 2 "http://${phx_host}:${phx_port}/" 2>/dev/null || true)"
      if [[ "$phx_http_code" =~ ^[234] ]]; then
        echo "Phoenix already running (HTTP ${phx_http_code}); leaving overmind session unchanged."
        needs_restart=0
      else
        echo "Overmind is running but Phoenix is not healthy (HTTP ${phx_http_code:-000}); trying graceful restart..."
        overmind stop phoenix >/dev/null 2>&1 || true
        sleep 1
        overmind restart phoenix >/dev/null 2>&1 || true

        if WAIT_TIMEOUT="${SPOTTER_PHX_GRACEFUL_TIMEOUT:-15}" bash {{project_root}}/scripts/runtime/wait-for-phoenix.sh >/dev/null 2>&1; then
          echo "Phoenix recovered after graceful restart."
          needs_restart=0
        else
          echo "Graceful restart did not recover Phoenix; recycling overmind session..."
        fi
      fi
    fi

    if [ "$needs_restart" -eq 1 ]; then
      if overmind status >/dev/null 2>&1 || [ -S "{{project_root}}/.overmind.sock" ]; then
        overmind quit 2>/dev/null || true
        for i in $(seq 1 10); do
          if [ ! -S "{{project_root}}/.overmind.sock" ]; then break; fi
          sleep 1
        done
        overmind kill 2>/dev/null || true
        rm -f "{{project_root}}/.overmind.sock" 2>/dev/null || true
      fi
      overmind start -f {{project_root}}/Procfile.dev -D 2>/dev/null || true
    fi

    bash {{project_root}}/scripts/runtime/wait-for-phoenix.sh

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

# Start OTEL stack explicitly
otel-up:
    #!/usr/bin/env bash
    set -euo pipefail
    workspace_obs="{{project_root}}/../../../.runtime/docker/obs-up.sh"
    if [[ -x "$workspace_obs" ]]; then
      "$workspace_obs"
    else
      docker compose -f {{compose_otel}} up -d
    fi

# Stop OTEL stack
otel-down:
    #!/usr/bin/env bash
    set -euo pipefail
    workspace_obs="{{project_root}}/../../../.runtime/docker/obs-down.sh"
    if [[ -x "$workspace_obs" ]]; then
      "$workspace_obs"
    else
      docker compose -f {{compose_otel}} down
    fi

# Restart OTEL stack
otel-restart:
    #!/usr/bin/env bash
    set -euo pipefail
    workspace_obs="{{project_root}}/../../../.runtime/docker/obs-restart.sh"
    if [[ -x "$workspace_obs" ]]; then
      "$workspace_obs"
    else
      docker compose -f {{compose_otel}} down
      docker compose -f {{compose_otel}} up -d
    fi

# Show OTEL stack status
otel-status:
    #!/usr/bin/env bash
    set -euo pipefail
    workspace_obs="{{project_root}}/../../../.runtime/docker/obs-status.sh"
    if [[ -x "$workspace_obs" ]]; then
      "$workspace_obs"
    else
      docker compose -f {{compose_otel}} ps
    fi

# Run runtime smoke tests
test-smoke:
    bash test/scripts/smoke_test.sh
