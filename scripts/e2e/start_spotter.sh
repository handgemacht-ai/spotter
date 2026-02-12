#!/usr/bin/env bash
set -euo pipefail

scripts/e2e/prepare_runtime.sh

rm -f path/to/your.db

mix ecto.migrate
mix spotter.e2e.seed
mix phx.server
