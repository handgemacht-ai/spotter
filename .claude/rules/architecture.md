# Architecture Overview

## Stack

Elixir, Ash 3.0, Phoenix, LiveView, SQLite (AshSqlite), Oban (Lite engine), OpenTelemetry, xterm.js, tmux, esbuild

Localhost prototype, no authentication.

## Domain Layer

`Spotter.Transcripts` — primary Ash domain with ~31 resources:

| Resource | Purpose |
|----------|---------|
| Project | Projects with transcript discovery patterns |
| Session | Claude Code sessions |
| Message | Chat messages within sessions |
| Subagent | Agentic sub-sessions |
| ToolCall | Tool invocations |
| Commit | Git commits |
| SessionCommitLink | Session-commit links with confidence scores |
| FileSnapshot | File state at points in time |
| FileHeatmap | File change frequency |
| CommitHotspot | Code hotspot analysis |
| CoChangeGroup | Co-change group analysis |
| Annotation | Review annotations |
| RetroItem, RetroSubmission | Retrospectives |
| Team, TeamMember | Team/subagent support |
| ShellCommandEvent | Shell command telemetry |
| ComputedLaneCache, ParallelLanes | Parallel processing flow |
| RawHookEvent | Raw hook event storage |

Secondary domain: `Spotter.Config` (runtime settings via `Setting` resource, `Runtime` accessor with DB → TOML → default precedence). `transcript_roots` is the authoritative config key for transcript discovery paths (JSON array string in DB, TOML array in `priv/spotter.toml`).

## Services Layer (`lib/spotter/services/`)

- **Git**: GitRunner (port-based, timeout-safe), GitLogReader, GitCommitReader
- **File analysis**: FileDetail, FileBlame, FileMetrics
- **Commit analysis**: CommitDetail, CommitHistory, CommitDiffExtractor, CommitPatchExtractor, CommitHotspotFilters, CommitHotspotMetrics
- **Heatmap/co-change**: HeatmapCalculator, CoChangeCalculator, CoChangeIntersections
- **Session**: SessionCommitLinker, SessionEndFinalizer
- **Transcripts**: TranscriptDiscovery, TranscriptRenderer, TranscriptListing, TranscriptFileLinks, TranscriptTaskActions
- **Terminal**: TranscriptTailAdapter, TranscriptTailSupervisor, TranscriptTailWorker (tmux integration)
- **Other**: ShellCommandExtractor, ShellCommandTelemetryQuery, PromptCollector, AnnotationExplainPrompt, ProjectPeriodRollupPack, ReviewCounts, ReviewUpdates

## Web Layer (`lib/spotter_web/`)

**Controllers** (HTTP): HooksController, SessionHookController, SearchController, ReviewsRedirectController, SpotterMcpPlug
**LiveViews** (15): PaneListLive (dashboard), HistoryLive, CommitDetailLive, FileDetailLive, FileMetricsLive, SessionLive, SubagentLive, ReviewsLive, RetrosLive, ShellTelemetryLive, IngestProgressLive
**Channel**: ReviewsChannel (live review-count updates via WebSocket)
**Components**: Layouts, TranscriptComponents, AnnotationComponents, LanesComponents, ImportModalComponents

## Background Jobs (Oban)

All in `lib/spotter/transcripts/jobs/`:

| Worker | Purpose |
|--------|---------|
| SyncTranscripts | Scan JSONL files, ingest sessions/messages |
| EnrichCommits | Fetch commit metadata (parents, authors, files, patch-ids) |
| IngestRecentCommits | Run `git log` for new commits |
| ComputeHeatmap | File change frequency computation |
| ComputeCoChange | Co-change group analysis |
| ComputeLanes | Parallel processing lane computation |

Engine: `Oban.Engines.Lite` (SQLite-backed). Plugins: Cron + Lifeline (15-min rescue).

## Data Flow

```
Hook events (POST /api/hooks/*) --> Ash actions --> Oban enrichment pipeline --> LiveView UI
JSONL file discovery            --> SyncTranscripts job --> Session/Message creation
MCP requests (POST /api/mcp)    --> SpotterMcpPlug --> Ash reads
Git operations                  --> GitRunner (port-based, timeout-safe)
```

## Frontend

esbuild-compiled JS (no framework). Key libraries: cytoscape (DAG visualization), highlight.js, marked (markdown), sortablejs, dompurify.

## Plugin

`spotter-plugin/` — MCP server plugin for Claude Code integration. Receives hook events and provides MCP tool access.

## Canonical Span Naming

| Domain | Prefix | Example |
|---|---|---|
| Hotspot analysis | `spotter.commit_hotspots.*` | `spotter.commit_hotspots.create` |
| Claude queries | `spotter.claude_code.*` | `spotter.claude_code.query` |
| Git operations | `spotter.git.*` | `spotter.git.run` |
| File detail | `spotter.file_detail.*` | `spotter.file_detail.load_file_content` |
