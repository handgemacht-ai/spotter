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

## Plans Layer (`lib/spotter/plans/`)

Plan source abstraction for aggregating plans from multiple backends.

- **Plans** (`Spotter.Plans`): Public API coordinator — aggregates results from configured sources. `list_projects/0` merges via flat_map; `list_plans/2`, `get_plan/2`, `get_bead/2`, `list_children/2`, `list_dependencies/2` use first-success fallthrough. Sources configured via `config :spotter, Spotter.Plans, sources: [...]`. All functions wrapped in OTEL spans (`spotter.plans.*`).
- **PlanSource**: Behaviour defining callbacks — `list_projects/0`, `list_plans/2`, `get_plan/2`, `list_children/2`, `list_dependencies/2`
- **BeadsSource**: PlanSource implementation — pure delegation to `Spotter.Beads.BeadQueries`

## Beads Layer (`lib/spotter/beads/`)

Read-only client for querying beads issue data across projects via JSONL files.

- **JsonlStore**: GenServer per project — loads `issues.jsonl` + `dependencies.jsonl` from `.beads/backup/`, indexes in-memory, polls mtimes every 5s
- **Client**: In-memory lookups against JsonlStore (lazy-started per project)
- **DoltConfig**: Display/tracing name resolution for projects
- **BeadQueries**: High-level query interface returning typed structs with OTEL spans
- **BeadStructs**: Typed structs — Epic, Task, Dependency — with `from_row/1` converters
- **BeadContentParser**: Markdown parser — section splitting, mermaid extraction, GIVEN/WHEN/THEN tables

## ImageStore (`lib/spotter/image_store.ex`, `lib/spotter/image_store/`)

DI-based image storage for annotation screenshots. Follows the same behaviour + config pattern as `Spotter.Plans.PlanSource`.

- **Spotter.ImageStore**: Behaviour (`store/fetch/delete` callbacks) + public API delegating to configured adapter via `Application.get_env(:spotter, Spotter.ImageStore, adapter: ...)`
- **SqliteAdapter**: Default adapter — stores image blobs in `annotation_images` table via raw `Ecto.Adapters.SQL` against `Spotter.Repo`. 5MB size limit, upsert on duplicate `annotation_id`.

Config: `config :spotter, Spotter.ImageStore, adapter: Spotter.ImageStore.SqliteAdapter`

## Search Subsystem (`lib/spotter/search/`)

Unified full-text search over sessions, commits, hotspots, annotations, and files.

- **Spotter.Search**: Public facade — `search/2` delegates to Query
- **Search.Query**: Dual-backend query engine — SQLite FTS5 with BM25 ranking (primary), LIKE pattern matching (fallback when FTS5 unavailable)
- **Search.Indexer**: Idempotent batch indexer — builds search documents from Ash resources and git, upserts in chunks of 300 with batch timestamp, sweeps stale rows
- **Search.Result**: Typed struct (kind, project_id, external_id, title, subtitle, url, score)
- **Search.Jobs.ReindexProject**: Oban worker (queue: default, max_attempts: 3, unique per project 30s)

Indexed kinds: session, commit, commit_hotspot, annotation, file, directory. All operations wrapped in OTEL spans (`spotter.search.*`).

## Observability Layer (`lib/spotter/observability/`)

In-memory flow event system for real-time visualization of hook→job→enrichment pipelines.

- **FlowHub**: GenServer with ETS-backed event store (10K cap, 2h retention). Records events, broadcasts via PubSub (`flows:global`, `flows:<key>`)
- **FlowEvent**: Typed event struct with validation, sanitization, and W3C trace context derivation
- **FlowGraph**: Converts event snapshots into deterministic DAG model (nodes, edges, flows) for the `/flows` LiveView. Node types: session, commit, oban, agent_run
- **FlowKeys**: Namespaced key builders (`session:`, `commit:`, `oban:`, `agent_run:`, `project:`, `subagent:`)
- **ObanTelemetry**: Attaches to `[:oban, :job, :*]` events, emits FlowHub events with job metadata and trace context
- **ParallelLanesTelemetry**: Handles `[:spotter, :parallel_lanes, :compute, :*]` events
- **ErrorReport**: Structured error payload builders for both FlowHub events and OTEL span attributes
- **AgentRunInput**: Input normalization (atom/string key unification) for Oban job args

