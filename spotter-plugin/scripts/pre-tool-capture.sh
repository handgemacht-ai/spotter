#!/usr/bin/env bash
# Pre-tool capture: saves file state before Write/Edit/Bash tools execute.
# Reads hook JSON from stdin, saves baseline to /tmp for post-tool comparison.
# Fails silently to never block Claude.

set -euo pipefail
trap 'exit 0' ERR

INPUT="$(cat)"

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
TOOL_USE_ID="$(echo "$INPUT" | jq -r '.tool_use_id // empty')"
WORKING_CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"

if [ -z "$TOOL_USE_ID" ]; then
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
GIT_CMD=(git)
if [ -n "${REPO_DIR:-}" ]; then
  GIT_CMD=(git -C "$REPO_DIR")
elif git -C "$WORKING_CWD" rev-parse --git-dir > /dev/null 2>&1; then
  REPO_DIR="$WORKING_CWD"
  GIT_CMD=(git -C "$REPO_DIR")
elif git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --git-dir > /dev/null 2>&1; then
  REPO_DIR="${CLAUDE_PROJECT_DIR:-.}"
  GIT_CMD=(git -C "$REPO_DIR")
else
  GIT_CMD=(git)
fi

case "$TOOL_NAME" in
  Write|Edit)
    FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')"
    if [ -z "$FILE_PATH" ]; then
      exit 0
    fi

    TEMP_FILE="/tmp/spotter-before-${TOOL_USE_ID}.json"

    if [ -f "$FILE_PATH" ]; then
      # Check: skip binary files
      MIME="$(file --mime-type -b "$FILE_PATH" 2>/dev/null || echo "unknown")"
      case "$MIME" in
        text/*|application/json|application/javascript|application/xml)
          # Skip files > 1MB
          FILE_SIZE="$(wc -c < "$FILE_PATH" 2>/dev/null || echo 0)"
          if [ "$FILE_SIZE" -gt 1048576 ]; then
            echo '{"content":null}' > "$TEMP_FILE"
          else
            jq -Rs '{content: .}' < "$FILE_PATH" > "$TEMP_FILE"
          fi
          ;;
        *)
          echo '{"content":null,"skip":true}' > "$TEMP_FILE"
          ;;
      esac
    else
      echo '{"content":null}' > "$TEMP_FILE"
    fi
    ;;

  Bash)
    BASELINE_FILE="/tmp/spotter-git-baseline-${TOOL_USE_ID}.txt"
    HEAD_FILE="/tmp/spotter-git-head-${TOOL_USE_ID}.txt"

    if "${GIT_CMD[@]}" rev-parse --git-dir > /dev/null 2>&1; then
      {
        "${GIT_CMD[@]}" diff --name-only HEAD 2>/dev/null || true
        "${GIT_CMD[@]}" status --porcelain 2>/dev/null | awk '{print $2}' || true
      } | sort -u > "$BASELINE_FILE"
      "${GIT_CMD[@]}" rev-parse HEAD 2>/dev/null > "$HEAD_FILE" || echo "" > "$HEAD_FILE"
    else
      touch "$BASELINE_FILE"
      echo "" > "$HEAD_FILE"
    fi
    ;;
esac

exit 0
