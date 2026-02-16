---
name: spotter-review
description: "Execute a Spotter review by resolving open review annotations via MCP tools."
---

# Spotter Review

Execute a code review by resolving open review annotations using Spotter MCP tools. Do not use the web UI or tmux launch flow.

## Workflow

### 1. List sessions for the current project

The MCP server automatically scopes all requests to the current project via the `x-spotter-project-dir` header. No need to select a project.

Call `mcp__spotter__list_sessions` to find sessions:

```json
{
  "limit": 50
}
```

Collect the `id` values from the returned sessions.

### 2. List open review annotations

Call `mcp__spotter__list_review_annotations` with:

```json
{
  "filter": {
    "state": { "eq": "open" },
    "session_id": { "in": ["<session_id_1>", "<session_id_2>"] }
  },
  "limit": 100
}
```

This tool is review-only: it never returns `purpose=explain` annotations, so no `purpose` filter is needed. Results include `state`, `purpose`, `source`, `selected_text`, `comment`, `inserted_at`, and loaded `subagent`, `file_refs`, and `message_refs` (with full message content).

### 3. Resolve each annotation

For each annotation, make the necessary code or process changes, then call `mcp__spotter__resolve_annotation`.

The `resolution` field is a **required, non-empty resolution note** (1-3 sentences) describing what was done. This note will be visible under "Resolved annotations" in the Spotter web UI. Blank or whitespace-only values are rejected.

```json
{
  "id": "<annotation_id>",
  "input": {
    "resolution": "Applied the suggested fix by refactoring the validation logic.",
    "resolution_kind": "code_change"
  }
}
```

Valid `resolution_kind` values:
- `code_change` - Changed source code
- `process_change` - Changed a workflow or process
- `tooling_change` - Changed tooling configuration
- `doc_change` - Updated documentation
- `wont_fix` - Intentionally not addressing (explain why in `resolution`)
