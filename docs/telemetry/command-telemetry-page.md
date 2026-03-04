# Command Telemetry Page

Shell command timing and error analytics for Claude Code sessions.

## Routes

| Route | Scope |
|---|---|
| `/telemetry/commands` | Global (first project auto-selected) |
| `/projects/:project_id/telemetry/commands` | Project-scoped (preselects given project) |

Sidebar nav link: **Telemetry** (under File metrics).

## Window Selector

| Option | Duration | Default |
|---|---|---|
| `last_24h` | 24 hours | |
| `last_7d` | 7 days | Yes |
| `last_30d` | 30 days | |
| `all` | No cutoff | |

Switching windows preserves the selected project. Window defaults to `last_7d` for unknown/missing values.

## Summary Metrics

Six aggregate cards computed across all commands in the selected project and window:

- **mean** -- average of per-command mean durations
- **median** -- average of per-command median durations
- **p50** -- average of per-command 50th percentile
- **p90** -- average of per-command 90th percentile
- **p95** -- average of per-command 95th percentile
- **error_rate** -- total errors / total finished (completed + errors)

## Per-Command Table

Sorted by `median_ms DESC, p95_ms DESC, count DESC` (via `ShellCommandTelemetryQuery.snapshot/2`).

| Column | Description |
|---|---|
| command | Exact command string (truncated at 80 chars with full title tooltip) |
| completed | Number of completed runs |
| ongoing | Number of runs without a finish event |
| error_rate | Errors / (completed + errors), displayed as percentage |
| mean | Mean duration in ms |
| median | Median duration |
| p50 | 50th percentile |
| p90 | 90th percentile |
| p95 | 95th percentile |
| last_seen | Relative time since last event |

Grouping key: exact command string (no normalization).

## Live Ongoing Display

A 1-second timer tick refreshes data from `ShellCommandTelemetryQuery`, updating ongoing elapsed durations and incorporating newly arrived events without manual page refresh.

## Empty State

When no command events exist for the selected project and window, an explicit empty state message is displayed instead of the table.

## Data Source

Single data source: `Spotter.Services.ShellCommandTelemetryQuery.snapshot/2`. Events originate from `ShellCommandEvent` records created by hook-based shell command extraction.
