#!/usr/bin/env bash
# Require an explicitly configured OTEL endpoint or a healthy shared workspace stack.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Resolve workspace root robustly — walk up from PROJECT_ROOT looking for the
# .runtime/docker/ marker. This works from worktrees (nested under .claude/worktrees/)
# where the naive "../" relative path would land in the wrong directory.
if [[ -n "${WORKSPACE_ROOT_OVERRIDE:-}" ]]; then
  WORKSPACE_ROOT="$WORKSPACE_ROOT_OVERRIDE"
else
  _dir="$PROJECT_ROOT"
  WORKSPACE_ROOT=""
  while [[ "$_dir" != "/" ]]; do
    if [[ -d "$_dir/.runtime/docker" ]]; then
      WORKSPACE_ROOT="$_dir"
      break
    fi
    _dir="$(dirname "$_dir")"
  done
  if [[ -z "$WORKSPACE_ROOT" ]]; then
    echo "[obs] Could not locate workspace root (.runtime/docker/) from ${PROJECT_ROOT}" >&2
    exit 1
  fi
fi
APP_LABEL="${APP_LABEL:-Spotter}"
REPO_OTEL_COMMAND="${REPO_OTEL_COMMAND:-just otel-up}"
OBS_CHECK="${OBS_CHECK_OVERRIDE:-${WORKSPACE_ROOT}/.runtime/docker/obs-dev-check.sh}"
DEFAULT_ENDPOINT="http://localhost:14318"
ALT_DEFAULT_ENDPOINT="http://127.0.0.1:14318"

endpoint="${OTEL_EXPORTER_OTLP_ENDPOINT:-${OBS_OTLP_HTTP_ENDPOINT:-$DEFAULT_ENDPOINT}}"

print_guidance() {
  cat >&2 <<EOF
[obs] Shared OTEL is required before starting ${APP_LABEL}.
[obs] Start it from the workspace root:
[obs]   cd "${WORKSPACE_ROOT}" && just obs-up
[obs] Or start it from this repo:
[obs]   ${REPO_OTEL_COMMAND}
[obs] Alternatively set OTEL_EXPORTER_OTLP_ENDPOINT to an explicit external collector.
EOF
}

case "$endpoint" in
  "$DEFAULT_ENDPOINT"|"$ALT_DEFAULT_ENDPOINT")
    ;;
  *)
    echo "[obs] Using explicit OTLP endpoint: ${endpoint}"
    exit 0
    ;;
esac

if [[ -z "${OBS_CHECK_OVERRIDE:-}" ]]; then
  missing=()
  for tool in docker jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[obs] Missing tools needed to verify the shared OTEL stack: ${missing[*]}" >&2
    print_guidance
    exit 1
  fi
fi

if [[ ! -x "$OBS_CHECK" ]]; then
  echo "[obs] Shared observability check not found at ${OBS_CHECK}" >&2
  print_guidance
  exit 1
fi

check_exit=0
"$OBS_CHECK" --quiet || check_exit=$?

case "$check_exit" in
  0)
    exit 0
    ;;
  1|2)
    print_guidance
    exit 1
    ;;
  *)
    echo "[obs] Shared observability check exited unexpectedly (${check_exit})." >&2
    print_guidance
    exit 1
    ;;
esac
