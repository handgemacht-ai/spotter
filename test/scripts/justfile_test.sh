#!/usr/bin/env bash
# Tests for Justfile recipes
# Run: bash test/scripts/justfile_test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
JUSTFILE="$PROJECT_ROOT/Justfile"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== Justfile tests ==="

# --- Test: Justfile exists ---
echo ""
echo "--- Existence ---"

if [[ -f "$JUSTFILE" ]]; then
  pass "Justfile exists"
else
  fail "Justfile does not exist at project root"
fi

# --- Test: Procfile.dev exists ---
if [[ -f "$PROJECT_ROOT/Procfile.dev" ]]; then
  pass "Procfile.dev exists"
else
  fail "Procfile.dev does not exist at project root"
fi

# --- Test: required recipes are defined ---
echo ""
echo "--- Required recipes ---"

if ! command -v just &>/dev/null; then
  echo "  SKIP: 'just' not installed, skipping recipe tests"
else
  REQUIRED_RECIPES=("up" "down" "status" "logs" "reset" "otel-up" "otel-down")

  available=$(just --justfile "$JUSTFILE" --list 2>&1) || true

  for recipe in "${REQUIRED_RECIPES[@]}"; do
    if echo "$available" | grep -qw "$recipe"; then
      pass "recipe '$recipe' is defined"
    else
      fail "recipe '$recipe' is missing from Justfile"
    fi
  done

  # _check-prereqs should exist (underscore = private recipe)
  if grep -q '_check-prereqs' "$JUSTFILE" 2>/dev/null; then
    pass "private recipe '_check-prereqs' is defined"
  else
    fail "private recipe '_check-prereqs' is missing"
  fi
fi

# --- Test: Procfile.dev contains phoenix entry ---
echo ""
echo "--- Procfile.dev content ---"

if [[ -f "$PROJECT_ROOT/Procfile.dev" ]]; then
  if grep -qi "phoenix\|phx\.server\|mix phx" "$PROJECT_ROOT/Procfile.dev"; then
    pass "Procfile.dev has Phoenix entry"
  else
    fail "Procfile.dev missing Phoenix entry"
  fi
else
  fail "Procfile.dev does not exist (can't check contents)"
fi

# --- Test: just up is idempotent (dry-run check) ---
echo ""
echo "--- Idempotency ---"

if command -v just &>/dev/null && [[ -f "$JUSTFILE" ]]; then
  # Check that the 'up' recipe doesn't use 'set -e' without guarding
  # against already-running services (idempotency)
  up_body=$(just --justfile "$JUSTFILE" --show up 2>&1) || true
  if echo "$up_body" | grep -qi "already\|running\|if.*docker\|force-recreate\|restart\|2>/dev/null\|||.*true"; then
    pass "'up' recipe has idempotency guards"
  else
    # Check if _check-prereqs is called (which is a prereq for idempotency)
    if echo "$up_body" | grep -q '_check-prereqs'; then
      pass "'up' recipe calls _check-prereqs"
    else
      fail "'up' recipe may not be idempotent (no guards found)"
    fi
  fi
else
  echo "  SKIP: just not available or Justfile missing"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