## Telemetry Layer (`lib/spotter/telemetry/`)

OpenTelemetry bootstrap and trace context utilities.

- **Otel**: Idempotent OTEL setup — Bandit + Phoenix instrumentation, opt-out via `SPOTTER_OTEL_ENABLED=false`
- **TraceContext**: W3C `traceparent` extraction from current span context

## Web Tracing (`lib/spotter_web/`)

- **OtelTraceHelpers**: Controller tracing macro (`with_span`), error recording (`set_error`), trace response headers (`x-spotter-trace-id`), job arg trace context injection
- **LiveviewOtel**: Custom LiveView telemetry handler using `OpentelemetryTelemetry` tracer stack — replaces OpentelemetryPhoenix's built-in LV handler to prevent context leaks between sequential callbacks

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

**Controllers** (HTTP): HooksController, SessionHookController, SearchController, AnnotationController, ReviewsRedirectController, SpotterMcpPlug
**LiveViews** (22): PaneListLive (dashboard), HistoryLive, CommitDetailLive, FileDetailLive, FileMetricsLive, SessionLive, SubagentLive, ReviewsLive, RetrosLive, ShellTelemetryLive, IngestProgressLive, PlansLive, PlanDetailLive, RepoLive, FolderViewLive
**Channel**: ReviewsChannel (live review-count updates via WebSocket)
**Components**: Layouts, TranscriptComponents, AnnotationComponents, LanesComponents, ImportModalComponents, PlanComponents, FolderComponents

### Web Plugs (`lib/spotter_web/plugs/`)

Custom middleware for request pipeline augmentation.

- **SpotterMcpPlug**: MCP endpoint at `/api/mcp` — wraps `AshAi.Mcp.Router` with OTEL tracing and 3-tier project scope resolution (header → session_id param → recent session fallback). Exposes tools: list_review_annotations, resolve_annotation, create_hotspot, submit_retro. Handles SSE transport with configurable keepalive (15s default).
- **ProjectContext**: Resolves current project from `?project=` query param via `ProjectHelpers`, assigns `:projects` and `:current_project_id` to conn for downstream use.

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

esbuild-compiled JS (no framework). Key libraries: cytoscape (DAG visualization), highlight.js, marked (markdown), sortablejs, dompurify, mermaid (lazy-loaded for plan diagrams).

**JS Hooks** (`assets/js/hooks/`): LaneDrag, SortableColumns, ConnectorOverlay, TranscriptTaskRail, MermaidHook (lazy-loads mermaid.js, renders SVG with dark theme), PlanContentHook (hljs syntax highlighting on Earmark-rendered code blocks + text selection for plan annotations).

## Plugin

`spotter-plugin/` — MCP server plugin for Claude Code integration. Receives hook events and provides MCP tool access.

## Canonical Span Naming

| Domain | Prefix | Example |
|---|---|---|
| Hotspot analysis | `spotter.commit_hotspots.*` | `spotter.commit_hotspots.create` |
| Claude queries | `spotter.claude_code.*` | `spotter.claude_code.query` |
| Git operations | `spotter.git.*` | `spotter.git.run` |
| File detail | `spotter.file_detail.*` | `spotter.file_detail.load_file_content` |
| Plans coordinator | `spotter.plans.*` | `spotter.plans.list_projects` |
| Repo tree | `spotter.repo_live.*` | `spotter.repo_live.load_tree` |
| Skill folders | `spotter.skill_folder.*` | `spotter.skill_folder.detect_folders` |
| Search | `spotter.search.*` | `spotter.search.query` |
| MCP endpoint | `spotter.mcp.*` | `spotter.mcp.http` |
| Web controllers | `spotter.web.*` | `spotter.web.search` |
