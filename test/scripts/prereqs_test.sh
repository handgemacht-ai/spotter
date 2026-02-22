#!/usr/bin/env bash
# Tests for scripts/runtime/prereqs.sh
# Run: bash test/scripts/prereqs_test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PREREQS="$PROJECT_ROOT/scripts/runtime/prereqs.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== prereqs.sh tests ==="

# --- Test: script exists and is executable ---
echo ""
echo "--- Existence and permissions ---"

if [[ -f "$PREREQS" ]]; then
  pass "prereqs.sh exists"
else
  fail "prereqs.sh does not exist at scripts/runtime/prereqs.sh"
fi

if [[ -x "$PREREQS" ]]; then
  pass "prereqs.sh is executable"
else
  fail "prereqs.sh is not executable"
fi

# --- Test: exits 0 when all prereqs are met ---
echo ""
echo "--- Happy path (prereqs available) ---"

# On a dev machine with just, docker installed, prereqs should pass
if output=$("$PREREQS" 2>&1); then
  pass "exits 0 when prerequisites are met"
else
  # This may fail on CI where prereqs aren't installed — that's expected
  fail "exits non-zero even though prereqs should be available (exit: $?)"
fi

# --- Test: output is pipe-friendly (no raw ANSI when piped) ---
echo ""
echo "--- Pipe-friendly output ---"

output=$("$PREREQS" 2>&1 | cat) || true
# When piped (not a TTY), output should not contain ANSI escape codes
if echo "$output" | grep -qP '\x1b\['; then
  fail "output contains ANSI escape codes when piped (not TTY)"
else
  pass "output is clean when piped (no ANSI escapes)"
fi

# --- Test: checks for required tools ---
echo ""
echo "--- Required tool detection ---"

# Create a temp dir with a fake PATH that's missing 'just'
FAKE_PATH=$(mktemp -d)
trap "rm -rf $FAKE_PATH" EXIT

# Copy only essential commands needed by the script itself
for cmd in bash echo printf cat grep test [ mkdir; do
  real=$(command -v "$cmd" 2>/dev/null) || true
  if [[ -n "$real" && -f "$real" ]]; then
    cp "$real" "$FAKE_PATH/" 2>/dev/null || true
  fi
done

# Run with a PATH that's missing 'just', 'overmind', 'docker'
if PATH="$FAKE_PATH" "$PREREQS" >/dev/null 2>&1; then
  fail "should exit non-zero when required tools are missing"
else
  pass "exits non-zero when required tools are missing"
fi

# Verify error output mentions the missing tool
missing_output=$(PATH="$FAKE_PATH" "$PREREQS" 2>&1) || true
if echo "$missing_output" | grep -qi "install\|missing\|not found\|required"; then
  pass "error output includes actionable install guidance"
else
  fail "error output lacks actionable install guidance: $missing_output"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
