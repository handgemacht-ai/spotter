#!/usr/bin/env bash
# Tests for scripts/runtime/ensure-shared-otel.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$PROJECT_ROOT/scripts/runtime/ensure-shared-otel.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

WORKSPACE_ROOT="$TEMP_ROOT/workspace"
mkdir -p "$WORKSPACE_ROOT"

make_check() {
  local exit_code="$1"
  local script_path="$TEMP_ROOT/obs-dev-check.sh"
  cat >"$script_path" <<EOF
#!/usr/bin/env bash
exit ${exit_code}
EOF
  chmod +x "$script_path"
  printf '%s\n' "$script_path"
}

echo "=== ensure-shared-otel.sh tests ==="

echo ""
echo "--- Existence and permissions ---"

if [[ -f "$HELPER" ]]; then
  pass "ensure-shared-otel.sh exists"
else
  fail "ensure-shared-otel.sh does not exist"
fi

if [[ -x "$HELPER" ]]; then
  pass "ensure-shared-otel.sh is executable"
else
  fail "ensure-shared-otel.sh is not executable"
fi

echo ""
echo "--- Healthy shared stack passes ---"

healthy_check="$(make_check 0)"
if PROJECT_ROOT_OVERRIDE="$PROJECT_ROOT" WORKSPACE_ROOT_OVERRIDE="$WORKSPACE_ROOT" OBS_CHECK_OVERRIDE="$healthy_check" "$HELPER" >/dev/null 2>&1; then
  pass "healthy shared stack exits 0"
else
  fail "healthy shared stack should exit 0"
fi

echo ""
echo "--- Missing shared stack prints guidance ---"

missing_check="$(make_check 1)"
missing_output="$(
  PROJECT_ROOT_OVERRIDE="$PROJECT_ROOT" \
  WORKSPACE_ROOT_OVERRIDE="$WORKSPACE_ROOT" \
  OBS_CHECK_OVERRIDE="$missing_check" \
  "$HELPER" 2>&1
)" || missing_exit=$?

if [[ ${missing_exit:-0} -ne 0 ]]; then
  pass "missing shared stack exits non-zero"
else
  fail "missing shared stack should exit non-zero"
fi

if echo "$missing_output" | grep -q "just obs-up" && echo "$missing_output" | grep -q "just otel-up"; then
  pass "missing shared stack output includes setup guidance"
else
  fail "missing shared stack output does not include setup guidance: $missing_output"
fi

echo ""
echo "--- Explicit external endpoint skips shared check ---"

external_output="$(
  OTEL_EXPORTER_OTLP_ENDPOINT="https://collector.example.test:4318" \
  PROJECT_ROOT_OVERRIDE="$PROJECT_ROOT" \
  WORKSPACE_ROOT_OVERRIDE="$WORKSPACE_ROOT" \
  OBS_CHECK_OVERRIDE="/does/not/matter" \
  "$HELPER" 2>&1
)" || external_exit=$?

if [[ ${external_exit:-0} -eq 0 ]]; then
  pass "explicit external endpoint exits 0"
else
  fail "explicit external endpoint should exit 0"
fi

if echo "$external_output" | grep -q "Using explicit OTLP endpoint"; then
  pass "explicit external endpoint reports reuse mode"
else
  fail "explicit external endpoint output missing endpoint note: $external_output"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
