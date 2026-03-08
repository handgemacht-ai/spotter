# External Integrations

| Service | Purpose | Module/File | Config |
|---------|---------|-------------|--------|
| Git | Commit metadata, history, blame, diff, patch-ids | `Spotter.Services.GitRunner` (port-based), `GitLogReader`, `GitCommitReader` | Port-based execution, 10s default timeout, 1MB output limit |
| tmux | Live transcript tail during active sessions | `TranscriptTailAdapter`, `TranscriptTailSupervisor`, `TranscriptTailWorker` | GenServer + `tail -f` subprocess, 500ms debounce |
| Claude Code Plugin | Hook event capture + MCP server access | `spotter-plugin/` (bash scripts + `.mcp.json`) | HTTP hooks with p95 <= 75ms target, cURL timeouts 0.1s connect / 0.3s total |
| OpenTelemetry | Distributed tracing across hooks, controllers, jobs, LiveViews | `lib/spotter/telemetry/otel.ex`, `lib/spotter/observability/` | OTLP exporter, Jaeger UI at `:14686`, configurable via `OTEL_EXPORTER_OTLP_ENDPOINT` |
| SQLite | All data persistence (Ash resources + Oban job queue) | AshSqlite data layer, `Oban.Engines.Lite` | Single-file database, no external DB server |
| Phoenix PubSub | Real-time UI updates (session activity, sync progress, review counts, telemetry) | In-process PubSub (no external broker) | Topic-based pub/sub within the Erlang VM |
