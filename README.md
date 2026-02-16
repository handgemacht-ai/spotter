# Spotter

Spotter reviews Claude Code sessions and generated code. It links Claude sessions to Git commits using deterministic hook capture plus asynchronous enrichment so each session can be traced to concrete repository changes. The runtime stack is Phoenix/LiveView for the app, xterm.js for terminal rendering, and tmux-integrated hook scripts for session event capture.

## Showcase quickstart (one command)

Run Spotter + Claude Code + tmux in Docker without cloning this repo.

### Prerequisites

- Docker Desktop or Docker Engine with `docker compose`
- `SPOTTER_ANTHROPIC_API_KEY` exported
- A local git repo to run inside (or pass `--repo`)

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/marot/spotter/refs/heads/main/install/install.sh | bash
```

Ensure `~/.local/bin` is in your `PATH`.

### Run

```bash
export SPOTTER_ANTHROPIC_API_KEY=sk-ant-...
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

### Known limitations

- Commits created outside Claude hooks are not deterministically observed
- Squash merges may require inference and can be low-confidence
- Git-only in V1; no GitHub/GitLab API integration

## Anthropic API key (AI hotspots / waiting summary)

LLM-powered features (hotspot scoring, waiting summary) use the Anthropic API via LangChain.

- **Environment variable**: `SPOTTER_ANTHROPIC_API_KEY`
- **LangChain app config**: `:langchain, :anthropic_key` (wired in `config/runtime.exs`)
- **Resolution order**: app config first, then system env fallback
- **Fail-safe**: when the key is missing or blank, LLM features degrade gracefully (deterministic fallback summaries, scoring skipped) without crashing workers or making outbound API calls

## Claude Agent SDK (Claude Code CLI)

