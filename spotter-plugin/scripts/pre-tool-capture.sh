#!/usr/bin/env bash
# Pre-tool capture: saves file state before Write/Edit/Bash tools execute.
# Reads hook JSON from stdin, saves baseline to /tmp for post-tool comparison.
# Fails silently to never block Claude.

set -euo pipefail
trap 'exit 0' ERR

INPUT="$(cat)"

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
TOOL_USE_ID="$(echo "$INPUT" | jq -r '.tool_use_id // empty')"

if [ -z "$TOOL_USE_ID" ]; then
  exit 0
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

    if git rev-parse --git-dir > /dev/null 2>&1; then
      {
        git diff --name-only HEAD 2>/dev/null || true
        git status --porcelain 2>/dev/null | awk '{print $2}' || true
      } | sort -u > "$BASELINE_FILE"
    else
      touch "$BASELINE_FILE"
    fi
    ;;
esac

exit 0
