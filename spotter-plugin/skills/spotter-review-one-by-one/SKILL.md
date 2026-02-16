---
name: spotter-review-one-by-one
description: "Resolve Spotter review annotations one at a time (tight loop)."
---

# Spotter Review: One-by-One

Resolve review annotations individually in a tight loop. Best for annotations that require focused attention and distinct code changes.

## Prerequisites

Complete steps 1-3 from the `spotter-review` skill to obtain the list of open annotations.

## Iteration Loop

Repeat for each annotation, starting with the oldest:

### Checklist per annotation

1. **Read** the annotation's `comment`, `selected_text`, `relative_path` (from `file_refs`), and `line_start`/`line_end`.
2. **Understand** the context by reading the referenced file and surrounding code.
3. **Plan** the change needed to address the annotation.
4. **Implement** the code, process, or documentation change.
5. **Verify** the change compiles and tests pass (if applicable).
6. **Resolve** the annotation by calling `mcp__spotter__resolve_annotation`. The `resolution` field is a **required, non-empty resolution note** (1-3 sentences) that will be visible under "Resolved annotations" in the Spotter web UI. Blank or whitespace-only values are rejected.
   ```json
   {
     "id": "<annotation_id>",
     "input": {
       "resolution": "Short description of what was done (1-3 sentences).",
       "resolution_kind": "code_change"
     }
   }
   ```
7. **Move on** to the next open annotation.

## Ordering

- Process annotations from oldest to newest (`inserted_at` ascending).
- If annotations reference the same file, process them bottom-to-top to avoid line number drift from earlier edits.

## When to stop

- All open review annotations are resolved.
- Or you encounter a blocker that requires human input - leave remaining annotations open and report what's blocking.
