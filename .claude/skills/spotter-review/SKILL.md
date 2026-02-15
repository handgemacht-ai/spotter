---
name: spotter-review
description: "Execute a Spotter review by resolving open review annotations via MCP tools."
---

# Spotter Review

Execute a code review by resolving open review annotations using Spotter MCP tools. Do not use the web UI or tmux launch flow.

## Workflow

### 1. Determine project_id

Call `mcp__spotter__list_projects` and pick the relevant project:

```json
{
  "filter": {},
  "limit": 25
}
```

Note the `id` of the target project.

### 2. Determine review scope

Call `mcp__spotter__list_sessions` to find sessions for the project:

```json
{
  "filter": {
    "project_id": { "eq": "<project_id>" }
  },
  "limit": 50
}
```

Collect the `id` values from the returned sessions.

### 3. List open review annotations

Call `mcp__spotter__list_review_annotations` with:

```json
{
  "filter": {
    "state": { "eq": "open" },
    "purpose": { "eq": "review" },
    "session_id": { "in": ["<session_id_1>", "<session_id_2>"] }
  },
  "limit": 100
}
```

This returns annotations with loaded `subagent`, `file_refs`, and `message_refs` (including messages).

### 4. Resolve each annotation

For each annotation, make the necessary code or process changes, then call `mcp__spotter__resolve_annotation`:

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
