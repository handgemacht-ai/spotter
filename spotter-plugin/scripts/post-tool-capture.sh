#!/usr/bin/env bash
# Post-tool capture: reads file state after Write/Edit/Bash tools execute,
# compares with pre-tool baseline, and POSTs snapshots to Spotter.
# Fails silently to never block Claude.

set -euo pipefail
trap 'exit 0' ERR

# Source trace context helper (fail silently if unavailable)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
[ -f "${LIB_DIR}/trace_context.sh" ] && . "${LIB_DIR}/trace_context.sh"
[ -f "${LIB_DIR}/hook_timeouts.sh" ] && . "${LIB_DIR}/hook_timeouts.sh"
[ -f "${LIB_DIR}/spotter_url.sh" ] && . "${LIB_DIR}/spotter_url.sh"
[ -f "${LIB_DIR}/hook_http.sh" ] && . "${LIB_DIR}/hook_http.sh"

INPUT="$(cat)"

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
TOOL_USE_ID="$(echo "$INPUT" | jq -r '.tool_use_id // empty')"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
HOOK_EVENT="$(echo "$INPUT" | jq -r '.hook_event_name // empty')"
WORKING_CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"

if [ -z "$TOOL_USE_ID" ] || [ -z "$SESSION_ID" ]; then
  exit 0
fi

resolve_repo_dir() {
  local cwd_input="$WORKING_CWD"
  local project_input="${CLAUDE_PROJECT_DIR:-}"
  local tool_command
  local git_arg

  local try_dir
  for try_dir in "$cwd_input" "$project_input"; do
    if [ -n "$try_dir" ] && git -C "$try_dir" rev-parse --git-dir > /dev/null 2>&1; then
      git -C "$try_dir" rev-parse --show-toplevel 2>/dev/null
      return 0
    fi
  done

  tool_command="$(echo "$INPUT" | jq -r '.tool_input.command // empty')"
  git_arg="$(printf '%s' "$tool_command" | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "-C" && i + 1 <= NF) {
          print $(i + 1)
          exit 0
        }
        if (index($i, "-C") == 1 && length($i) > 2) {
          print substr($i, 3)
          exit 0
        }
      }
    }' )"

  if [ -n "$git_arg" ]; then
    git_arg="${git_arg%\"}"
    git_arg="${git_arg#\"}"
    if [ -n "$git_arg" ] && git -C "$git_arg" rev-parse --git-dir > /dev/null 2>&1; then
      git -C "$git_arg" rev-parse --show-toplevel 2>/dev/null
      return 0
    fi
  fi
}

REPO_DIR="$(resolve_repo_dir || true)"
if [ -z "${REPO_DIR:-}" ]; then
  if git -C "$WORKING_CWD" rev-parse --git-dir > /dev/null 2>&1; then
    REPO_DIR="$WORKING_CWD"
  elif git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --git-dir > /dev/null 2>&1; then
    REPO_DIR="${CLAUDE_PROJECT_DIR:-.}"
  fi
fi

GIT_CMD=(git)
if [ -n "${REPO_DIR:-}" ]; then
  GIT_CMD=(git -C "$REPO_DIR")
fi

# Generate trace context (fail gracefully if unavailable)
TRACEPARENT="$(spotter_generate_traceparent 2>/dev/null || true)"

# Determine Spotter URL
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PORT_FILE="$PLUGIN_DIR/../.port"

if [ -f "$PORT_FILE" ]; then
  PORT="$(cat "$PORT_FILE")"
else
  PORT=1100
fi

SPOTTER_URLS="$(spotter_resolve_urls "${PORT}")"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)"

SNAPSHOT_CONNECT_TIMEOUT="$(resolve_timeout "${SPOTTER_POST_TOOL_CONNECT_TIMEOUT:-}" "${SPOTTER_HOOK_CONNECT_TIMEOUT:-}" "$SPOTTER_DEFAULT_CONNECT_TIMEOUT")"
SNAPSHOT_MAX_TIME="$(resolve_timeout "${SPOTTER_POST_TOOL_MAX_TIME:-}" "${SPOTTER_HOOK_MAX_TIME:-}" "$SPOTTER_DEFAULT_MAX_TIME")"

post_snapshot() {
  local json="$1"

  for BASE_URL in $SPOTTER_URLS; do
    if spotter_post_hook_json \
      "$BASE_URL" \
      "/api/hooks/file-snapshot" \
      "$json" \
      "${HOOK_EVENT:-PostToolUse}" \
      "post-tool-capture.sh" \
      "${TRACEPARENT:-}" \
      "$SNAPSHOT_CONNECT_TIMEOUT" \
      "$SNAPSHOT_MAX_TIME"; then
      return 0
    fi
  done

  return 0
}

