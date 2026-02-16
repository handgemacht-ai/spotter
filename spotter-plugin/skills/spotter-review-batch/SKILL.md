---
name: spotter-review-batch
description: "Resolve Spotter review annotations in batches grouped by file/topic."
---

# Spotter Review: Batch

Resolve review annotations in batches, grouped by file or topic. Best when many annotations share the same file or concern, allowing related changes to be made together.

## Prerequisites

Complete steps 1-3 from the `spotter-review` skill to obtain the list of open annotations.

## Grouping

Group annotations by:

1. **File** (`relative_path` from `file_refs`). Annotations referencing the same file should be addressed together.
2. **Topic** - infer topic from the annotation `comment` text. Common groupings: naming, error handling, testing, documentation, security, performance.

Annotations without `file_refs` form their own group.

## Batch workflow

For each group:

1. **Plan** all changes for the group before modifying any code.
2. **Implement** all changes for the group at once.
3. **Verify** the changes compile and tests pass.
4. **Resolve** each annotation in the group individually. Resolution must happen per-annotation since `mcp__spotter__resolve_annotation` operates on a single annotation `id`. The `resolution` field is a **required, non-empty resolution note** (1-3 sentences) that will be visible under "Resolved annotations" in the Spotter web UI. Blank or whitespace-only values are rejected.
   ```json
   {
     "id": "<annotation_id>",
     "input": {
       "resolution": "Addressed as part of batch refactor of validation module.",
       "resolution_kind": "code_change"
     }
   }
   ```
5. **Move on** to the next group.

## Ordering

- Process groups by file path alphabetically.
- Within a group, resolve annotations bottom-to-top by line number to avoid drift.

## Important

- Each annotation still requires its own `mcp__spotter__resolve_annotation` call - there is no batch resolve API.
- Use a shared resolution prefix for batch-resolved annotations so they can be identified as related (e.g., "Batch: refactored error handling in auth module").
