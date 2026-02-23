# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- `Spotter.Observability.ParallelLanesTelemetry` module for parallel transcript lanes observability (sp-7cxo.16, parent: sp-7cxo)
  - `spotter.parallel_lanes.compute` span — attributes: `lane_count`, `overlap_count`, `team_id`
  - `spotter.parallel_lanes.mode_switch` span — attributes: `from_mode`, `to_mode`, `session_id`
  - Full `:start`/`:stop`/`:exception` lifecycle with `ErrorReport.set_trace_error/4`
  - Follows established `LiveviewOtel`/`ObanTelemetry` patterns (detach/attach_many, rescue fail-safety)
  - Wired into `Spotter.Application` startup via `setup/0`
  - 5 tests covering compute span and mode-switch handlers
  - Files: `lib/spotter/observability/parallel_lanes_telemetry.ex`, `test/spotter/observability/parallel_lanes_telemetry_test.exs`, `lib/spotter/application.ex`
  - Commits: e92b7db, 8a7e444, d61fabc

### Fixed

- String-based `handler_id` convention in `ParallelLanesTelemetry` (d61fabc)
- Structured exception reason extraction in telemetry handlers (d61fabc)

### Known Issues

- `sp-nuvm`: start_span/end_span context leak in telemetry handlers (affects LiveviewOtel too)
