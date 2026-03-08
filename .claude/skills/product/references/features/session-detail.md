# Session Detail (Transcript Review)

## Why This Exists

The core review workflow: understanding what a Claude Code agent did during a session by reading the full transcript, identifying code changes, and creating annotations for review.

## What It Does

Renders the full session transcript with tool call groups, code blocks, and markdown. Supports text selection for annotation capture (review or explain purpose), a sidebar with commits/hotspots/files/errors tabs, rework event markers, and commit link confidence badges. Also offers a parallel lanes view toggle for team sessions (see [parallel-lanes.md](parallel-lanes.md)).

## User Flow

1. Navigate from Dashboard or Sessions list → click a session
2. Read the transcript (messages rendered with syntax highlighting, tool groups collapsible)
3. Select text in the transcript to capture an annotation
4. Choose annotation purpose: "review" or "explain"
5. Save annotation — it appears in the Reviews page
6. Browse sidebar tabs for related commits, hotspots, changed files, and errors
7. For team sessions, toggle to lanes view for side-by-side agent comparison

## How It Works

`TranscriptComputers` (AshComputer module) handles reactive data loading: messages, annotations, commit links, rework events, subagent labels, and rendered transcript lines via `TranscriptRenderer`. The renderer pipeline processes JSONL messages into displayable lines with tool blocks, code blocks, and markdown rendering. Text selection uses JS hooks that capture selected text + message UUIDs and push them to the LiveView for annotation creation. View mode toggles between `list` (default transcript) and `lanes` (parallel agent view).

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/sessions/:session_id` | Session detail LiveView |

## Key Files

- **LiveView**: `lib/spotter_web/live/session_live.ex`
- **Computers**: `lib/spotter_web/live/transcript_computers.ex`
- **Component**: `lib/spotter_web/components/transcript_components.ex`
- **Component**: `lib/spotter_web/components/annotation_components.ex`
- **Service**: `lib/spotter/services/transcript_renderer.ex`
- **Service**: `lib/spotter/services/transcript_file_links.ex`
- **Service**: `lib/spotter/services/transcript_task_actions.ex`

## Data Model

Primary: `Session` with `has_many :messages`, `has_many :subagents`, `has_many :annotations`, `has_many :tool_calls`, `has_many :session_reworks`. Related: `SessionCommitLink` (with `Commit`) for commit sidebar, `CommitHotspot` for hotspots sidebar, `FileSnapshot` for files sidebar.

## Constraints & Edge Cases

- Messages are rendered in order with parent_uuid threading
- Tool call groups are collapsible (expand/collapse)
- Annotations require text selection + at least one message UUID
- Rework events highlight files that were edited multiple times
- Session activity broadcasts update the page if the session is still ongoing
