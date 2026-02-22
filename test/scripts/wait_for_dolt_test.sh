#!/usr/bin/env bash
# Tests for scripts/runtime/wait-for-dolt.sh
# Run: bash test/scripts/wait_for_dolt_test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WAIT_SCRIPT="$PROJECT_ROOT/scripts/runtime/wait-for-dolt.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== wait-for-dolt.sh tests ==="

# --- Test: script exists and is executable ---
echo ""
echo "--- Existence and permissions ---"

if [[ -f "$WAIT_SCRIPT" ]]; then
  pass "wait-for-dolt.sh exists"
else
  fail "wait-for-dolt.sh does not exist at scripts/runtime/wait-for-dolt.sh"
fi

if [[ -x "$WAIT_SCRIPT" ]]; then
  pass "wait-for-dolt.sh is executable"
else
  fail "wait-for-dolt.sh is not executable"
fi

# --- Test: supports --timeout flag or env var ---
echo ""
echo "--- Timeout support ---"

if [[ -f "$WAIT_SCRIPT" ]]; then
  script_content=$(cat "$WAIT_SCRIPT")

  if echo "$script_content" | grep -qi "timeout\|TIMEOUT\|max.*wait\|MAX_WAIT"; then
    pass "script references a timeout mechanism"
  else
    fail "script has no timeout mechanism (could hang forever)"
  fi
else
  fail "script doesn't exist (can't check timeout)"
fi

# --- Test: exits non-zero on timeout (use unreachable port) ---
echo ""
echo "--- Timeout behavior ---"

if [[ -x "$WAIT_SCRIPT" ]]; then
  # Use a very short timeout and an unreachable port to force a timeout
  start_time=$(date +%s)
  DOLT_PORT=19999 WAIT_TIMEOUT=2 "$WAIT_SCRIPT" >/dev/null 2>&1 || exit_code=$?
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  if [[ ${exit_code:-0} -ne 0 ]]; then
    pass "exits non-zero when Dolt is unreachable"
  else
    fail "exits 0 even when Dolt is unreachable"
  fi

  # Should timeout within a reasonable time (not hang)
  if [[ $elapsed -le 10 ]]; then
    pass "respects timeout (completed in ${elapsed}s)"
  else
    fail "took ${elapsed}s — may not respect timeout"
  fi
else
  fail "script not executable (can't test timeout)"
  fail "script not executable (can't test timeout duration)"
fi

# --- Test: pipe-friendly output ---
echo ""
echo "--- Pipe-friendly output ---"

if [[ -x "$WAIT_SCRIPT" ]]; then
  output=$(DOLT_PORT=19999 WAIT_TIMEOUT=2 "$WAIT_SCRIPT" 2>&1 | cat) || true
  if echo "$output" | grep -qP '\x1b\['; then
    fail "output contains ANSI escape codes when piped"
  else
    pass "output is clean when piped (no ANSI escapes)"
  fi
else
  fail "script not executable (can't test output)"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
