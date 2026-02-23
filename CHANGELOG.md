# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- `--scenario` and `--cleanup` flags for e2e seed mix task (`mix spotter.e2e.seed`) (bd-e8f.1)
  - `--scenario=session_lanes` creates deterministic test data with fixed timestamps and agent names
  - `--cleanup` removes scenario-specific seed data without affecting other records
  - 132+ lines of new tests covering scenario creation, cleanup, and edge cases
  - Files: `lib/mix/tasks/spotter.e2e.seed.ex`, `test/mix/tasks/spotter.e2e.seed_test.exs`
- 8 `data-testid` selectors on lanes LiveView components for stable e2e targeting (bd-e8f.2)
  - Selectors: `lane-row`, `lane-agent`, `lane-duration`, `lane-tab-count`, `lane-overlap-badge`, `lane-tabs-panel`, `lane-model-badge`, `lane-cost`
  - 129+ lines of new component tests verifying selector presence
  - Files: `lib/spotter_web/components/lanes_components.ex`, `test/spotter_web/components/lanes_components_test.exs`
- `LanesPage` Page Object Model for e2e tests (bd-e8f.3)
  - Encapsulates lane element queries, agent extraction, duration parsing, overlap detection
  - Files: `e2e/support/pages/`
- Rewrote `session-lanes.smoke.spec.ts` with semantic assertions (bd-e8f.4)
  - Asserts agent names, durations, overlaps, tab counts via Page Object Model
  - Replaced brittle snapshot-only checks with structural validation
  - Files: `e2e/tests/session-lanes.smoke.spec.ts`
- Documented e2e setup/cleanup contract in `e2e/CLAUDE.md` (bd-e8f.5)
  - Scenario lifecycle, selector conventions, test data expectations

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
