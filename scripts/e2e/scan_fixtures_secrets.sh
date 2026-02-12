#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

TARGET_PATH="${1:-${REPO_ROOT}/test/fixtures/transcripts}"
CONFIG_PATH="${2:-${REPO_ROOT}/.gitleaks.toml}"

if [[ ! -d "${TARGET_PATH}" ]]; then
  echo "target fixture directory not found: ${TARGET_PATH}" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "gitleaks config not found: ${CONFIG_PATH}" >&2
  exit 1
fi

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks dir "${TARGET_PATH}" \
    --redact \
    --config "${CONFIG_PATH}" \
    --exit-code 1
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "neither gitleaks nor docker is available; cannot run secrets scan" >&2
  exit 1
fi

if [[ "${TARGET_PATH}" != "${REPO_ROOT}"/* ]]; then
  echo "target path must be inside repository when using docker fallback: ${TARGET_PATH}" >&2
  exit 1
fi

docker run --rm \
  -v "${REPO_ROOT}:/repo" \
  zricethezav/gitleaks:latest \
  dir "/repo/${TARGET_PATH#${REPO_ROOT}/}" \
  --redact \
  --config "/repo/${CONFIG_PATH#${REPO_ROOT}/}" \
  --exit-code 1
