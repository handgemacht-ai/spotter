#!/usr/bin/env bash
# Smoke tests for Spotter local dev runtime
# Run: bash test/scripts/smoke_test.sh
# Or:  just test-smoke
#
# These tests exercise the full runtime lifecycle (just up/down).
# They start and stop real services, so they're slower than unit tests.
# Each test is independent with its own setup/teardown.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
JUSTFILE="$PROJECT_ROOT/Justfile"

PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  SKIP: $1"; }

# Port Phoenix listens on (default dev port)
PHOENIX_PORT="${SPOTTER_PORT:-1100}"

# Ensure just is available
if ! command -v just &>/dev/null; then
  echo "ERROR: 'just' is required to run smoke tests"
  exit 1
fi

if [[ ! -f "$JUSTFILE" ]]; then
  echo "ERROR: Justfile not found at $PROJECT_ROOT"
  exit 1
fi

# Helper: ensure services are down before/after each test
ensure_down() {
  just --justfile "$JUSTFILE" down >/dev/null 2>&1 || true
  # Give processes a moment to release ports
  sleep 1
}

# Helper: check if a port is responding to HTTP
port_responds() {
  local port="$1"
  local timeout="${2:-5}"
  curl -sf --max-time "$timeout" "http://localhost:$port" >/dev/null 2>&1 ||
    curl -sf --max-time "$timeout" "http://localhost:$port" -o /dev/null -w '%{http_code}' 2>/dev/null | grep -qP '^[2-3]'
}

