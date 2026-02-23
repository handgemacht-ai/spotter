# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- `Spotter.Test.OtelHelpers` module for OpenTelemetry span assertions in tests (sp-mvg)
  - 7 public functions: `setup_otel_test/1`, `assert_span_recorded/2`, `assert_span_attributes/3`, `assert_span_status/3`, `assert_child_span/3`, `refute_span_recorded/2`, `collect_spans/1`
  - `:otel_exporter_pid` pattern routes finished spans to test process mailbox
  - `:otel_simple_processor` config added to `test.exs` for test-time span routing
  - 17 meta-tests covering all helpers
  - Files: `test/support/otel_helpers.ex`, `test/spotter/test/otel_helpers_test.exs`, `config/test.exs`
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
