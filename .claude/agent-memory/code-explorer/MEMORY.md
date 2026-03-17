# Code Explorer Memory for spotter-cp6

## Epic: Plans/Beads Detail View Rework

**Summary**: Rework plan detail view with full markdown rendering, inline annotations, dependency display, and any-bead navigation.

**Child beads**: spotter-bl3 (Earmark), spotter-2sc (deps + aliases), spotter-de2 (route rename + any-bead LiveView), spotter-c6j (Markdown rendering + PlanContentHook), spotter-055 (Acceptance cards + chips + deps components), spotter-00o (Inline annotations), spotter-7q0 (E2E tests).

## Key Paths

### Beads Layer (`lib/spotter/beads/`)
- `dolt_config.ex` — Connection config. Port 3307, root user, no password. `database_name/1` returns project name as-is.
- `client.ex` — MyXQL pool manager. `get_issue/2`, `list_epics/2`, `get_children/2`, `get_dependencies/2`, `epic_counts_by_project/0`. Discovery SQL filters system schemas. Lazy pool per project.
- `bead_queries.ex` — High-level API: `project_summaries/0`, `list_epics/2`, `get_epic/2`, `list_children/2`. All OTEL-traced. **No `get_dependencies` wrapper yet.**
- `bead_structs.ex` — Epic, Task, Dependency structs with `from_row/1` and `from_rows/1`.
- `bead_content_parser.ex` — Parses markdown: `extract_sections_ordered/1`, `extract_mermaid_blocks/1`, `extract_acceptance_table/1`, `extract_headings/1`.

### Plans Layer (`lib/spotter/plans/`)
- `plan_source.ex` — Behaviour: `list_projects/0`, `list_plans/2`, `get_plan/2`, `list_children/2`. Types alias BeadStructs.
- `beads_source.ex` — PlanSource impl, pure delegation to BeadQueries.
- `plans.ex` — Public coordinator. `list_projects/0` merges flat_map; others use first-success fallthrough. Config: `config :spotter, Spotter.Plans, sources: [...]`.

### Web Layer
- `plans_live.ex` — List view. Uses sidebar ProjectContext. Grouped or filtered view. `safe_query/2` with Task.async + 2s timeout.
- `plan_detail_live.ex` — Detail view. Params: `project`, `epic_id`. Uses BeadContentParser. PlanHighlighter hook. `safe_query/2` pattern. Test data override via app env.
- `plan_components.ex` — `status_badge`, `priority_badge`, `epic_table`, `epic_table_row`, `acceptance_table`, `task_row`.
- `project_context.ex` — on_mount hook for project context.

### Routes
- `/plans` → PlansLive
- `/plans/:project/:epic_id` → PlanDetailLive

### Annotations
- `annotation.ex` — Ash resource. Source `:plan` requires `bead_id`. States: open/closed. Purpose: review/explain.

### JS Hooks
- `assets/js/hooks/plan_highlighter.js` — Text selection → `plan_text_selected` event.
- `assets/js/hooks/mermaid_hook.js` — Lazy-loads mermaid.js, renders SVG.

### E2E
- `e2e/tests/plans.smoke.spec.ts`, `e2e/tests/plan-detail.smoke.spec.ts`
- `e2e/support/pages/plans.ts`, `e2e/support/pages/plan-detail.ts`

## Gaps for This Epic
- **No `get_dependencies` in BeadQueries** — Client has it but no wrapper (spotter-2sc)
- **No `get_dependencies` in PlanSource behaviour** — Needs new callback (spotter-2sc)
- **Plain text rendering** — Sections body rendered as `<p>` per line, no Earmark (spotter-bl3, spotter-c6j)
- **No any-bead navigation** — Routes only support epics (spotter-de2)
- **No dependency display** — Not shown in detail view (spotter-055)
- **No inline annotation display** — Created but not rendered (spotter-00o)
