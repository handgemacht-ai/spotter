# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- Multi-root transcript discovery via `transcript_roots` config key (spotter-j9d)
  - `transcript_roots` replaces `transcripts_dir` as the single source of truth for transcript location
  - DB storage as JSON array string, precedence: DB → TOML → defaults
  - Defaults: `[~/.claude/projects, ~/.claude_agents/projects]`
  - Path normalization: trim, dedupe, expand ~, make absolute, fallback to defaults if empty
  - Files: `lib/spotter/config/runtime.ex`, `lib/spotter/config/setting.ex`, `lib/spotter/transcripts/config.ex`
- `transcript_path` hint support for direct file resolution (spotter-j9d.2)
  - `SyncTranscripts.sync_session_by_id/2` accepts `transcript_path` option
  - `find_transcript_file` checks `transcript_path` first, falls back to multi-root search
  - `SessionEndFinalizer` and `SessionHookController` forward `transcript_path`
  - Trace attribute `spotter.transcript_path.source` ("direct" or "root_search")
  - Files: `lib/spotter/transcripts/jobs/sync_transcripts.ex`, `lib/spotter/services/session_end_finalizer.ex`, `lib/spotter_web/controllers/session_hook_controller.ex`
- Multi-root support in operational surfaces (spotter-j9d.3)
  - `mix spotter.live.configure` writes `transcript_roots` with both default roots
  - Shell scripts (`spotter_live_entrypoint.sh`, `prepare_runtime.sh`) create both root dirs
  - `snapshot_transcripts.sh` supports multiple colon-separated roots via `SNAPSHOT_TRANSCRIPT_ROOTS`
  - Hook scripts (`notify-session.sh`, `notify-session-end.sh`) forward `transcript_path`
  - `SPOTTER_LIVE_TRANSCRIPT_ROOTS` env var supported
- Cross-root deduplication in `TranscriptDiscovery` with first-root-wins ordering (spotter-j9d.4)
  - Deduplicates by `session_id` across multiple roots
  - 26 new tests across all beads
  - Files: `lib/spotter/services/transcript_discovery.ex`

### Changed

- Replaced `transcripts_dir` with `transcript_roots` across Runtime, Setting, TOML, and Transcripts.Config (spotter-j9d.1)
- Simplified hook scripts with consistent `SCRIPT_DIR` and removed dead guards (spotter-j9d.3)
- Updated README, `architecture.md`, and `product/SKILL.md` with multi-root documentation (spotter-j9d.3, spotter-j9d.4)

### Fixed

- Sanitized user paths in snapshot manifest to prevent home directory leak (spotter-j9d.3)

### Added

- `DashboardLive` at `/` — ongoing-only session view with live start/finish updates (spotter-05g.3)
  - PubSub-driven real-time updates via `SessionActivityBroadcaster` (extracted service)
  - Subscribes to session started/finished events, adds/removes cards without page reload
  - OTel spans: `spotter.dashboard.mount`, `spotter.dashboard.session_started`, `spotter.dashboard.session_finished`
  - Files: `lib/spotter_web/live/dashboard_live.ex`, `lib/spotter/services/session_activity_broadcaster.ex`
- `SessionsLive` at `/sessions` — full session list with project filter sidebar (spotter-05g.2)
  - Project filter chips, session table with status/duration/message count columns
  - Sidebar navigation link in root layout
  - README navigation table and QUICKSTART guide
  - Files: `lib/spotter_web/live/sessions_live.ex`, `lib/spotter_web/components/layouts/root.html.heex`, `lib/spotter_web/router.ex`
- E2E tests for dashboard ongoing sessions and sessions page (spotter-05g.2, spotter-05g.3)
  - Files: `e2e/tests/session.smoke.spec.ts`, `e2e/tests/dashboard.smoke.spec.ts`

### Changed

