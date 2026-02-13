# Spotter

Spotter reviews Claude Code sessions and generated code. It links Claude sessions to Git commits using deterministic hook capture plus asynchronous enrichment so each session can be traced to concrete repository changes. The runtime stack is Phoenix/LiveView for the app, xterm.js for terminal rendering, and tmux-integrated hook scripts for session event capture.

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

- **Environment variable**: `ANTHROPIC_API_KEY`
- **LangChain app config**: `:langchain, :anthropic_key` (wired in `config/runtime.exs`)
- **Resolution order**: app config first, then system env fallback
- **Fail-safe**: when the key is missing or blank, LLM features degrade gracefully (deterministic fallback summaries, scoring skipped) without crashing workers or making outbound API calls

## Local E2E (Docker + Playwright + Live Claude)

Spotter includes a local-only E2E harness that runs:

- Spotter app in Docker (`tmux` + `claude` available in container)
- Playwright smoke tests with full-page visual snapshots (`maxDiffPixelRatio: 0.001`)

### Prerequisites

- Docker + Docker Compose
- `ANTHROPIC_API_KEY` exported in your shell (the app will fail to start in dev/prod without it)

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
ANTHROPIC_API_KEY=... scripts/e2e/run.sh
```

Default host port is `1101`. If it is already in use, override it:

```bash
SPOTTER_E2E_HOST_PORT=1102 ANTHROPIC_API_KEY=... scripts/e2e/run.sh
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
| Oban jobs | Manual spans in `EnrichCommits.perform/1` | `spotter.enrich_commits.perform` |
| LiveView | Telemetry handler for mount/handle_params/handle_event | `spotter.liveview.*` |
| TerminalChannel | Span events for join/input/resize/stream lifecycle | `spotter.channel.*` |

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

- JSON trace file: `tmp/otel/spotter-traces.json`
- Jaeger UI: `http://localhost:16686`

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
