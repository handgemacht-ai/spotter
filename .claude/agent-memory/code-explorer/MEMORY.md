# Code Explorer Memory for spotter-cp6

## Epic: Plans/Beads Detail View Rework

**Summary**: Rework plan detail view with full markdown rendering, inline annotations, dependency display, and any-bead navigation.

**Child beads**: spotter-bl3 (Earmark), spotter-2sc (deps + aliases), spotter-de2 (route rename + any-bead LiveView), spotter-c6j (Markdown rendering + PlanContentHook), spotter-055 (Acceptance cards + chips + deps components), spotter-00o (Inline annotations), spotter-7q0 (E2E tests).

## Key Paths (Post-Rebase State)

### Beads Layer (`lib/spotter/beads/`)
- `dolt_config.ex` — Port 3307, root, no password. `database_name/1` returns project name as-is.
- `client.ex` — MyXQL pool manager. `get_issue/2`, `list_epics/2`, `get_children/2`, `get_dependencies/2`, `epic_counts_by_project/0`.
- `bead_queries.ex` — `project_summaries/0`, `list_epics/2`, `get_epic/2`, `list_children/2`, `list_dependencies/2` (NEW), `get_bead/2` (NEW, delegates to get_epic).
- `bead_structs.ex` — Epic, Task, Dependency structs.
- `bead_content_parser.ex` — `extract_sections_ordered/1`, `extract_mermaid_blocks/1`, `extract_acceptance_table/1`, `render_section_body/1` (NEW, Earmark HTML), `classify_section/1` (NEW), `extract_classification/1` (NEW), `sanitize_html/1`.

### Plans Layer (`lib/spotter/plans/`)
- `plan_source.ex` — Behaviour: `list_projects/0`, `list_plans/2`, `get_plan/2`, `list_children/2`, `list_dependencies/2` (NEW). Types: plan, task, dependency (NEW).
- `beads_source.ex` — Delegates all callbacks including `list_dependencies/2` (NEW).
- `plans.ex` — `list_dependencies/2` (NEW), `get_bead/2` (NEW, delegates to get_plan). OTEL traced.

### Web Layer
- `plan_detail_live.ex` — **MAJOR REWORK**: Now uses `bead` (not `epic`). Params: `project`, `bead_id` (was `epic_id`). Fetches bead + children + deps + annotations in parallel via Task.async. `parse_bead_content/1` uses `classify_section`, `render_section_body`, `extract_classification`. Renders deps section with navigable links. Renders annotation list. `safe_call/2` (simplified, no Task wrapping). `@query_timeout` now 5s.
- `plan_components.ex` — `task_row` now navigable link to `/plans/:project/:task_id` (any-bead). Removed expand/collapse toggle. Added `project` attr.
- `plans_live.ex` — Unchanged.
- Route: `/plans/:project/:bead_id` (was `:epic_id`).

### Annotations
- `annotation.ex` — NEW action `list_for_bead` (read): filters by `source == :plan`, `state == :open`, matching `bead_id`.

### JS Hooks — Unchanged.

### E2E — `plans.smoke.spec.ts`, `plan-detail.smoke.spec.ts`, POMs in `e2e/support/pages/`.