# Helper: wait for port to respond
wait_for_port() {
  local port="$1"
  local max_wait="${2:-30}"
  local elapsed=0
  while [[ $elapsed -lt $max_wait ]]; do
    if port_responds "$port" 2; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

echo "=== Spotter Runtime Smoke Tests ==="
echo "Phoenix port: $PHOENIX_PORT"
echo ""

# ============================================================
# Test 1: Happy path — just up → port responds → status → down
# ============================================================
echo "--- Test 1: Happy path lifecycle ---"

ensure_down

if just --justfile "$JUSTFILE" up 2>&1; then
  pass "just up exits 0"
else
  fail "just up exits non-zero"
fi

if wait_for_port "$PHOENIX_PORT" 45; then
  pass "Phoenix responds on port $PHOENIX_PORT"
else
  fail "Phoenix not responding on port $PHOENIX_PORT after 45s"
fi

# Check status shows services running
status_output=$(just --justfile "$JUSTFILE" status 2>&1) || true
if echo "$status_output" | grep -qP '●|running|up'; then
  pass "just status shows services running"
else
  fail "just status does not show running services: $status_output"
fi

# Clean shutdown
if just --justfile "$JUSTFILE" down 2>&1; then
  pass "just down exits 0"
else
  fail "just down exits non-zero"
fi

sleep 2

# ============================================================
# Test 2: Missing prereqs — mock missing overmind
# ============================================================
echo ""
echo "--- Test 2: Missing overmind detection ---"

# Temporarily hide overmind from PATH
REAL_PATH="$PATH"
TEMP_BIN=$(mktemp -d)
# Symlink everything except overmind
for bin_dir in $(echo "$PATH" | tr ':' '\n'); do
  for f in "$bin_dir"/*; do
    fname=$(basename "$f" 2>/dev/null) || continue
    if [[ "$fname" != "overmind" && ! -e "$TEMP_BIN/$fname" ]]; then
      ln -sf "$f" "$TEMP_BIN/$fname" 2>/dev/null || true
    fi
  done
done

if PATH="$TEMP_BIN" just --justfile "$JUSTFILE" _check-prereqs >/dev/null 2>&1; then
  fail "should fail when overmind is missing"
else
  pass "exits non-zero when overmind is missing"
fi

prereq_output=$(PATH="$TEMP_BIN" just --justfile "$JUSTFILE" _check-prereqs 2>&1) || true
if echo "$prereq_output" | grep -qi "overmind"; then
  pass "error message mentions overmind"
else
  fail "error message does not mention overmind: $prereq_output"
fi

rm -rf "$TEMP_BIN"

# ============================================================
# Test 3: Missing prereqs — mock missing docker
# ============================================================
echo ""
echo "--- Test 3: Missing docker detection ---"

TEMP_BIN=$(mktemp -d)
for bin_dir in $(echo "$PATH" | tr ':' '\n'); do
  for f in "$bin_dir"/*; do
    fname=$(basename "$f" 2>/dev/null) || continue
    if [[ "$fname" != "docker" && ! -e "$TEMP_BIN/$fname" ]]; then
      ln -sf "$f" "$TEMP_BIN/$fname" 2>/dev/null || true
    fi
  done
done

if PATH="$TEMP_BIN" just --justfile "$JUSTFILE" _check-prereqs >/dev/null 2>&1; then
  fail "should fail when docker is missing"
else
  pass "exits non-zero when docker is missing"
fi

prereq_output=$(PATH="$TEMP_BIN" just --justfile "$JUSTFILE" _check-prereqs 2>&1) || true
if echo "$prereq_output" | grep -qi "docker"; then
  pass "error message mentions docker"
else
  fail "error message does not mention docker: $prereq_output"
fi

rm -rf "$TEMP_BIN"

# ============================================================
# Test 4: Idempotency — just up twice is safe
# ============================================================
echo ""
echo "--- Test 4: Idempotency (just up twice) ---"

ensure_down

just --justfile "$JUSTFILE" up >/dev/null 2>&1 || true
sleep 2

# Second up should not fail
if just --justfile "$JUSTFILE" up 2>&1; then
  pass "second just up exits 0 (idempotent)"
else
  fail "second just up exits non-zero (not idempotent)"
fi

if wait_for_port "$PHOENIX_PORT" 30; then
  pass "Phoenix still responds after double up"
else
  fail "Phoenix not responding after double up"
fi

ensure_down

# ============================================================
# Test 5: Readiness timeout — wait-for-dolt exits non-zero
# ============================================================
echo ""
echo "--- Test 5: Readiness timeout ---"

WAIT_SCRIPT="$PROJECT_ROOT/scripts/runtime/wait-for-dolt.sh"

if [[ -x "$WAIT_SCRIPT" ]]; then
  start_time=$(date +%s)
  DOLT_PORT=19999 WAIT_TIMEOUT=3 "$WAIT_SCRIPT" >/dev/null 2>&1 || exit_code=$?
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  if [[ ${exit_code:-0} -ne 0 ]]; then
    pass "wait-for-dolt exits non-zero on unreachable port"
  else
    fail "wait-for-dolt exits 0 on unreachable port"
  fi

  if [[ $elapsed -le 10 ]]; then
    pass "timeout respected (${elapsed}s)"
  else
    fail "timeout not respected (${elapsed}s, expected ≤10)"
  fi
else
  skip "wait-for-dolt.sh not found"
  skip "wait-for-dolt.sh not found"
fi

# ============================================================
# Test 6: Clean shutdown — no orphan processes or containers
# ============================================================
echo ""
echo "--- Test 6: Clean shutdown ---"

ensure_down

just --justfile "$JUSTFILE" up >/dev/null 2>&1 || true
wait_for_port "$PHOENIX_PORT" 30 || true
just --justfile "$JUSTFILE" down >/dev/null 2>&1 || true
sleep 3

# Check no Phoenix process on port
if port_responds "$PHOENIX_PORT" 2; then
  fail "port $PHOENIX_PORT still responding after just down"
else
  pass "port $PHOENIX_PORT released after just down"
fi

# Check no orphan overmind processes for this project
if pgrep -f "overmind.*Procfile.dev" >/dev/null 2>&1; then
  fail "orphan overmind processes found after just down"
else
  pass "no orphan overmind processes"
fi

# Check Dolt container is stopped (scoped to our compose project)
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.dolt.yml"
if [[ -f "$COMPOSE_FILE" ]]; then
  running=$(docker compose -f "$COMPOSE_FILE" ps --status running -q 2>/dev/null)
  if [[ -n "$running" ]]; then
    fail "Dolt container still running after just down (compose project)"
  else
    pass "Dolt container stopped after just down"
  fi
else
  skip "docker-compose.dolt.yml not found"
fi

# Final cleanup
ensure_down

# ============================================================
# Summary
# ============================================================
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $SKIP skipped ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
