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
| `lib/spotter/services/` | Business logic services (~38 modules) |
| `lib/spotter/observability/` | Telemetry (FlowHub, ObanTelemetry, error reporting) |
| `lib/spotter/telemetry/` | OpenTelemetry setup (OTLP exporter, trace context) |
| `lib/spotter/plans/` | Plans coordinator, PlanSource behaviour, BeadsSource impl |
| `lib/spotter/beads/` | Dolt beads client, queries, structs, content parser |
| `lib/spotter/image_store.ex` | ImageStore behaviour + DI public API |
| `lib/spotter/image_store/` | ImageStore adapters (SqliteAdapter) |
| `lib/spotter/config/` | Runtime configuration (EnvParser, Setting) |
| `lib/spotter/search/` | Full-text search (FTS5/LIKE, indexer, reindex job) |
| `lib/spotter_web/controllers/` | HTTP endpoints (hooks, search, annotations, MCP) |
| `lib/spotter_web/live/` | LiveView pages (23 modules) |
| `lib/spotter_web/components/` | Reusable HEEX components (FolderComponents, PlanComponents, etc.) |
| `lib/spotter_web/channels/` | WebSocket channels (ReviewsChannel) |
| `lib/spotter_web/plugs/` | Custom plugs (SpotterMcpPlug, ProjectContext) |
| `lib/spotter_web/telemetry/` | LiveView OTEL instrumentation |
| `lib/spotter_web/project_helpers.ex` | Shared project selection helpers |
| `lib/spotter_web/project_context.ex` | LiveView on_mount hook for project context |
| `lib/spotter_web/router.ex` | Phoenix routes |

## Frontend & Static

| Path | Contents |
|------|----------|
| `assets/` | JS/CSS source (esbuild-compiled) |
| `assets/js/project_selector.js` | Sidebar project selector dropdown (standalone init) |
| `assets/js/hooks/mermaid_hook.js` | MermaidHook: lazy-loads mermaid.js, renders SVG diagrams |
| `assets/js/hooks/plan_content_hook.js` | PlanContentHook: hljs syntax highlighting + text selection for plan annotations |
| `assets/js/hooks/folder_content_hook.js` | FolderContentHook: hljs syntax highlighting + text selection for folder annotations |
| `priv/static/` | Compiled static assets |

## Tests

| Path | Contents |
|------|----------|
| `test/` | ExUnit tests (~102 files) |
| `e2e/` | Playwright E2E tests |
| `e2e/tests/plans.smoke.spec.ts` | Plans list view e2e tests |
| `e2e/tests/plan-detail.smoke.spec.ts` | Plan detail view e2e tests |
| `e2e/support/pages/plans.ts` | PlansPage POM |
| `e2e/support/pages/plan-detail.ts` | PlanDetailPage POM |

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