- Renamed `hook_ended_at` to `session_ended_at` across the entire stack (spotter-05g.1)
  - True column rename migration (not drop+add)
  - Updated Ash resource attribute, finalizer, controllers, rollup queries
  - Files: `priv/repo/migrations/*_rename_hook_ended_at.exs`, `lib/spotter/transcripts/session.ex`, `lib/spotter/services/session_rollup.ex`, `lib/spotter_web/controllers/hooks_controller.ex`
- Dashboard route moved from full session list to ongoing-only view; session list moved to `/sessions` (spotter-05g.2, spotter-05g.3)
- Replaced `String.to_existing_atom` with explicit `case` match for sort field parsing (review finding)

### Added

- `ShellCommandEvent` Ash resource — append-only event log extracted from raw hook payloads (spotter-nqk.1)
  - `ShellCommandExtractor` service with recursive command extraction from hook payloads, depth-limited traversal, phase mapping (PreToolUse/PostToolUse/PostToolUseFailure), and fail-safe persistence
  - Upsert identity for idempotent event ingestion
  - Integrated into `HooksController` with OTel span `spotter.shell_telemetry.ingest`
  - Files: `lib/spotter/transcripts/shell_command_event.ex`, `lib/spotter/services/shell_command_extractor.ex`, `lib/spotter_web/controllers/hooks_controller.ex`
- `ShellCommandTelemetryQuery` service for run folding, percentiles, and error rates (spotter-nqk.2)
  - `snapshot/2` and `snapshot_all_projects/1` fold events into runs by {tool_use_id, command, command_path}
  - Per-command metrics: p50/p90/p95 latency, error rate, mean/median duration
  - Time window filtering: `:last_24h`, `:last_7d`, `:last_30d`, `:all`
  - Files: `lib/spotter/services/shell_command_telemetry_query.ex`
- `ShellTelemetryLive` LiveView at `/telemetry/commands` (spotter-nqk.3)
  - Project and time-window selectors
  - Summary metrics row: mean, median, p50, p90, p95, error rate
  - Per-command table sorted by median_ms DESC with ongoing elapsed timer
  - Sidebar navigation link and documentation
  - Files: `lib/spotter_web/live/shell_telemetry_live.ex`, `lib/spotter_web/router.ex`, `lib/spotter_web/components/layouts/root.html.heex`, `docs/telemetry/command-telemetry-page.md`
- PubSub live updates for telemetry page (spotter-nqk.4)
  - Broadcast on shell command ingestion with centralized `telemetry_topic/1` (single source of truth)
  - LiveView subscription with 300ms debounce coalescing (immediate first load + timer-gated bursts)
  - OTel spans for ingest and live refresh paths
  - Ingestion failures remain fail-safe (rescue around PubSub)
  - Files: `lib/spotter/transcripts/shell_command_event.ex`, `lib/spotter_web/live/shell_telemetry_live.ex`

### Changed

- Disabled Ash auto-tracing in `test.exs` to prevent OTel processor contention (spotter-nqk.4)
- Removed duplicate `config :opentelemetry` that silently overrode exporter config (spotter-nqk.4)

### Fixed

- UTF-8 safe string truncation — replaced `binary_part` (byte-indexed) with `String.slice` (codepoint-aware) to prevent splitting multi-byte characters

### Added (spotter-gw2)

- Retro LiveView at `/retros` with project-filtered retrospective submission browser (spotter-gw2)
  - `SpotterWeb.RetrosLive` LiveView following ReviewsLive patterns with `project_id` query param
  - Project filter chips with submission counts, auto-select first project, empty state handling
  - Expandable submission cards with color-coded category badges (knowledge_gained, effective_strategy, gotcha, requirements_clarity, struggle)
  - Rating buttons (useful/undecided/not_useful) with active state highlighting and distribution summary on collapsed headers
  - Sidebar nav link in `root.html.heex`
  - `has_many :retro_submissions` relationship on `Project` resource
  - OTel span: `spotter.retros_live.rate_item`
  - CSS for category badge colors (5 categories) and rating button states using design tokens
  - 19 new integration tests
  - Files: `lib/spotter_web/live/retros_live.ex`, `test/spotter_web/live/retros_live_test.exs`, `lib/spotter_web/router.ex`, `lib/spotter_web/components/layouts/root.html.heex`, `priv/static/assets/spotter.css`, `lib/spotter/transcripts/project.ex`

