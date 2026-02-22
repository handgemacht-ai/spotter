#!/usr/bin/env bash
# Tests for scripts/runtime/status.sh
# Run: bash test/scripts/status_test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATUS="$PROJECT_ROOT/scripts/runtime/status.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== status.sh tests ==="

# --- Test: script exists and is executable ---
echo ""
echo "--- Existence and permissions ---"

if [[ -f "$STATUS" ]]; then
  pass "status.sh exists"
else
  fail "status.sh does not exist at scripts/runtime/status.sh"
fi

if [[ -x "$STATUS" ]]; then
  pass "status.sh is executable"
else
  fail "status.sh is not executable"
fi

# --- Test: runs without error ---
echo ""
echo "--- Execution ---"

if output=$("$STATUS" 2>&1); then
  pass "exits 0 on execution"
else
  # status.sh may exit non-zero if services are down — that's acceptable
  # but it should NOT crash with a bash error
  if echo "$output" | grep -qi "syntax error\|unbound variable\|command not found"; then
    fail "script has a bash error: $output"
  else
    pass "exits non-zero (services may be down) but no script errors"
  fi
fi

# --- Test: output contains status symbols ---
echo ""
echo "--- Status symbols in output ---"

output=$("$STATUS" 2>&1) || true

# Should use ●, ✕, or ! symbols for status indicators
if echo "$output" | grep -qP '[●✕!]|running|stopped|down|up'; then
  pass "output contains status indicators"
else
  fail "output lacks status indicators (●/✕/!): $output"
fi

# --- Test: pipe-friendly (no ANSI when piped) ---
echo ""
echo "--- Pipe-friendly output ---"

piped_output=$("$STATUS" 2>&1 | cat) || true
if echo "$piped_output" | grep -qP '\x1b\['; then
  fail "output contains ANSI escape codes when piped"
else
  pass "output is clean when piped (no ANSI escapes)"
fi

# --- Test: checks key services ---
echo ""
echo "--- Service coverage ---"

output=$("$STATUS" 2>&1) || true

# Should report on Phoenix and Dolt at minimum
if echo "$output" | grep -qi "phoenix\|phx\|web\|endpoint"; then
  pass "reports on Phoenix/web service"
else
  fail "does not report on Phoenix/web service"
fi

if echo "$output" | grep -qi "dolt\|database\|db"; then
  pass "reports on Dolt/database service"
else
  fail "does not report on Dolt/database service"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
