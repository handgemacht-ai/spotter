# Spotter

Spotter reviews Claude Code sessions and generated code. It links Claude sessions to Git commits using deterministic hook capture plus asynchronous enrichment so each session can be traced to concrete repository changes. The runtime stack is Phoenix/LiveView for the app, xterm.js for terminal rendering, and tmux-integrated hook scripts for session event capture.

## Navigation

| Route | Page | Purpose |
|-------|------|---------|
| `/` | Dashboard | Ongoing sessions across all projects |
| `/sessions` | Sessions | Project-filtered session browsing with import, hide/unhide, and pagination |
| `/sessions/:id` | Session detail | Transcript review for a single session |
| `/reviews` | Reviews | Open review annotations |
| `/retros` | Retros | Session retrospectives |
| `/history` | History | Commit history and detail views |
| `/file-metrics` | File metrics | Heatmap and co-change analysis |
| `/telemetry/commands` | Telemetry | Shell command telemetry |

The sidebar highlights the active page. The Sessions link covers both `/sessions` and `/sessions/:id`.

## Local Development Runtime

**Scope:** local-dev only. No installer or production deployment support in this contract.

### Required Tools

| Tool | Purpose |
|------|---------|
| [just](https://github.com/casey/just) | Command runner (delegates to `scripts/runtime/`) |
| [overmind](https://github.com/DarthSim/overmind) | Process manager (reads `Procfile`) |
| [docker](https://docs.docker.com/get-docker/) | Runs Dolt SQL-server container |

All three must be on `$PATH`. If any are missing, `just up` exits non-zero with a single error listing all missing tools.

### Environment Variables

None required. All variables have sensible defaults:

| Variable | Default | Notes |
|----------|---------|-------|
| `SPOTTER_DOLT_HOST` | `127.0.0.1` | Dolt server host |
| `SPOTTER_DOLT_HOST_PORT` | `13307` | Dolt host-mapped port |
| `SPOTTER_DOLT_DATABASE` | `spotter_product` | Main Dolt database |
| `SPOTTER_DOLT_USERNAME` | `spotter` | Dolt credentials |
| `SPOTTER_DOLT_PASSWORD` | `spotter` | Dolt credentials |

### Commands

```
just up        # Start all services (Dolt + Phoenix)
just down      # Stop all services
just status    # Show service health
just logs      # Tail service logs
just reset     # Stop, wipe state, restart clean
```

### Startup Sequence (`just up`)

1. Check prerequisites (`just`, `overmind`, `docker`) — batch all missing into one error
2. Start Dolt container via Docker Compose
3. Readiness check: ping Dolt with 30-second timeout
4. Start Phoenix via overmind (reads `Procfile`)

### Service Ports

| Service | Port | Binding |
|---------|------|---------|
| Phoenix | `1100` base | `0.0.0.0` (deterministic per-worktree via `.worktree-ports.json`) |
| Dolt | `13307` base | `0.0.0.0` (deterministic per-worktree Docker host mapping) |

### OpenTelemetry (always on)

`just up` ensures the OTEL stack is available before starting Phoenix. Manual controls:

```
just otel-up
just otel-down
just otel-restart
just otel-status
```

| Service | Port | Binding |
|---------|------|---------|
| OTEL Collector (gRPC) | `14317` | `127.0.0.1` |
| OTEL Collector (HTTP) | `14318` | `127.0.0.1` |
| OTEL Collector health | `14333` | `127.0.0.1` |
| OTEL Collector metrics | `14389` | `127.0.0.1` |
| Jaeger UI | `14686` | `127.0.0.1` |
| Prometheus UI | `14090` | `127.0.0.1` |

### CLI UX Contract

- Service state indicators: `●` running, `✕` stopped, `!` error
- ANSI colors only when stdout is a TTY
- Justfile recipes delegate to `scripts/runtime/` for testability

### Out of Scope

- Installer / bundle path (no `curl | bash` setup)
- Production deployment
- Remote/cloud runtime

### Transcript Roots

Spotter discovers transcripts from multiple root directories configured via `transcript_roots`. This replaces the former single-path `transcripts_dir` setting.

**Precedence:** DB setting → TOML (`priv/spotter.toml`) → defaults.

| Source | Format | Example |
|--------|--------|---------|
| DB setting (key: `transcript_roots`) | JSON array string | `["~/.claude/projects", "/custom/path"]` |
| TOML (`priv/spotter.toml`) | TOML array | `transcript_roots = ["~/.claude/projects"]` |
| Default | — | `~/.claude/projects`, `~/.claude_agents/projects` |

Paths are normalized: `~` is expanded, relative paths are made absolute, duplicates are removed. Discovery and import scan all configured roots and deduplicate by session ID, preferring the first root in configuration order.

For live container mode, set `SPOTTER_LIVE_TRANSCRIPT_ROOTS` (colon-separated paths) before running `mix spotter.live.configure`. When unset, both default roots are written.

The Docker entrypoint and e2e runtime scripts create both default root directories automatically. Plugin session notifiers (`notify-session.sh`, `notify-session-end.sh`) forward `transcript_path` from hook payloads when present, enabling path-based transcript resolution.

## Showcase quickstart (one command)

Run Spotter + Claude Code + tmux in Docker without cloning this repo.

### Prerequisites

- Docker Desktop or Docker Engine with `docker compose`
- A local git repo to run inside (or pass `--repo`)

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/marot/spotter/refs/heads/main/install/install.sh | bash
```

Ensure `~/.local/bin` is in your `PATH`.

### Run

```bash
cd /path/to/target-repo
spotter
```

This starts the full stack and opens `http://localhost:1100` in your browser by default.
You can override the binding with environment variables or flags:

```bash
spotter --port 1200 --host 127.0.0.1
SPOTTER_HOST=100.64.0.1 SPOTTER_PORT=1200 spotter
```

`SPOTTER_HOST` defaults to `127.0.0.1` and is used for container port binding and the URL Spotter prints.

### Attach to Claude

```bash
spotter attach
```

This connects to the running tmux session where Claude Code is active.

### Stop

```bash
spotter down
```

### Ports

Only `:1100` (Spotter UI) is exposed by default. For debug access:

```bash
spotter up --debug-ports
```

This additionally exposes:
- Jaeger UI: `:16686`
- OTLP HTTP: `:4318`
- Dolt: `:13307`

### Frontend assets in Docker

Docker images prebuild frontend assets (`priv/static/assets/app.js`) during `docker build`. If the file is missing or empty at container startup (e.g. due to a volume mount or manual deletion), the entrypoint performs a one-time rebuild before starting the server. If the rebuild fails, the container exits with a clear error instead of booting with a broken UI.

### Security note

The launcher mounts your target repo (read-write) and `~/.claude` (read-write) into containers so Claude can edit code and write transcripts. The first run prompts for consent. To revoke consent, delete `~/.local/share/spotter/consent-v1`.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `spotter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:spotter, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/spotter>.

## Session-to-Commit Linking

Spotter associates Claude Code sessions with Git commits via a two-phase approach:

### Deterministic capture (hook path)

Claude Code hooks emit a minimal payload after each Bash tool use that creates commits. The `post-tool-capture.sh` script:

1. Compares `HEAD` before and after the tool execution
2. Computes `git rev-list` for new commit hashes (capped at 50)
3. POSTs `session_id`, `base_head`, `head`, and `new_commit_hashes` to `/api/hooks/commit-event`

These commits are stored as **observed_in_session** links with `confidence: 1.0`.

### Async enrichment and inference

An Oban worker enriches commit metadata (parents, author, changed files, patch-id) and computes inferred links:

| Link type | Confidence | Criteria |
|---|---|---|
| `observed_in_session` | 1.00 | Commit hash captured by hook |
| `descendant_of_observed` | 0.90 | Parent is an observed commit |
| `patch_match` | 0.85 | Stable patch-id matches an observed commit |
| `file_overlap` | 0.60 | Jaccard overlap >= 0.70, time delta <= 360 min |

Only links with `confidence >= 0.60` are persisted.

### Hook performance contract

- Target: **p95 <= 75ms** for hook script execution
- Hard budget: **<= 200ms** total script time
- cURL timeouts: `--connect-timeout 0.1`, `--max-time 0.3`
- No `git show` or `git patch-id` in hook scripts (deferred to backend)
- Silent-fail semantics: hooks never block Claude

### Stop vs SessionEnd hooks

- `Stop` is not authoritative for session completion. It is used for per-response lifecycle behavior (for example waiting-overlay cleanup) and may not fire if a response is interrupted.
- `SessionEnd` is the authoritative end-of-session trigger. Spotter runs `notify-session-end.sh` and `raw-event-forward.sh` on this event.
- Backend finalization on SessionEnd stops any active tail worker, runs per-session transcript sync, marks `session_ended_at`, and enqueues follow-up ingest jobs when project context exists.
- Manual transcript import remains available for backfill/historical recovery, but normal session completion should not require manual import.

### Known limitations

- Commits created outside Claude hooks are not deterministically observed
- Squash merges may require inference and can be low-confidence
- Git-only in V1; no GitHub/GitLab API integration

## MCP Server

The Spotter MCP server is provided by the plugin via `spotter-plugin/.mcp.json`. The server name is `spotter`, so tools are exposed as `mcp__spotter__*`.

The MCP server URL is controlled by the `SPOTTER_URL` environment variable (default `http://127.0.0.1:1100`). The plugin config uses `${SPOTTER_URL:-http://127.0.0.1:1100}/api/mcp`.

Worktree hooks generate `.worktree.env`, `config/dev.local.exs`, `.port`, and `.mcp.json` from `.worktree-ports.json`, so each worktree gets deterministic ports and a matching `SPOTTER_URL` target.

### Troubleshooting

If logs show tzdata permission errors like:
`could not write to file "/app/_build/dev/lib/tzdata/priv/latest_remote_poll.txt": permission denied`
1. Restart Spotter after pulling the latest installer bundle/config (defaults to writable `/tmp/tzdata`)
2. Optionally set a custom path: `SPOTTER_TZDATA_DIR=/path/you/control`
3. If you don’t run tracing collectors, you can ignore this OTEL export warning and keep tracing disabled in local troubleshooting mode

## Local E2E (Docker + Playwright + Live Claude)

Spotter includes a local-only E2E harness that runs:

- Spotter app in Docker (`tmux` + `claude` available in container)
- Playwright smoke tests with full-page visual snapshots (`maxDiffPixelRatio: 0.001`)

### Prerequisites

- Docker + Docker Compose

### Refresh transcript fixtures from host Claude sessions

Fixture snapshot source is restricted to spotter project directories matching:

- `-home-*-projects-spotter`
- `-home-*-projects-spotter-worktrees*`

The script scans multiple roots by default (`~/.claude/projects` and `~/.claude_agents/projects`). Override with `SNAPSHOT_TRANSCRIPT_ROOTS` (colon-separated) or a single positional argument:

```bash
scripts/e2e/snapshot_transcripts.sh                          # both default roots
SNAPSHOT_TRANSCRIPT_ROOTS=/custom/root scripts/e2e/snapshot_transcripts.sh  # custom root
scripts/e2e/scan_fixtures_secrets.sh                         # verify no secrets leaked
```

The snapshot script selects longer sessions (line-count based), forces subagent coverage when available, sanitizes data, and writes metadata to `test/fixtures/transcripts/README.md`.

### Run E2E suite

```bash
scripts/e2e/run.sh
```

Default host port is `1101`. If it is already in use, override it:

```bash
SPOTTER_E2E_HOST_PORT=1102 scripts/e2e/run.sh
```

This command:

1. builds app + runner containers
2. seeds fixture transcripts into container `~/.claude/projects`
3. runs Playwright smoke tests
4. always tears down the compose stack

### Artifacts and visual policy

- Playwright artifacts: `e2e/test-results/` and `e2e/playwright-report/`
- Snapshot assertions use full-page captures with tolerance `0.001`
- If recurring flakiness appears, report artifacts first. Do not switch to component snapshots without an explicit user decision.

## Observability

Spotter supports three observability flows controlled by environment variables in `scripts/start_spotter.sh`.

### Shared contract collector (default)

When the shared dev observability stack is already running (detected by the `dev.observability.contract=v1` Docker label):

```bash
scripts/start_spotter.sh
# → Detects shared collector, skips local OTEL stack, exports to http://localhost:14318
```

### Local fallback

When no shared stack is running and you want local observability:

```bash
export SPOTTER_OTEL_LOCAL_FALLBACK=1
scripts/start_spotter.sh
# → Starts local collector + Jaeger from docker-compose.otel.yml
```

### External endpoint override

For custom or remote collectors:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=https://my-collector.example.com:4318
scripts/start_spotter.sh
# → Uses explicit endpoint, no local stack started
```

### Observability environment variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `OBS_ENABLED` | Enable contract-aware startup | `true` |
| `SPOTTER_OTEL_LOCAL_FALLBACK` | Allow local stack when no contract collector | unset (disabled) |
| `SPOTTER_OTEL_ENABLED` | Elixir SDK instrumentation toggle | `true` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint URL | `http://localhost:14318` |
| `OTEL_RESOURCE_ATTRIBUTES` | Resource attributes (comma-separated key=value) | auto-filled with project/worktree defaults |

> OTEL traces contain technical identifiers only (span names, durations, service metadata). Resource attributes are project and worktree names — no personally identifiable information (PII) is collected or exported.

## OpenTelemetry Tracing

Spotter includes end-to-end OpenTelemetry instrumentation across the full request path:

```
Plugin hooks → traceparent header → Phoenix controllers → Ash actions → LiveView → TerminalChannel
```

### Architecture

| Layer | Instrumentation | Span/Event names |
|---|---|---|
| Plugin hooks | W3C `traceparent` header generation | (client-side, no spans) |
| Phoenix controllers | `with_span` macro in hook controllers | `spotter.hook.*` |
| Ash Framework | `opentelemetry_ash` tracer (action, custom, flow) | `ash.*` |
| Oban jobs | Manual spans in job `perform/1` functions | `spotter.enrich_commits.perform`, `spotter.ingest_recent_commits.perform`, `spotter.sync_transcripts.perform` |
| LiveView | Telemetry handler for mount/handle_params/handle_event | `spotter.liveview.*` |
| TerminalChannel | Span events for join/input/resize/stream lifecycle | `spotter.channel.*` |

### Trace context propagation

Hook controllers propagate trace context into Oban jobs via `OtelTraceHelpers.maybe_add_trace_context/1`, which adds `otel_trace_id` and `otel_traceparent` to job args. Jobs read these and set them as span attributes (`spotter.parent_trace_id`, `spotter.parent_traceparent`), enabling cross-process trace correlation.

Hook responses expose the `x-spotter-trace-id` header. Use this ID to query related spans in Jaeger, including downstream job spans from the same request.

### Local mode (default OTLP collector)

By default in dev, Spotter exports traces via OTLP.
Start the local collector stack for machine-readable traces and Jaeger UI:

1. Start collector + Jaeger:

```bash
scripts/otel/start.sh
```

2. Point Spotter to OTLP:

```bash
export OTEL_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318
mix phx.server
```

3. Inspect traces:

- JSON trace file: `tail -f tmp/otel/spotter-traces.json`
- Jaeger UI: `http://localhost:14686`

Query Jaeger programmatically:

```bash
# List available services
curl http://localhost:14686/api/services

# Recent traces for the Spotter service
curl "http://localhost:14686/api/traces?service=spotter&limit=20"

# Lookup a specific trace by ID (from x-spotter-trace-id response header)
curl "http://localhost:14686/api/traces?traceID=<trace_id>&limit=50"
```

4. Stop the stack when done:

```bash
scripts/otel/stop.sh
```

### Disabling tracing

Set the environment variable before starting the server:

```bash
SPOTTER_OTEL_ENABLED=false mix phx.server
```

In test environment, the exporter is set to `:none` by default so no span output is produced.

### Production (OTLP exporter)

Set these environment variables to send spans to an OTLP-compatible collector:

```bash
export OTEL_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318
```

### Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| No traces in collector/Jaeger | Collector not running or tracing disabled | Run `scripts/otel/start.sh`; verify `SPOTTER_OTEL_ENABLED` is not `false` |
| Startup error `Transforming configuration value failed ... OTEL_TRACES_EXPORTER ... stdout` | Unsupported exporter value for this OTEL version | Unset `OTEL_TRACES_EXPORTER` or set it to `otlp`/`none`; use `OTEL_EXPORTER=otlp` for Spotter |
| Missing `x-spotter-trace-id` response header | No active span context | Verify plugin sends `traceparent` header |
| Malformed `traceparent` from plugin | `openssl` unavailable in hook environment | Install openssl or check `/proc/sys/kernel/random/uuid` |
| Exporter connection errors | OTLP endpoint unreachable | Verify `OTEL_EXPORTER_OTLP_ENDPOINT` is correct |
| Duplicate telemetry handlers after code reload | Handler re-attachment | `LiveviewOtel.setup/0` detaches before re-attaching |
| Ash action spans missing | Tracer not configured | Verify `config :ash, tracer: [OpentelemetryAsh]` in config |

## `.spotterignore` (co-change filtering)

Co-change computation reads all file paths from `git log --name-only`. To exclude generated or operational files (e.g. issue trackers stored in-tree), create a `.spotterignore` file in the repo root with gitignore-style patterns:

```
.beads/
tmp/
*.jsonl
```

When this file is present, co-change groups will not include matching paths. Matching is delegated to `git check-ignore` so all gitignore syntax (globs, directory rules, comments, negation) is supported.

If the file is missing or empty, all paths are included (existing behavior).

Note: `.spotterignore` currently applies only to co-change analysis. Heatmap computation is not affected.

## Landing page (Astro + GitHub Pages)

### Local development

```bash
cd site
npm ci
npm run dev
```

### Production build check

```bash
cd site
npm ci
npm run build
```

### Refresh landing screenshots (crop + optimize + WebP)

```bash
cd site
npm ci
npm run screenshots:process
```

### Enable deployment in GitHub

- Go to `Settings -> Pages` in `github.com/marot/spotter`
- Under **Build and deployment**, set **Source** to `GitHub Actions`
- Pushes to `master` or `main` trigger `.github/workflows/deploy-pages.yml` when `site/**` or workflow files change

### Verification checklist

- Workflow run name is `Deploy Astro site to Pages`.
- Build job completes `npm ci` and `npm run build` in `site/`.
- Deploy job publishes `site/dist` to `github-pages` environment.
- Published URL remains `https://marot.github.io/spotter/`.

### Notes

- Astro `base` is `/spotter` for project pages path handling.
- The workflow deploys only when files under `site/**` or the workflow file change.