- `RetroSubmission` and `RetroItem` Ash resources for structured agent retrospectives (spotter-xnz.1)
  - `retro_submissions` table with `session_id`, `agent_name`, `submitted_at` columns
  - `retro_items` table with `category` (enum: went_well, frustrating, surprising, do_differently, open_questions), `content`, `rating` (1-5)
  - Migration: `priv/repo/migrations/20260226212526_add_retro_submissions_and_items.exs`
  - Files: `lib/spotter/transcripts/retro_submission.ex`, `lib/spotter/transcripts/retro_item.ex`
- MCP actions for retrospective submission and querying (spotter-xnz.2)
  - `submit_retro` — accepts structured retro data (5 categories) and persists submission + items
  - `list_retros` — lists retrospective submissions with optional session/agent filters
  - `rate_retro_item` — rates individual retro items on a 1-5 scale
  - OTel tracing on all three actions
  - Registered in `SpotterWeb.Plugs.SpotterMcpPlug`
  - Files: `lib/spotter_web/plugs/spotter_mcp_plug.ex`, `lib/spotter/transcripts.ex`
- Global Spotter MCP configuration in `personal_claude` (spotter-xnz.3)
  - `.mcp.json` entry and Makefile target for workspace-wide MCP access
- New structured retro skill with 5 reflection categories and Wait re-examination (spotter-xnz.4)
  - Categories: went_well, frustrating, surprising, do_differently, open_questions
  - Includes Wait step for agents to re-examine their observations before submitting
  - No action items — retrospectives capture observations only
- Deprecated old rig-level retro skill in favor of new structured skill (spotter-xnz.5)
- 38 new tests covering RetroSubmission, RetroItem, and MCP actions
  - Files: `test/spotter/transcripts/retro_submission_test.exs`, `test/spotter/transcripts/retro_item_test.exs`, `test/spotter/transcripts/retro_item_rate_test.exs`, `test/spotter/transcripts/retro_mcp_actions_test.exs`

- Table-based lanes layout with CSS Grid, sticky time column, and wall clock + offset display (spotter-4iv.1, spotter-4iv.4, spotter-4iv.5)
  - Rewrote `lanes_components.ex` from flex columns to CSS Grid table layout
  - Sticky time column with wall clock and offset display
  - Collapsed/expanded message cells with tool badges
  - Expand all / collapse all / collapse idle toolbar actions
  - Row normalization with 1-second grouping for time-aligned display
  - Files: `lib/spotter_web/components/lanes_components.ex`, `lib/spotter/transcripts/parallel_lanes.ex`, `lib/spotter_web/live/session_live.ex`, `priv/static/assets/spotter.css`
- Idle period detection with labeled idle rows for gaps >60 seconds (spotter-4iv.2)
  - `ParallelLanes.compute/1` detects gaps between messages and inserts idle period markers
  - Hatched-row CSS styling for idle periods with duration labels
  - Files: `lib/spotter/transcripts/parallel_lanes.ex`, `lib/spotter_web/components/lanes_components.ex`
- Inter-agent SendMessage cross-lane link badges on message headers (spotter-4iv.3)
  - Link badges with `data-link-direction`, `data-link-peer`, `data-link-preview` attributes
  - `data-msg-uuid` and `data-agent-name` on message cells for receiver lookup
  - Files: `lib/spotter_web/components/lanes_components.ex`
