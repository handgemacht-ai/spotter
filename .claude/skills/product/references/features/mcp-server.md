# MCP Server (Claude Code Integration)

## Why This Exists

Claude Code agents need programmatic access to Spotter for two workflows: (1) reviewing and resolving annotations during coding sessions, and (2) submitting retrospectives and code hotspots after analysis. The MCP protocol enables this integration natively within Claude Code.

## What It Does

An MCP server exposing 4 tools to Claude Code agents: list review annotations, resolve annotations, create code hotspots, and submit retrospectives. All tools are project-scoped via header, session context, or fallback detection.

## User Flow (from agent perspective)

1. Claude Code agent calls `mcp__spotter__list_review_annotations` to see open annotations
2. Agent reviews code and resolves annotations via `mcp__spotter__resolve_annotation`
3. During analysis, agent creates hotspots via `mcp__spotter__create_hotspot`
4. At session end, agent submits retro via `mcp__spotter__submit_retro`

## How It Works

`SpotterMcpPlug` implements the MCP protocol using AshAi's MCP router. It mounts at `/api/mcp` and handles both GET (tool discovery) and POST (tool execution) requests. Project scoping uses a priority chain: (1) `x-spotter-project-dir` header, (2) `session_id` query param from CLAUDE_ENV_FILE, (3) most recent session's project as fallback. The `spotter_mcp_scope` context is injected into Ash action context for all MCP operations.

### Available Tools

| Tool | Action | Purpose |
|------|--------|---------|
| `list_review_annotations` | `Annotation.mcp_read_review_annotations` | List annotations filtered by project, state, session |
| `resolve_annotation` | `Annotation.mcp_resolve` | Resolve/reopen annotation with resolution text |
| `create_hotspot` | `CommitHotspot.mcp_create` | Create code hotspot for a commit |
| `submit_retro` | `RetroSubmission.mcp_submit` | Submit retrospective with items array |

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/mcp` | MCP tool discovery |
| POST | `/api/mcp` | MCP tool execution |

## Key Files

- **Plug**: `lib/spotter_web/plugs/spotter_mcp_plug.ex`
- **Domain tools**: `lib/spotter/transcripts.ex` (tool declarations)
- **Plugin config**: `spotter-plugin/.mcp.json`

## Data Model

Tools operate on: `Annotation` (list/resolve), `CommitHotspot` (create), `RetroSubmission` + `RetroItem` (submit). All scoped by `Project` via MCP context.

## Constraints & Edge Cases

- MCP server URL: `${SPOTTER_URL:-http://127.0.0.1:1100}/api/mcp`
- Project scoping fallback chain means tools work even without explicit project context
- Full OpenTelemetry tracing wraps all MCP requests
- Only 4 tools are exposed (reduced from a larger set to minimize agent tool clutter)
