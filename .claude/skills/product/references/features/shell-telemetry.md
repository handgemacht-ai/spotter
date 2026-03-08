# Shell Command Telemetry

## Why This Exists

Understanding which shell commands Claude Code agents run — how often, how long they take, and how often they fail — reveals performance bottlenecks and reliability issues in agent workflows.

## What It Does

A per-project telemetry dashboard showing shell command metrics with time window selection. Displays summary stats (mean, median, p50, p90, p95 latency, error rate) and a per-command table sorted by median duration, with ongoing commands showing a live elapsed timer.

## User Flow

1. Navigate to Telemetry via sidebar
2. Select a project and time window (24h / 7d / 30d / all)
3. View summary metrics row at top
4. Browse per-command table: command name, path, execution count, latency percentiles, error rate
5. See ongoing commands with a live elapsed timer
6. Data updates live as new commands are ingested

## How It Works

`ShellCommandTelemetryQuery` folds `ShellCommandEvent` records into runs by `{tool_use_id, command, command_path}`, computing per-command metrics (p50/p90/p95 latency, error rate, mean/median duration). Time window filtering supports `:last_24h`, `:last_7d`, `:last_30d`, `:all`. The LiveView subscribes to a PubSub topic (centralized via `ShellCommandEvent.telemetry_topic/1`) and coalesces updates with a 300ms debounce (immediate first load + timer-gated bursts). A 1-second tick updates elapsed timers for ongoing commands.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/telemetry/commands` | Shell telemetry LiveView |
| GET | `/projects/:project_id/telemetry/commands` | Project-scoped telemetry |

## Key Files

- **LiveView**: `lib/spotter_web/live/shell_telemetry_live.ex`
- **Service**: `lib/spotter/services/shell_command_telemetry_query.ex`
- **Resource**: `lib/spotter/transcripts/shell_command_event.ex`
- **Extractor**: `lib/spotter/services/shell_command_extractor.ex`

## Data Model

`ShellCommandEvent` with `session_id`, `tool_use_id`, `command`, `command_path`, `phase` (start/finish), `finish_status` (ok/error/unknown), `captured_at`. Events are extracted from `RawHookEvent` by `ShellCommandExtractor` with recursive command key traversal and phase mapping.

## Constraints & Edge Cases

- Events are upserted with identity to prevent duplicates
- Run folding matches start/finish events by `{tool_use_id, command, command_path}`
- Commands without a finish event are treated as "ongoing" with live elapsed display
- PubSub broadcast on ingestion is fail-safe (rescue around PubSub.broadcast)
- 300ms debounce prevents UI thrashing during burst ingestion
