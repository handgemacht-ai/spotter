# Instructions Telemetry

## Why This Exists

Understanding what instruction files agents load — CLAUDE.md, memory files, skill files — and how much context they consume helps optimize agent configuration and identify bloated or unused instruction sources.

## What It Does

A per-project telemetry page showing instruction load events with file paths, memory types, load reasons, byte/line counts, and size status.

## User Flow

1. Navigate to Instructions Telemetry via sidebar
2. Select a project
3. View instruction load events grouped by file path
4. See metrics: bytes loaded, lines loaded, memory type, load reason

## How It Works

`InstructionsLoadedExtractor` persists `InstructionsLoadedEvent` records from raw hook events (fired on the `InstructionsLoaded` hook event type). `InstructionsTelemetryQuery` aggregates events for the selected project. The LiveView displays the data with project filtering.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/telemetry/instructions` | Instructions telemetry LiveView |
| GET | `/projects/:project_id/telemetry/instructions` | Project-scoped |

## Key Files

- **LiveView**: `lib/spotter_web/live/instructions_telemetry_live.ex`
- **Service**: `lib/spotter/services/instructions_telemetry_query.ex`
- **Resource**: `lib/spotter/transcripts/instructions_loaded_event.ex`
- **Extractor**: `lib/spotter/services/instructions_loaded_extractor.ex`

## Data Model

`InstructionsLoadedEvent` with `file_path`, `memory_type`, `load_reason`, `bytes_loaded`, `lines_loaded`, `size_status`, `captured_at`. Linked to `Session` and `Project` via IDs. Extracted from `RawHookEvent`.

## Constraints & Edge Cases

- Events are upserted to prevent duplicates
- Size status indicates whether the file was within expected bounds
- Memory type distinguishes CLAUDE.md, skills, auto-memory, etc.
