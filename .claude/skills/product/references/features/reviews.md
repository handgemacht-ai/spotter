# Reviews (Annotation Management)

## Why This Exists

Annotations created across multiple sessions and files need a centralized place for triage, review, and resolution. Without this, annotations scatter across individual session transcripts with no overview.

## What It Does

A project-filtered annotation dashboard showing open and resolved annotations in separate sections. Each annotation displays its source, purpose, selected text, comment, file refs, and message refs. Live count updates via WebSocket keep the sidebar badge current.

## User Flow

1. Navigate to Reviews via sidebar
2. Select a project from filter chips (shows per-project open counts)
3. Browse open annotations — each shows source badge, purpose, text excerpt, file/message refs
4. Resolve annotations (marks them as closed)
5. Scroll down to see resolved annotations
6. Sidebar badge updates in real-time as annotations are created/resolved

## How It Works

`ReviewsLive` loads annotations filtered by project and state (open/resolved). `ReviewsChannel` (WebSocket on topic `reviews:counts`) pushes live count updates whenever annotation state changes, triggered by `ReviewUpdates` service. `ReviewCounts` aggregates per-project open counts for the filter chips. Annotations can also be resolved via the MCP `resolve_annotation` tool (see [mcp-server.md](mcp-server.md)).

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/reviews` | Reviews LiveView |
| GET | `/projects/:project_id/review` | Redirect to `/reviews?project_id=...` |

## Key Files

- **LiveView**: `lib/spotter_web/live/reviews_live.ex`
- **Channel**: `lib/spotter_web/channels/reviews_channel.ex`
- **Service**: `lib/spotter/services/review_counts.ex`
- **Service**: `lib/spotter/services/review_updates.ex`
- **Controller**: `lib/spotter_web/controllers/reviews_redirect_controller.ex`

## Data Model

`Annotation` with `state` (open/closed), `source` (terminal/transcript/file/commit_message/code/prompt_pattern), `purpose` (review/explain). Has_many `AnnotationMessageRef` and `AnnotationFileRef` for linking to messages and files. Belongs_to `Session`, `Subagent`, `Project`, `Commit`, `CommitHotspot` (all nullable).

## Constraints & Edge Cases

- Annotations can come from multiple sources: text selection in transcripts, file detail, commit review, or MCP tools
- WebSocket channel joins send initial counts; subsequent updates are pushed
- The redirect controller maps legacy `/projects/:id/review` URLs to the new reviews page
- Source badge helps users understand where an annotation originated
