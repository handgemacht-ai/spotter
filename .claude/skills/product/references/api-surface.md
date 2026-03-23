# API Surface

## Hook Endpoints (Plugin -> Spotter)

| Method | Path | Purpose | Controller |
|--------|------|---------|------------|
| POST | `/api/hooks/session-start` | Session lifecycle start | SessionHookController |
| POST | `/api/hooks/session-end` | Session lifecycle end | SessionHookController |
| POST | `/api/hooks/waiting-summary` | Status polling fallback | SessionHookController |
| POST | `/api/hooks/file-snapshot` | File state capture (before/after) | HooksController |
| POST | `/api/hooks/tool-call` | Tool invocation capture | HooksController |
| POST | `/api/hooks/commit-event` | Commit hash capture | HooksController |
| POST | `/api/hooks/raw-event` | Raw event storage + extraction | HooksController |

## API Endpoints

| Method | Path | Purpose | Controller |
|--------|------|---------|------------|
| GET | `/api/search` | Full-text search (FTS5) | SearchController |
| POST | `/api/annotations` | Create annotation (external) | AnnotationController |
| POST | `/api/annotations/:id/image` | Attach image to annotation | AnnotationController |
| POST/GET | `/api/mcp` | MCP server (5 tools) | SpotterMcpPlug |

## LiveView Pages

| Method | Path | Purpose | LiveView |
|--------|------|---------|----------|
| GET | `/` | Dashboard (ongoing sessions) | DashboardLive |
| GET | `/sessions` | Session list with import | SessionsLive |
| GET | `/sessions/:session_id` | Session detail + transcript | SessionLive |
| GET | `/sessions/:session_id/agents/:agent_id` | Subagent detail | SubagentLive |
| GET | `/history` | Commit history timeline | HistoryLive |
| GET | `/history/commits/:commit_id` | Commit detail + diff | CommitDetailLive |
| GET | `/reviews` | Annotation management | ReviewsLive |
| GET | `/retros` | Agent retrospectives | RetrosLive |
| GET | `/file-metrics` | File metrics (4 tabs) | FileMetricsLive |
| GET | `/telemetry/commands` | Shell command telemetry | ShellTelemetryLive |
| GET | `/telemetry/instructions` | Instructions telemetry | InstructionsTelemetryLive |

## Project-Scoped Routes

| Method | Path | Purpose | LiveView |
|--------|------|---------|----------|
| GET | `/projects/:project_id/review` | Redirect to `/reviews?project_id=...` | ReviewsRedirectController |
| GET | `/projects/:project_id/file-metrics` | Project file metrics | FileMetricsLive |
| GET | `/projects/:project_id/telemetry/commands` | Project shell telemetry | ShellTelemetryLive |
| GET | `/projects/:project_id/telemetry/instructions` | Project instructions telemetry | InstructionsTelemetryLive |
| GET | `/projects/:project_id/files/*relative_path` | File detail / browser | FileDetailLive |

## MCP Tools (via SpotterMcpPlug)

| Tool | Purpose | Handler |
|------|---------|---------|
| `list_review_annotations` | List annotations for scoped project (includes `has_image` flag) | AshAi |
| `resolve_annotation` | Resolve an annotation with resolution note | AshAi |
| `create_hotspot` | Create a code hotspot for a commit | AshAi |
| `submit_retro` | Submit a session retrospective | AshAi |
| `get_annotation_image` | Retrieve base64 PNG screenshot attached to annotation | Custom handler |

`get_annotation_image` is a custom MCP tool (not routed through AshAi) because AshAi doesn't support MCP image content types. It returns `{"type": "image", "mimeType": "image/png", "data": "<base64>"}`. Project scope validation ensures annotations from other projects are rejected.

## WebSocket

| Topic | Purpose | Module |
|-------|---------|--------|
| `reviews:counts` | Live annotation count updates | ReviewsChannel |

## Authentication

None. Localhost prototype — all endpoints are unauthenticated.
