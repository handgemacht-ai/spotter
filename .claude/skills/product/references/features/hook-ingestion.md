# Hook Event Ingestion Pipeline

## Why This Exists

Spotter needs to capture all events from Claude Code sessions — tool calls, file changes, shell commands, subagent lifecycle, instruction loads — in real-time. The plugin hook system is the primary data ingestion path.

## What It Does

Six HTTP endpoints accept events from plugin hook scripts. Events are stored as raw records and then processed by specialized extractors that persist structured data and enqueue background enrichment jobs.

## User Flow

This is infrastructure — no direct user interaction. Events flow automatically from the Claude Code plugin to Spotter whenever Claude is running.

## How It Works

### Ingestion Flow

```
Claude Code hook event
  -> spotter-plugin/scripts/* (capture + forward)
  -> POST /api/hooks/* (HTTP)
  -> HooksController / SessionHookController
  -> Raw event stored (RawHookEvent)
  -> Extractors run:
     - ShellCommandExtractor (shell commands)
     - SubagentLifecycleIngestor (subagent start/stop)
     - InstructionsLoadedExtractor (instruction file loads)
  -> Oban jobs enqueued:
     - SyncTranscripts (JSONL -> DB)
     - EnrichCommits (git metadata)
     - IngestRecentCommits (commit backfill)
     - ComputeHeatmap / ComputeCoChange (analysis)
```

### Hook Events Handled

| Hook Event | Script | Endpoint | What's Captured |
|-----------|--------|----------|-----------------|
| SessionStart | `notify-session.sh` | `/api/hooks/session-start` | Session creation, tail worker start |
| SessionEnd | `notify-session-end.sh` | `/api/hooks/session-end` | Session finalization, job enqueueing |
| PreToolUse | `pre-tool-capture.sh` | `/api/hooks/file-snapshot` | File state before tool execution |
| PostToolUse | `post-tool-capture.sh` | `/api/hooks/file-snapshot`, `/commit-event`, `/tool-call` | File state after, commits, tool results |
| All events | `raw-event-forward.sh` | `/api/hooks/raw-event` | Raw payload for extraction |

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/hooks/session-start` | Session lifecycle start |
| POST | `/api/hooks/session-end` | Session lifecycle end |
| POST | `/api/hooks/file-snapshot` | File state capture |
| POST | `/api/hooks/tool-call` | Tool invocation capture |
| POST | `/api/hooks/commit-event` | Commit hash capture |
| POST | `/api/hooks/raw-event` | Raw event storage |
| POST | `/api/hooks/waiting-summary` | Status polling fallback |

## Key Files

- **Controller**: `lib/spotter_web/controllers/hooks_controller.ex`
- **Controller**: `lib/spotter_web/controllers/session_hook_controller.ex`
- **Extractor**: `lib/spotter/services/shell_command_extractor.ex`
- **Extractor**: `lib/spotter/services/subagent_lifecycle_ingestor.ex`
- **Extractor**: `lib/spotter/services/instructions_loaded_extractor.ex`
- **Resource**: `lib/spotter/transcripts/raw_hook_event.ex`
- **Plugin**: `spotter-plugin/` (hook scripts + config)

## Data Model

`RawHookEvent` stores the complete payload with `session_id`, `hook_event_name`, `tool_name`, `tool_use_id`, `hook_payload` (map), `env` (map). Extractors create `ShellCommandEvent`, `Subagent`, and `InstructionsLoadedEvent` from raw events. `FileSnapshot` captures before/after file states. `ToolCall` records tool invocations with error status.

## Constraints & Edge Cases

- Hook scripts have a p95 target of 75ms, hard budget of 200ms
- cURL timeouts: `--connect-timeout 0.1`, `--max-time 0.3`
- Silent-fail semantics: hooks never block Claude Code
- Raw events are upserted to handle duplicate deliveries
- Extraction failures are fail-safe (rescue + log, never crash the request)
- W3C `traceparent` header propagated from plugin for trace correlation
- `SessionEnd` is authoritative for session completion (not `Stop`)
