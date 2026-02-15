---
name: spotter-review-process-improvements
description: "Turn review annotations into concrete improvements: commands, skills, hooks, or CLAUDE.md rules."
---

# Spotter Review: Process Improvements

When review annotations suggest systemic improvements (not just one-off code fixes), use this skill to turn them into durable project improvements.

## Prerequisites

Complete steps 1-3 from the `spotter-review` skill to obtain open annotations. Filter for annotations where the `comment` suggests a recurring pattern, missing automation, or architectural constraint.

## Workflow

For each improvement annotation:

1. **Classify** the improvement using the rubric below.
2. **Implement** the improvement in the appropriate location.
3. **Resolve** the annotation with `resolution_kind` set to the matching kind:
   - Command/script -> `tooling_change`
   - Skill -> `process_change`
   - Hook -> `tooling_change`
   - CLAUDE.md rule -> `doc_change`

### Rubric: Command vs Skill vs Hook vs CLAUDE.md Rule

- **Command**: deterministic, repeatable automation (scripts or mix tasks). Good for repo-local operations that should behave the same every time.
  - Put scripts in `scripts/` or add a `mix` task under `lib/mix/tasks/`.
- **Skill**: prompt template + workflow guidance. Good for reasoning-heavy, context-dependent work where Claude must choose actions.
  - Put repo skills in `.claude/skills/<name>/SKILL.md` or plugin skills in `spotter-plugin/skills/<name>/SKILL.md`.
- **Hook**: automatic behavior triggered by Claude Code lifecycle/tool events. Must be fail-safe, silent-fail preferred, and must not block Claude.
  - Configure in `spotter-plugin/hooks/hooks.json` and implement scripts in `spotter-plugin/scripts/`.
- **CLAUDE.md rule**: stable project-wide constraints, quality gates, and architectural invariants.
  - Update `CLAUDE.md`.

## Examples

| Annotation comment | Classification | Action |
|---|---|---|
| "Always run credo before committing" | Hook | Add pre-commit hook |
| "Use Ash.Changeset pattern for updates" | CLAUDE.md rule | Add to CLAUDE.md |
| "Generate migration after schema change" | Command | Add script |
| "Review annotations should follow this workflow" | Skill | Create new skill |

## Resolution

After implementing each improvement:

```json
{
  "id": "<annotation_id>",
  "input": {
    "resolution": "Created pre-commit hook in spotter-plugin/hooks/hooks.json to run credo automatically.",
    "resolution_kind": "tooling_change"
  }
}
```
