#!/usr/bin/env bash
set -euo pipefail

echo "NOTE: scripts/start_spotter_with_dolt.sh is deprecated; use scripts/start_spotter_with_dolt_and_otel.sh" >&2

dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "${dir}/start_spotter_with_dolt_and_otel.sh" "$@"