- SortableJS drag-and-drop column reordering on desktop (spotter-4iv.6)
  - `SortableColumns` JS hook for desktop grid header drag-and-drop
  - Persist column order to localStorage keyed by session ID
  - Drag handle (grip icon) on column header hover with ghost/chosen/drag CSS feedback
  - "Reset order" toolbar button resets to `started_at` sort
  - Files: `assets/js/hooks/sortable_columns.js`, `assets/js/app.js`, `lib/spotter_web/components/lanes_components.ex`, `lib/spotter_web/live/session_live.ex`
- SVG hover connectors and click drawer for inter-agent message links (spotter-4iv.7)
  - `ConnectorOverlay` JS hook draws dashed SVG connector line with arrowhead on badge hover (100ms debounce)
  - Highlight receiver cell with accent outline during hover
  - Click badge to open message drawer with content preview and peer info
  - "Jump to response" scrolls to and highlights the receiver cell
  - SVG overlay is `pointer-events:none`, positioned absolute over grid
  - Files: `assets/js/hooks/connector_overlay.js`, `assets/js/app.js`, `lib/spotter_web/components/lanes_components.ex`

### Removed

- MCP tools `list_sessions`, `list_hotspots`, `list_retros`, `rate_retro_item` from the exposed MCP surface (spotter-q9p)
  - Retained tools: `list_review_annotations`, `resolve_annotation`, `create_hotspot`, `submit_retro`
  - Tool declarations removed from `Spotter.Transcripts` domain and `SpotterWeb.SpotterMcpPlug` allowlist
  - Underlying Ash resource actions are preserved for internal use
  - Spotter review and retro skill docs updated to reflect reduced tool surface

### Fixed

- CSS layout: `.main-content` overflow-x clipping and `.lanes-container` flex sizing (spotter-4iv.1)
- `sanitize_agent_name` nil guard and `format_offset` negative diff guard (spotter-4iv.5)
- Pre-existing test isolation: timezone filter, broadcast pattern match (spotter-4iv)

### Added

- Team-aware auto-import of sister sessions (spotter-s0p.1)
  - `TranscriptDiscovery.build_preview/3` now extracts `team_name` and `agent_name` from JSONL first line
  - `TranscriptDiscovery.group_by_team/1` clusters previews by team name
  - "Import Team" bulk action in `ImportModalComponents` imports all team members in one click
  - OTel span: `spotter.import.team_bulk` with `team_name`, `member_count` attributes
  - Files: `lib/spotter/services/transcript_discovery.ex`, `lib/spotter_web/components/import_modal_components.ex`, `lib/spotter_web/live/pane_list_live.ex`
- Full-fidelity lane rendering through TranscriptRenderer pipeline (spotter-s0p.2)
  - Each lane calls `TranscriptRenderer.render/2` producing rendered_lines with tool blocks, code blocks, and markdown
  - `ParallelLanes.compute/1` now includes `rendered_lines` per lane
  - Lane columns use `transcript_panel`/`transcript_row` components matching the main list view
  - OTel span: `spotter.lanes.render_lane` with `session_id`, `lane_agent_name`, `message_count`
  - Files: `lib/spotter_web/components/lanes_components.ex`, `lib/spotter/transcripts/parallel_lanes.ex`, `lib/spotter/services/transcript_renderer.ex`, `lib/spotter_web/live/session_live.ex`
- SortableJS drag-and-drop reorder on lane tab bar (spotter-s0p.4)
  - `LaneDrag` LiveView JS hook initializes SortableJS on tab bar container
  - `reorder_lanes` event stores order in socket assigns (session-scoped, no DB persistence)
  - Lane columns and tabs re-render in new order with drag animation
  - Files: `assets/js/hooks/lane_drag.js`, `lib/spotter_web/components/lanes_components.ex`, `lib/spotter_web/live/session_live.ex`, `assets/package.json`

### Changed

