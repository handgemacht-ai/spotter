#!/usr/bin/env bash
# Tests for scripts/runtime/ensure-dev-setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$PROJECT_ROOT/scripts/runtime/ensure-dev-setup.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TEMP_ROOT="$(mktemp -d)"
TEMP_BIN="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT" "$TEMP_BIN"' EXIT

cat >"$TEMP_BIN/mix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'mix %s\n' "$*" >>"$TEST_LOG"
if [[ "${1:-}" == "deps.get" ]]; then
  mkdir -p "$PWD/deps"
fi
EOF

cat >"$TEMP_BIN/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'npm %s\n' "$*" >>"$TEST_LOG"
mkdir -p "$PWD/node_modules"
EOF

chmod +x "$TEMP_BIN/mix" "$TEMP_BIN/npm"

run_setup() {
  local log_file="$1"
  TEST_LOG="$log_file" \
    PATH="$TEMP_BIN:/usr/bin:/bin" \
    PROJECT_ROOT_OVERRIDE="$TEMP_ROOT" \
    "$SETUP_SCRIPT"
}

echo "=== ensure-dev-setup.sh tests ==="

echo ""
echo "--- Existence and permissions ---"

if [[ -f "$SETUP_SCRIPT" ]]; then
  pass "ensure-dev-setup.sh exists"
else
  fail "ensure-dev-setup.sh does not exist at scripts/runtime/ensure-dev-setup.sh"
fi

if [[ -x "$SETUP_SCRIPT" ]]; then
  pass "ensure-dev-setup.sh is executable"
else
  fail "ensure-dev-setup.sh is not executable"
fi

mkdir -p "$TEMP_ROOT/assets"
printf '{}' >"$TEMP_ROOT/assets/package.json"
printf '{}' >"$TEMP_ROOT/assets/package-lock.json"

echo ""
echo "--- Missing setup is bootstrapped ---"

bootstrap_log="$TEMP_ROOT/bootstrap.log"
run_setup "$bootstrap_log" >/dev/null 2>&1

if [[ -d "$TEMP_ROOT/deps" ]]; then
  pass "mix deps.get bootstraps deps/"
else
  fail "deps/ was not created"
fi

if [[ -d "$TEMP_ROOT/assets/node_modules" ]]; then
  pass "npm bootstraps assets/node_modules/"
else
  fail "assets/node_modules/ was not created"
fi

if grep -q '^mix deps.get$' "$bootstrap_log" && grep -q '^npm ci$' "$bootstrap_log"; then
  pass "missing setup runs mix deps.get and npm ci"
else
  fail "bootstrap commands were not invoked as expected: $(cat "$bootstrap_log")"
fi

echo ""
echo "--- Existing setup is left alone ---"

existing_log="$TEMP_ROOT/existing.log"
run_setup "$existing_log" >/dev/null 2>&1

if [[ ! -s "$existing_log" ]]; then
  pass "existing setup does not rerun installers"
else
  fail "installers reran even though setup already existed: $(cat "$existing_log")"
fi

echo ""
echo "--- npm install fallback works without lockfile ---"

rm -rf "$TEMP_ROOT/assets/node_modules"
rm -f "$TEMP_ROOT/assets/package-lock.json"

fallback_log="$TEMP_ROOT/fallback.log"
run_setup "$fallback_log" >/dev/null 2>&1

if grep -q '^npm install$' "$fallback_log"; then
  pass "missing lockfile falls back to npm install"
else
  fail "npm install fallback did not run: $(cat "$fallback_log")"
fi

echo ""
echo "--- Asset watchers can be disabled ---"

rm -rf "$TEMP_ROOT/assets/node_modules"

disabled_log="$TEMP_ROOT/disabled.log"
TEST_LOG="$disabled_log" \
  PATH="$TEMP_BIN:/usr/bin:/bin" \
  PROJECT_ROOT_OVERRIDE="$TEMP_ROOT" \
  SPOTTER_DISABLE_ASSET_WATCH=1 \
  "$SETUP_SCRIPT" >/dev/null 2>&1

if [[ ! -s "$disabled_log" ]]; then
  pass "asset watcher disable skips npm bootstrap"
else
  fail "npm bootstrap ran even though asset watch was disabled: $(cat "$disabled_log")"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
