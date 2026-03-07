#!/usr/bin/env bash
# Integration tests for operational surface migration to transcript_roots
# Tests plugin scripts, docker entrypoint, and e2e scripts
# Run: bash test/scripts/operational_surfaces_test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Run from project root so plugin scripts resolve their lib/ correctly
cd "$PROJECT_ROOT"

PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  SKIP: $1"; }

# Create isolated temp dir for all tests
TEST_TMP="$(mktemp -d)"
cleanup() { rm -rf "$TEST_TMP"; }
trap cleanup EXIT

echo "=== Operational Surface Migration Tests ==="
echo ""

# ============================================================
# Test 1: notify-session.sh forwards transcript_path in payload
# ============================================================
echo "--- Test 1: notify-session.sh forwards transcript_path ---"

NOTIFY_SESSION="$PROJECT_ROOT/spotter-plugin/scripts/notify-session.sh"

if [[ ! -f "$NOTIFY_SESSION" ]]; then
  skip "notify-session.sh not found"
else
  # Create a mock curl that captures the payload
  MOCK_BIN="$TEST_TMP/mock_bin"
  mkdir -p "$MOCK_BIN"

  cat > "$MOCK_BIN/curl" << 'MOCK_CURL'
#!/usr/bin/env bash
echo "$@" >> "${MOCK_CURL_LOG}"
echo -n "200"
exit 0
MOCK_CURL
  chmod +x "$MOCK_BIN/curl"

  export MOCK_CURL_LOG="$TEST_TMP/curl_calls.log"
  export TMUX_PANE="%0"
  export SPOTTER_URL="http://localhost:9999"
  export CLAUDE_ENV_FILE="$TEST_TMP/env_file"
  SAVED_PATH="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  INPUT_JSON='{"session_id":"test-sess-123","cwd":"/workspace","transcript_path":"/home/user/.claude/projects/-workspace/test-sess-123.jsonl"}'

  echo "$INPUT_JSON" | bash "$NOTIFY_SESSION" 2>/dev/null || true

  export PATH="$SAVED_PATH"
  unset TMUX_PANE SPOTTER_URL CLAUDE_ENV_FILE

  if [[ -f "$MOCK_CURL_LOG" ]]; then
    if grep -q "transcript_path" "$MOCK_CURL_LOG"; then
      pass "notify-session.sh includes transcript_path in payload"
    else
      fail "notify-session.sh does NOT include transcript_path in payload"
    fi
  else
    fail "notify-session.sh did not make any HTTP calls"
  fi

  rm -f "$MOCK_CURL_LOG"
fi

# ============================================================
# Test 2: notify-session-end.sh forwards transcript_path
# ============================================================
echo ""
echo "--- Test 2: notify-session-end.sh forwards transcript_path ---"

NOTIFY_END="$PROJECT_ROOT/spotter-plugin/scripts/notify-session-end.sh"

if [[ ! -f "$NOTIFY_END" ]]; then
  skip "notify-session-end.sh not found"
else
  MOCK_BIN="$TEST_TMP/mock_bin2"
  mkdir -p "$MOCK_BIN"

  cat > "$MOCK_BIN/curl" << 'MOCK_CURL'
#!/usr/bin/env bash
echo "$@" >> "${MOCK_CURL_LOG}"
echo -n "200"
exit 0
MOCK_CURL
  chmod +x "$MOCK_BIN/curl"

  MOCK_CURL_LOG="$TEST_TMP/curl_calls_end.log"
  export MOCK_CURL_LOG
  export SPOTTER_URL="http://localhost:9999"
  SAVED_PATH="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  INPUT_JSON='{"session_id":"test-end-456","reason":"user_exit","cwd":"/workspace","transcript_path":"/home/user/.claude/projects/-workspace/test-end-456.jsonl"}'

  echo "$INPUT_JSON" | bash "$NOTIFY_END" 2>/dev/null || true

  export PATH="$SAVED_PATH"
  unset SPOTTER_URL

  if [[ -f "$MOCK_CURL_LOG" ]]; then
    if grep -q "transcript_path" "$MOCK_CURL_LOG"; then
      pass "notify-session-end.sh includes transcript_path in payload"
    else
      fail "notify-session-end.sh does NOT include transcript_path in payload"
    fi
  else
    fail "notify-session-end.sh did not make any HTTP calls"
  fi

  rm -f "$MOCK_CURL_LOG"
fi

# ============================================================
# Test 3: spotter_live_entrypoint.sh creates both root dirs
# ============================================================
echo ""
echo "--- Test 3: entrypoint creates both claude and claude_agents dirs ---"

ENTRYPOINT="$PROJECT_ROOT/scripts/docker/spotter_live_entrypoint.sh"

if [[ ! -f "$ENTRYPOINT" ]]; then
  skip "spotter_live_entrypoint.sh not found"
else
  # Check the script content for both directory creations
  if grep -q '\.claude_agents/projects' "$ENTRYPOINT"; then
    pass "entrypoint references .claude_agents/projects"
  else
    fail "entrypoint does NOT reference .claude_agents/projects (only creates .claude/projects)"
  fi
fi

# ============================================================
# Test 4: prepare_runtime.sh creates both root dirs
# ============================================================
echo ""
echo "--- Test 4: prepare_runtime.sh creates both root dirs ---"

PREPARE_RUNTIME="$PROJECT_ROOT/scripts/e2e/prepare_runtime.sh"

if [[ ! -f "$PREPARE_RUNTIME" ]]; then
  skip "prepare_runtime.sh not found"
else
  if grep -q '\.claude_agents/projects' "$PREPARE_RUNTIME"; then
    pass "prepare_runtime.sh references .claude_agents/projects"
  else
    fail "prepare_runtime.sh does NOT reference .claude_agents/projects (only creates .claude/projects)"
  fi
fi

# ============================================================
# Test 5: snapshot_transcripts.sh supports multiple source roots
# ============================================================
echo ""
echo "--- Test 5: snapshot_transcripts.sh supports multiple source roots ---"

SNAPSHOT="$PROJECT_ROOT/scripts/e2e/snapshot_transcripts.sh"

if [[ ! -f "$SNAPSHOT" ]]; then
  skip "snapshot_transcripts.sh not found"
else
  # The script should accept multiple source roots (either via multiple args,
  # env var, or colon-separated). Check for multi-root support.
  if grep -qE 'SOURCE_ROOTS|for.*root|multiple.*root|IFS.*:' "$SNAPSHOT"; then
    pass "snapshot_transcripts.sh has multi-root support"
  else
    # Also check if it iterates over positional args
    if grep -qE 'shift|"\$@"|"\${@}"' "$SNAPSHOT"; then
      pass "snapshot_transcripts.sh iterates over multiple args"
    else
      fail "snapshot_transcripts.sh only accepts single SOURCE_ROOT (no multi-root support)"
    fi
  fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $SKIP skipped ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
