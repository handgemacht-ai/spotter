#!/usr/bin/env bash
# Resolves a directory path to its canonical git repo root.
# Git-based strategies from Elixir canonicalize_cwd/1 (path heuristic handled server-side).
#
# Usage: resolve_canonical_dir <path>
# Outputs the canonical repo root, or the original path on failure.

resolve_canonical_dir() {
  local input_path="$1"

  if [ -z "$input_path" ]; then
    return 0
  fi

  # Strategy 1: git rev-parse --path-format=absolute --git-common-dir
  local common_dir
  common_dir="$(git -C "$input_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || true

  if [ -n "$common_dir" ] && [[ "$common_dir" == */.git ]]; then
    echo "${common_dir%/.git}"
    return 0
  fi

  # Strategy 2: git rev-parse --show-toplevel
  local toplevel
  toplevel="$(git -C "$input_path" rev-parse --show-toplevel 2>/dev/null)" || true

  if [ -n "$toplevel" ]; then
    echo "$toplevel"
    return 0
  fi

  # Fallback: return original path
  echo "$input_path"
}