Several features use [claude_agent_sdk](https://hexdocs.pm/claude_agent_sdk) to run Claude-powered agents in-process via the Claude Code CLI:

- **Product spec rolling spec** (epic `spotter-aml`)
- **Commit test extraction** (epic `spotter-z3e`)

### Prerequisites

Install the Claude Code CLI globally:

```bash
npm install -g @anthropic-ai/claude-code
claude --version
```

The SDK authenticates via `SPOTTER_ANTHROPIC_API_KEY` (environment variable) or CLI auth (`claude auth`).

In test mode, the SDK uses a mock server (`ClaudeAgentSDK.Mock`) so the CLI binary is not required for `mix test`.

## Session & Project Distillation

Completed sessions are distilled into structured summaries via Claude Agent SDK tool-loop agents. Both session and project rollup distillers use in-process MCP tools (`record_session_distillation`, `record_project_rollup_distillation`) with validation and normalization.

### Configuration

| Variable | Default | Description |
|---|---|---|
| `SPOTTER_SESSION_DISTILL_MODEL` | `claude-3-5-haiku-latest` | LLM model for session distillation |
| `SPOTTER_DISTILL_TIMEOUT_MS` | `45000` | Session distillation timeout in ms |
| `SPOTTER_SESSION_DISTILL_INPUT_CHAR_BUDGET` | `30000` | Char budget for transcript slice |
| `SPOTTER_PROJECT_ROLLUP_MODEL` | `claude-3-5-haiku-latest` | LLM model for project rollups |
| `SPOTTER_PROJECT_ROLLUP_DISTILL_TIMEOUT_MS` | `45000` | Project rollup distillation timeout in ms |

## MCP Server

The Spotter MCP server is provided by the plugin via `spotter-plugin/.mcp.json`. The server name is `spotter`, so tools are exposed as `mcp__spotter__*`.

The MCP server URL is controlled by the `SPOTTER_URL` environment variable (default `http://127.0.0.1:1100`). The plugin config uses `${SPOTTER_URL:-http://127.0.0.1:1100}/api/mcp`.

`scripts/setup_worktree.sh` sets `SPOTTER_URL` automatically per worktree based on the assigned port and Tailscale IP, so each tmux-launched Claude session connects to the correct Spotter instance.

## Product Specification (Dolt)

Spotter can maintain a rolling, versioned product specification derived from codebase changes. The spec is stored in a Dolt SQL-server (MySQL-compatible with Git-style versioning).

### Setup

Start the Dolt SQL-server:

```bash
docker compose -f docker-compose.dolt.yml up -d
```

The bootstrap SQL (`docker/dolt-init.sql`) creates both `spotter_product` and `spotter_tests` databases. The `scripts/start_spotter.sh` script also ensures both databases exist before starting the app. The schema is created automatically on startup.

If Dolt is unavailable, the app boots normally — product spec features are simply inactive.

### Configuration

| Variable | Default | Description |
|---|---|---|
| `SPOTTER_DOLT_HOST` | `localhost` | Dolt server hostname |
| `SPOTTER_DOLT_PORT` | `13307` | Dolt server port |
| `SPOTTER_DOLT_DATABASE` | `spotter_product` | Dolt database name |
| `SPOTTER_DOLT_USERNAME` | `spotter` | Dolt username |
| `SPOTTER_DOLT_PASSWORD` | `spotter` | Dolt password |

Tests run without Dolt. Integration tests require Dolt: `mix test --include live_dolt`.

## Test Specifications (Dolt)

Spotter extracts structured test specifications from commits using Claude agents, storing them in a Dolt database (`spotter_tests`). The `/specs` page (artifact=tests) provides a read-only view of the versioned test tree.

### How it works

1. When commits are ingested (via hooks or `IngestRecentCommits`), `AnalyzeCommitTests` is enqueued for commits with test file changes.
2. The agent reads each changed test file at the analyzed commit and extracts test metadata (framework, describe path, test name, given/when/then) into Dolt.
3. Each analysis run creates a Dolt commit snapshot. The snapshot hash is stored in `CommitTestRun.dolt_commit_hash`.
4. The `/specs` page uses time-travel queries (`AS OF`) to show the test tree at any commit, and computes semantic diffs between snapshots.

### `/specs` page (merged Product + Tests)

The Specs page (`/specs`) combines product and test specifications into a single commit-centric view. Users switch between artifact types (Product/Tests) and view modes (Diff/Snapshot) without leaving context.

- **Timeline**: project-scoped commit list with both product and test run badges
- **Artifact toggle**: switch between Product and Tests specs for the same commit
- **Diff view**: shows added, changed, and removed specs for a commit
- **Snapshot view**: full tree (domains/features/requirements for product, files/tests for tests) with search and expand/collapse controls

### Configuration

| Variable | Default | Description |
|---|---|---|
| `SPOTTER_TEST_SPEC_DOLT_HOST` | `SPOTTER_DOLT_HOST` | Test spec Dolt hostname |
| `SPOTTER_TEST_SPEC_DOLT_PORT` | `SPOTTER_DOLT_PORT` | Test spec Dolt port |
| `SPOTTER_TEST_SPEC_DOLT_DATABASE` | `spotter_tests` | Test spec Dolt database |
| `SPOTTER_TEST_SPEC_DOLT_USERNAME` | `SPOTTER_DOLT_USERNAME` | Test spec Dolt username |
| `SPOTTER_TEST_SPEC_DOLT_PASSWORD` | `SPOTTER_DOLT_PASSWORD` | Test spec Dolt password |

If Dolt is unavailable, the app boots normally — test spec features show a callout and disable data loading.

The `spotter_tests` database is created automatically at two layers:
1. **Bootstrap SQL** — `docker/dolt-init.sql` (and `install/bundle/dolt/dolt-init.sql`) provisions both databases on first Dolt startup.
2. **Runtime self-heal** — `Schema.ensure_database!/0` creates the database via a direct MyXQL connection before table DDL runs. This handles cases where the bootstrap SQL was not applied (e.g. existing Dolt instance).

### Troubleshooting

If logs show repeated `database not found: spotter_tests` errors:
1. Verify Dolt is reachable: `mysql -h127.0.0.1 -P13307 -uspotter -pspotter -e "SELECT 1"`
2. Check env overrides: `SPOTTER_TEST_SPEC_DOLT_DATABASE` defaults to `spotter_tests`
3. Restart the app — `ensure_database!/0` will auto-create the missing database

If logs show tzdata permission errors like:
`could not write to file "/app/_build/dev/lib/tzdata/priv/latest_remote_poll.txt": permission denied`
1. Restart Spotter after pulling the latest installer bundle/config (defaults to writable `/tmp/tzdata`)
2. Optionally set a custom path: `SPOTTER_TZDATA_DIR=/path/you/control`
3. If you don’t run tracing collectors, you can ignore this OTEL export warning and keep tracing disabled in local troubleshooting mode

### Rollout checklist

1. Start Dolt: `docker compose -f docker-compose.dolt.yml up -d`
2. Boot or restart the app (schema is created automatically on startup)
3. Verify hook enqueue: trigger a commit with test changes and check that `AnalyzeCommitTests` jobs appear
4. Verify `/specs?artifact=tests` timeline shows commits with test-run badges
5. Verify no-change commits show "ok (no changes)" badge (no Dolt snapshot created)

## Local E2E (Docker + Playwright + Live Claude)

Spotter includes a local-only E2E harness that runs:

- Spotter app in Docker (`tmux` + `claude` available in container)
- Playwright smoke tests with full-page visual snapshots (`maxDiffPixelRatio: 0.001`)

### Prerequisites

- Docker + Docker Compose
- `SPOTTER_ANTHROPIC_API_KEY` exported in your shell (the app will fail to start in dev/prod without it)

### Refresh transcript fixtures from host Claude sessions

Fixture snapshot source is restricted to:

- `~/.claude/projects/-home-*-projects-spotter`
- `~/.claude/projects/-home-*-projects-spotter-worktrees*`

Run:

```bash
scripts/e2e/snapshot_transcripts.sh
scripts/e2e/scan_fixtures_secrets.sh
```

The snapshot script selects longer sessions (line-count based), forces subagent coverage when available, sanitizes data, and writes metadata to `test/fixtures/transcripts/README.md`.

### Run E2E suite

```bash
SPOTTER_ANTHROPIC_API_KEY=... scripts/e2e/run.sh
```

Default host port is `1101`. If it is already in use, override it:

```bash
SPOTTER_E2E_HOST_PORT=1102 SPOTTER_ANTHROPIC_API_KEY=... scripts/e2e/run.sh
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
| Oban jobs | Manual spans in job `perform/1` functions | `spotter.enrich_commits.perform`, `spotter.ingest_recent_commits.perform`, `spotter.sync_transcripts.perform`, `spotter.product_spec.update_rolling_spec.perform` |
| LiveView | Telemetry handler for mount/handle_params/handle_event | `spotter.liveview.*` |
| TerminalChannel | Span events for join/input/resize/stream lifecycle | `spotter.channel.*` |

### Trace context propagation

Hook controllers propagate trace context into Oban jobs via `OtelTraceHelpers.maybe_add_trace_context/1`, which adds `otel_trace_id` and `otel_traceparent` to job args. Jobs read these and set them as span attributes (`spotter.parent_trace_id`, `spotter.parent_traceparent`), enabling cross-process trace correlation.

Hook responses expose the `x-spotter-trace-id` header. Use this ID to query related spans in Jaeger, including downstream job spans from the same request.

The `ObanTelemetry` handler extracts trace context from job args and includes `traceparent`/`trace_id` in FlowHub events, enabling the `/flows` view to display trace linkage between hooks and jobs.

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
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
mix phx.server
```

3. Inspect traces:

- JSON trace file: `tail -f tmp/otel/spotter-traces.json`
- Jaeger UI: `http://localhost:16686`

Query Jaeger programmatically:

```bash
# List available services
curl http://localhost:16686/api/services

# Recent traces for the Spotter service
curl "http://localhost:16686/api/traces?service=spotter&limit=20"

# Lookup a specific trace by ID (from x-spotter-trace-id response header)
curl "http://localhost:16686/api/traces?traceID=<trace_id>&limit=50"
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
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
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
| Hotspot/test/spec agent crash `FunctionClauseError` on `{:transport_stderr, _}` | Upstream SDK missing stderr handler | Using vendored SDK at `vendor/claude_agent_sdk` with fix. Remove when upstream `claude_agent_sdk` >= 0.15 includes the fix |

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
