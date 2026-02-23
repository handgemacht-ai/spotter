# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- `ParallelLanesTelemetry` module with `setup/0` for application startup wiring (sp-7cxo.16)
  - `spotter.parallel_lanes.compute` span with `lane_count`, `overlap_count`, and `team_id` attributes
  - Mode-switch span for tracking parallel lane mode transitions
  - String-based `handler_id` convention and structured exception reason extraction
  - 5 tests covering compute span and mode-switch handlers
  - Commits: e92b7db, 8a7e444, d61fabc

### Fixed

- `handler_id` convention corrected to use string identifiers (d61fabc)
- Exception reason extraction improved in `ParallelLanesTelemetry` (d61fabc)