get_relative_path() {
  local abs_path="$1"
  local toplevel
  toplevel="$("${GIT_CMD[@]}" rev-parse --show-toplevel 2>/dev/null || echo "")"
  if [ -n "$toplevel" ]; then
    echo "${abs_path#"$toplevel"/}"
  else
    echo "$abs_path"
  fi
}

is_text_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    return 1
  fi
  local mime
  mime="$(file --mime-type -b "$path" 2>/dev/null || echo "unknown")"
  case "$mime" in
    text/*|application/json|application/javascript|application/xml) return 0 ;;
    *) return 1 ;;
  esac
}

is_under_size_limit() {
  local path="$1"
  local size
  size="$(wc -c < "$path" 2>/dev/null || echo 0)"
  [ "$size" -le 1048576 ]
}

read_file_content() {
  local path="$1"
  if [ -f "$path" ] && is_text_file "$path" && is_under_size_limit "$path"; then
    jq -Rs '.' < "$path"
  else
    echo "null"
  fi
}

case "$TOOL_NAME" in
  Write|Edit)
    FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')"
    if [ -z "$FILE_PATH" ]; then
      exit 0
    fi

    TEMP_FILE="/tmp/spotter-before-${TOOL_USE_ID}.json"

    # Read before content from temp file
    CONTENT_BEFORE="null"
    if [ -f "$TEMP_FILE" ]; then
      SKIP="$(jq -r '.skip // empty' < "$TEMP_FILE")"
      if [ "$SKIP" = "true" ]; then
        rm -f "$TEMP_FILE"
        exit 0
      fi
      CONTENT_BEFORE="$(jq '.content' < "$TEMP_FILE")"
      rm -f "$TEMP_FILE"
    fi

    # Read after content
    CONTENT_AFTER="$(read_file_content "$FILE_PATH")"

    # Determine change type
    if [ "$CONTENT_BEFORE" = "null" ] && [ "$CONTENT_AFTER" != "null" ]; then
      CHANGE_TYPE="created"
    elif [ "$CONTENT_AFTER" = "null" ]; then
      CHANGE_TYPE="deleted"
    else
      CHANGE_TYPE="modified"
    fi

    REL_PATH="$(get_relative_path "$FILE_PATH")"

    # Determine source
    if [ "$TOOL_NAME" = "Write" ]; then
      SOURCE="write"
    else
      SOURCE="edit"
    fi

    JSON="$(jq -n \
      --arg session_id "$SESSION_ID" \
      --arg tool_use_id "$TOOL_USE_ID" \
      --arg file_path "$FILE_PATH" \
      --arg relative_path "$REL_PATH" \
      --argjson content_before "$CONTENT_BEFORE" \
      --argjson content_after "$CONTENT_AFTER" \
      --arg change_type "$CHANGE_TYPE" \
      --arg source "$SOURCE" \
      --arg timestamp "$TIMESTAMP" \
      '{session_id: $session_id, tool_use_id: $tool_use_id, file_path: $file_path, relative_path: $relative_path, content_before: $content_before, content_after: $content_after, change_type: $change_type, source: $source, timestamp: $timestamp}'
    )"

    post_snapshot "$JSON"
    ;;

  Bash)
    BASELINE_FILE="/tmp/spotter-git-baseline-${TOOL_USE_ID}.txt"
    HEAD_FILE="/tmp/spotter-git-head-${TOOL_USE_ID}.txt"

    if ! "${GIT_CMD[@]}" rev-parse --git-dir > /dev/null 2>&1; then
      rm -f "$BASELINE_FILE" "$HEAD_FILE"
      exit 0
    fi

    # Capture commit event
    BASE_HEAD=""
    if [ -f "$HEAD_FILE" ]; then
      BASE_HEAD="$(cat "$HEAD_FILE")"
      rm -f "$HEAD_FILE"
    fi

    CURRENT_HEAD="$(git rev-parse HEAD 2>/dev/null || echo "")"

    if [ -n "$BASE_HEAD" ] && [ -n "$CURRENT_HEAD" ] && [ "$BASE_HEAD" != "$CURRENT_HEAD" ]; then
      NEW_HASHES="$("${GIT_CMD[@]}" rev-list --reverse "${BASE_HEAD}..${CURRENT_HEAD}" 2>/dev/null | head -50 || echo "")"
    else
      NEW_HASHES=""
    fi

    if [ -n "$NEW_HASHES" ]; then
      GIT_BRANCH="$("${GIT_CMD[@]}" branch --show-current 2>/dev/null || echo "")"
      COMMIT_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)"

      HASHES_JSON="$(echo "$NEW_HASHES" | jq -R . | jq -s .)"

      COMMIT_JSON="$(jq -n \
        --arg session_id "$SESSION_ID" \
        --arg tool_use_id "$TOOL_USE_ID" \
        --arg git_branch "$GIT_BRANCH" \
        --arg base_head "$BASE_HEAD" \
        --arg head "$CURRENT_HEAD" \
        --argjson new_commit_hashes "$HASHES_JSON" \
        --arg captured_at "$COMMIT_TIMESTAMP" \
        '{session_id: $session_id, tool_use_id: $tool_use_id, git_branch: $git_branch, base_head: $base_head, head: $head, new_commit_hashes: $new_commit_hashes, captured_at: $captured_at}'
      )"

      COMMIT_CONNECT_TIMEOUT="$(resolve_timeout "${SPOTTER_POST_TOOL_CONNECT_TIMEOUT:-}" "${SPOTTER_HOOK_CONNECT_TIMEOUT:-}" "$SPOTTER_DEFAULT_CONNECT_TIMEOUT")"
      COMMIT_MAX_TIME="$(resolve_timeout "${SPOTTER_POST_TOOL_MAX_TIME:-}" "${SPOTTER_HOOK_MAX_TIME:-}" "$SPOTTER_DEFAULT_MAX_TIME")"

      for BASE_URL in $SPOTTER_URLS; do
        if spotter_post_hook_json \
          "$BASE_URL" \
          "/api/hooks/commit-event" \
          "$COMMIT_JSON" \
          "${HOOK_EVENT:-PostToolUse}" \
          "post-tool-capture.sh" \
          "${TRACEPARENT:-}" \
          "$COMMIT_CONNECT_TIMEOUT" \
          "$COMMIT_MAX_TIME"; then
          break
        fi
      done
    fi

    # Capture current state
    CURRENT_FILE="/tmp/spotter-git-current-${TOOL_USE_ID}.txt"
    {
      "${GIT_CMD[@]}" diff --name-only HEAD 2>/dev/null || true
      "${GIT_CMD[@]}" status --porcelain 2>/dev/null | awk '{print $2}' || true
    } | sort -u > "$CURRENT_FILE"

    # Find newly changed files (in current but not in baseline)
    if [ -f "$BASELINE_FILE" ]; then
      CHANGED_FILES="$(comm -13 "$BASELINE_FILE" "$CURRENT_FILE" 2>/dev/null || true)"
    else
      CHANGED_FILES="$(cat "$CURRENT_FILE")"
    fi

    rm -f "$BASELINE_FILE" "$CURRENT_FILE"

    TOPLEVEL="$("${GIT_CMD[@]}" rev-parse --show-toplevel 2>/dev/null || echo ".")"

    echo "$CHANGED_FILES" | while IFS= read -r rel_file; do
      [ -z "$rel_file" ] && continue

      abs_file="${TOPLEVEL}/${rel_file}"

      # Skip binary/large files
      if ! is_text_file "$abs_file" || ! is_under_size_limit "$abs_file"; then
        continue
      fi

      CONTENT_AFTER="$(read_file_content "$abs_file")"

      # Try to get before content from git
      CONTENT_BEFORE="$("${GIT_CMD[@]}" show "HEAD:${rel_file}" 2>/dev/null | jq -Rs '.' || echo "null")"

      if [ "$CONTENT_BEFORE" = "null" ]; then
        CHANGE_TYPE="created"
      elif [ ! -f "$abs_file" ]; then
        CHANGE_TYPE="deleted"
      else
        CHANGE_TYPE="modified"
      fi

      JSON="$(jq -n \
        --arg session_id "$SESSION_ID" \
        --arg tool_use_id "$TOOL_USE_ID" \
        --arg file_path "$abs_file" \
        --arg relative_path "$rel_file" \
        --argjson content_before "$CONTENT_BEFORE" \
        --argjson content_after "$CONTENT_AFTER" \
        --arg change_type "$CHANGE_TYPE" \
        --arg source "bash" \
        --arg timestamp "$TIMESTAMP" \
        '{session_id: $session_id, tool_use_id: $tool_use_id, file_path: $file_path, relative_path: $relative_path, content_before: $content_before, content_after: $content_after, change_type: $change_type, source: $source, timestamp: $timestamp}'
      )"

      post_snapshot "$JSON"
    done
    ;;
esac

exit 0