- Replaced time_axis overlay with independent scrollable lane panels (spotter-s0p.3)
  - Removed `time_axis/1` component and overlap bar rendering from lanes view
  - Each lane column is now an independently scrollable panel
  - Simplified `SessionLive` lane data passing
  - Files: `lib/spotter_web/components/lanes_components.ex`, `lib/spotter_web/live/session_live.ex`

### Fixed

- Duplicate HTML element IDs in transcript rows when rendering lanes (spotter-s0p.4)

- `--scenario` and `--cleanup` flags for e2e seed mix task (`mix spotter.e2e.seed`) (bd-e8f.1)
  - `--scenario=team_overlap` creates deterministic test data with fixed timestamps and agent names
  - `--cleanup` removes scenario-specific seed data via FK-safe cascading deletes (annotation refs → annotations → tool_calls → file_snapshots → session_commit_links → session_reworks → subagents → messages → team_members → sessions → orphaned teams)
  - Deterministic UUIDs (`00000000-0000-0000-0000-00000000000N`) for reproducible e2e state
  - Auto-upserts `e2e-spotter` project so `SyncTranscripts` processes fixture files
  - 6 new tests covering seed, cleanup, and scenario edge cases
  - Files: `lib/mix/tasks/spotter.e2e.seed.ex`, `test/mix/tasks/spotter.e2e.seed_test.exs`
- 8 `data-testid` selectors on lanes LiveView components for stable e2e targeting (bd-e8f.2)
  - Selectors: `lanes-panel`, `lane-tab-{agent}`, `lane-column-{agent}`, `lane-name`, `lane-duration`, `lanes-time-axis`, `overlap-bar-{HH:MM}`, `overlap-time-{HH:MM}`
  - Added `sanitize_agent_name/1` for parametric selector generation
  - 8 new unit tests (14 total)
  - Files: `lib/spotter_web/components/lanes_components.ex`, `test/spotter_web/components/lanes_components_test.exs`
- `LanesPage` Page Object Model for e2e tests (bd-e8f.3)
  - Parametric locators: `tab(name)`, `column(name)`, `overlapBar(time)`, `overlapTime(time)`
  - Scoped locators: `laneName(agent)`, `laneDuration(agent)` within column
  - Assertion helpers: `expectVisible()`, `expectTabCount()`, `expectColumnCount()`, `expectLaneName()`, `expectLaneDuration()`, `expectOverlapsPresent()`, `expectOverlapCount()`, `expectTabActive()`
  - Navigation: `goto(sessionId)`, `switchToLanesView()`
  - Files: `e2e/support/pages/lanes.ts`
- Rewrote `session-lanes.smoke.spec.ts` with semantic assertions (bd-e8f.4)
  - Desktop (1440x900): 6 tests — column count, agent names, durations (30m/15m/20m), overlap regions, time axis, snapshot
  - Responsive tabs (768x900): 3 tests — tab bar visibility, default active tab, tab switching (below `@media (max-width: 1199px)` breakpoint)
  - Deterministic fixtures: team-lead 10:00–10:30, qa-tester 10:05–10:20, implementer 10:10–10:30
  - Files: `e2e/tests/session-lanes.smoke.spec.ts`
- Documented e2e setup/cleanup contract in `e2e/CLAUDE.md` (bd-e8f.5)
  - Scenario seed/cleanup lifecycle, POM convention, new-scenario guide

### Added

- `Spotter.Test.OtelHelpers` module for OpenTelemetry span assertions in tests (sp-mvg)
  - 7 public functions: `setup_otel_test/1`, `assert_span_recorded/2`, `assert_span_attributes/3`, `assert_span_status/3`, `assert_child_span/3`, `refute_span_recorded/2`, `collect_spans/1`
  - `:otel_exporter_pid` pattern routes finished spans to test process mailbox
  - `:otel_simple_processor` config added to `test.exs` for test-time span routing
  - 17 meta-tests covering all helpers
  - Files: `test/support/otel_helpers.ex`, `test/spotter/test/otel_helpers_test.exs`, `config/test.exs`
