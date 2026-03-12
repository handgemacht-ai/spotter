#!/usr/bin/env bash
# Check that all required tools are on $PATH.
# Exits 0 when all present; non-zero with actionable guidance otherwise.
set -euo pipefail

# Disable ANSI colors when stdout is not a TTY
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  NC=''
fi

REQUIRED_TOOLS=(just overmind docker jq mix mysql node npm)

INSTALL_HINTS=(
  "Install just: https://github.com/casey/just#installation"
  "Install overmind: https://github.com/DarthSim/overmind#installation"
  "Install docker: https://docs.docker.com/get-docker/"
  "Install jq: https://jqlang.org/download/"
  "Install Elixir (provides mix): https://elixir-lang.org/install.html"
  "Install a MySQL-compatible client (e.g. brew install mysql-client or apt install default-mysql-client)"
  "Install Node.js: https://nodejs.org/en/download"
  "Install npm via Node.js: https://nodejs.org/en/download"
)

missing=()

for i in "${!REQUIRED_TOOLS[@]}"; do
  tool="${REQUIRED_TOOLS[$i]}"
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing+=("$tool")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  printf "${RED}Missing required tools:${NC}\n" >&2
  for i in "${!REQUIRED_TOOLS[@]}"; do
    tool="${REQUIRED_TOOLS[$i]}"
    for m in "${missing[@]}"; do
      if [[ "$m" == "$tool" ]]; then
        printf "  ✕ %s — %s\n" "$tool" "${INSTALL_HINTS[$i]}" >&2
      fi
    done
  done
  exit 1
fi

printf "${GREEN}All prerequisites met.${NC}\n"
exit 0
