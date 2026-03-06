# Project Index

## Configuration

| Path | Purpose |
|------|---------|
| `mix.exs` | Project manifest, dependencies, aliases |
| `config/config.exs` | Base config (Ash, Oban, OpenTelemetry, JSON:API) |
| `config/dev.exs` | Development overrides |
| `config/prod.exs` | Production overrides |
| `config/test.exs` | Test environment |
| `config/runtime.exs` | Runtime config (env variables) |
| `.credo.exs` | Credo linting rules |
| `.formatter.exs` | Code formatting |
| `.worktree-ports.json` | Port mapping per worktree |
| `Procfile.dev` | Process manager (Phoenix + services) |

## Source Directories

| Path | Contents |
|------|----------|
| `lib/spotter/transcripts/` | Ash domain, resources, jobs |
| `lib/spotter/services/` | Business logic services (~33 modules) |
| `lib/spotter/observability/` | Telemetry (FlowHub, ObanTelemetry, error reporting) |
| `lib/spotter/telemetry/` | OpenTelemetry setup (OTLP exporter, trace context) |
| `lib/spotter/config/` | Runtime configuration (EnvParser, Setting) |
| `lib/spotter/search/` | Full-text search (FTS5/LIKE, indexer, reindex job) |
| `lib/spotter_web/controllers/` | HTTP endpoints (hooks, search, MCP) |
| `lib/spotter_web/live/` | LiveView pages (15 modules) |
| `lib/spotter_web/components/` | Reusable HEEX components |
| `lib/spotter_web/channels/` | WebSocket channels (ReviewsChannel) |
| `lib/spotter_web/plugs/` | Custom plugs (SpotterMcpPlug) |
| `lib/spotter_web/telemetry/` | LiveView OTEL instrumentation |
| `lib/spotter_web/router.ex` | Phoenix routes |

## Frontend & Static

| Path | Contents |
|------|----------|
| `assets/` | JS/CSS source (esbuild-compiled) |
| `priv/static/` | Compiled static assets |

## Tests

| Path | Contents |
|------|----------|
| `test/` | ExUnit tests (~102 files) |
| `e2e/` | Playwright E2E tests |

## Infrastructure

| Path | Contents |
|------|----------|
| `priv/repo/migrations/` | SQLite migrations |
| `scripts/` | Operational scripts (runtime, OTEL, e2e) |
| `spotter-plugin/` | MCP server plugin for Claude Code |

## Documentation

| Path | Contents |
|------|----------|
| `README.md` | Project overview, setup, runtime |
| `CHANGELOG.md` | Release history |
| `RELEASE_NOTES.md` | Latest release notes |
| `docs/design/` | Design docs (CLI UX, observability, lanes) |
| `docs/telemetry/` | Telemetry page docs |
| `.beads/` | Issue tracking (bd/beads) |
| `.beads/PRIME.md` | Sprint/epic summary |