- Import transcripts from dashboard modal (bd-ehi)
  - `Spotter.Services.TranscriptDiscovery` — filesystem scanner for `~/.claude/projects` JSONL transcripts; extracts metadata (message count, team session detection, project name, timestamps) via first-line parse and `sessions-index.json`; batch DB check for already-imported sessions; capped at 500 results
  - `Spotter.Services.TranscriptListing` — in-memory pagination, sort by last_modified/message_count/project_name, case-insensitive text search, project filter dropdown population
  - `SpotterWeb.ImportModalComponents` — extracted Phoenix.Component with `import_modal/1`; full modal with overlay, table, filter/sort controls, pagination, MapSet-based checkbox selection with select-all, import progress indicator, error display
  - `SpotterWeb.PaneListLive` — import button in dashboard header, modal state management, async transcript loading via Task with `send(self(), ...)` callback, PubSub broadcast on import completion
  - Modal CSS using Graphite design tokens (overlay, dialog, header/body/footer, already-imported row styling, error states)
  - ARIA dialog attributes (`role="dialog"`, `aria-modal`, `aria-labelledby`)
  - OTel spans: `spotter.transcript_discovery.discover`, `.scan_directory`, `spotter.transcript_listing.list`, `spotter.import_modal.open`, `.list`, `.import`, `.import_complete`
  - Sort allow-list pattern (explicit case match, no `String.to_existing_atom` on user input)
  - 45 tests: 9 discovery + 11 listing + 25 modal (shell, table, filter/sort/pagination, selection, import action + telemetry)
  - Beads: bd-ehi.1 (discovery), bd-ehi.2 (listing), bd-ehi.3 (modal), bd-ehi.4 (import action)


- `Spotter.Observability.ParallelLanesTelemetry` module for parallel transcript lanes observability (sp-7cxo.16, parent: sp-7cxo)
  - `spotter.parallel_lanes.compute` span — attributes: `lane_count`, `overlap_count`, `team_id`
  - `spotter.parallel_lanes.mode_switch` span — attributes: `from_mode`, `to_mode`, `session_id`
  - Full `:start`/`:stop`/`:exception` lifecycle with `ErrorReport.set_trace_error/4`
  - Follows established `LiveviewOtel`/`ObanTelemetry` patterns (detach/attach_many, rescue fail-safety)
  - Wired into `Spotter.Application` startup via `setup/0`

### Changed

- Migrated `LiveviewOtel` from bare `Tracer.start_span`/`end_span` to `OpentelemetryTelemetry.start_telemetry_span`/`end_telemetry_span` (sp-7tz)
  - Eliminates context leak in long-lived LiveView socket processes
  - Handler ID normalized from atom to string `"spotter.telemetry.liveview_otel"`
  - Added `{:opentelemetry_telemetry, "~> 1.1"}` as explicit dependency
  - Files: `lib/spotter_web/telemetry/liveview_otel.ex`, `mix.exs`
- Disabled `OpentelemetryPhoenix` built-in LiveView handler (`liveview: false`) to prevent conflicting handler (sp-7tz)
  - File: `lib/spotter/telemetry/otel.ex`
- Refactored `parallel_lanes_telemetry_test.exs` to use `OtelHelpers`, now asserts actual span emission (sp-mvg)

### Fixed

- Span context leak in `ParallelLanesTelemetry` — removed 6 dead handlers and `Tracer.end_span()` from :stop handler; business logic's `with_span` owns lifecycle (sp-7tz)
  - Module shrunk from ~147 to ~67 lines
  - Added `:error` handler
- `set_current_span` in `ParallelLanesTelemetry` start handlers (sp-mvg)
- Flaky test `history_live_test:56` default branch selection tagged with `@tag :flaky` (sp-4fw)

### Known Issues

- `sp-nuvm`: start_span/end_span context leak in telemetry handlers (affects LiveviewOtel too)
