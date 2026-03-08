# Sessions List

## Why This Exists

Users need to browse all sessions — past and present — organized by project, with the ability to hide noise, paginate through history, and manage per-project display settings like timezone.

## What It Does

A project-filtered session list with hide/unhide, cursor pagination (separate for visible and hidden), per-project timezone display, subagent expansion, and tool call/rework stats per session.

## User Flow

1. Navigate to Sessions via sidebar
2. Select a project from the filter chips
3. Browse sessions in reverse chronological order
4. Expand subagents inline to see agent details
5. Hide irrelevant sessions (moves them to a collapsible "hidden" section)
6. Click "Review" to navigate to session detail
7. Optionally set a timezone for the selected project

## How It Works

AshComputer-driven reactive queries load sessions scoped to the selected project. Cursor-based pagination loads more sessions on demand (separate cursors for visible and hidden). Tool call stats (total/failed counts) and rework stats are loaded per-session. Subagent data is lazily loaded on expansion.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/sessions` | Sessions list LiveView |

## Key Files

- **LiveView**: `lib/spotter_web/live/sessions_live.ex`
- **Component**: `lib/spotter_web/components/import_modal_components.ex`

## Data Model

Primary: `Session` (with `project_id` filter, `hidden_at` for hide/unhide). Related: `Project` for filter chips, `Subagent` for expansion, `ToolCall` for stats, `SessionRework` for rework counts.

## Constraints & Edge Cases

- Cursor pagination prevents loading entire session history at once
- Hidden sessions have their own pagination and load-more
- Timezone is stored per project (not per session)
- Import modal is embedded in this page (see [transcript-import.md](transcript-import.md))
