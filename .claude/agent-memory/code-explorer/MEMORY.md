# Code Explorer Memory for spotter-cli worktree

## Epic: Plans/Beads Detail View Rework (spotter-cp6)

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

## Epic: Product Feedback Annotations with Image Support (spotter-3t2)

**Summary**: Extend annotation system for visual product feedback with images.

### Annotation System Touch Points
- `annotation.ex` source enum (line 166): add `:product_feedback`
- `annotation.ex` validation (line 144): exempt `product_feedback` from `session_id` requirement
- `annotation.ex` create action (line 48): accept image-related fields
- `AnnotationFileRef` — pattern for join resources (separate Ash resource with belongs_to)
- `ApplyResolution` change — shared metadata merge logic

### MCP Touch Points
- `transcripts.ex` tools block (line 83): add image-aware annotation tools
- `spotter_mcp_plug.ex` tools list (line 24): register new tools
- MCP scope resolution: 3-tier (header → session_id param → recent session fallback)

### Controller Patterns
- All controllers: `use Phoenix.Controller, formats: [:json]`
- OTEL: `OtelTraceHelpers.with_span` + `put_trace_response_header`
- API routes: `scope "/api", SpotterWeb` with `:api` pipeline

### Reviews Dashboard Touch Points
- `reviews_live.ex` source_badge/1 (line 222): add `product_feedback` case
- `reviews_live.ex` source_badge_class/1 (line 228): add CSS class
- `reviews_live.ex` annotation_card (line 247): add image display
- `annotation_components.ex` source_badge_text/1: add `product_feedback` case
- `project_review_live.ex`: similar badge functions need update

### DI Pattern (from plan_source.ex)
- Behaviour file with `@callback` + type specs
- Config: `config :spotter, Module, key: [Impl]`
- Used by Plans layer, reuse for ImageStore

### No Existing Image Infrastructure
- Greenfield — no image modules exist yet

## Epic: Lossless Transcript Analytics (spotter-phd)

### Transcript Pipeline Key Facts
- Latest migration: `20260313133419_add_bead_id_to_annotations.exs`
- Message identity: `[:session_id, :uuid]`
- Two divergent sync paths: public `sync_session_file/2` (upserts) vs private 4-arity (skips if messages exist)
- Messages without timestamps silently dropped during sync
- ToolCall resource is minimal: no duration, no input params, no file_path
- SessionLive has NO `handle_params` — only mount. Not inside project_scoped live_session.
- TranscriptComputers `messages` input is the natural filter point for slicing
- Mix task patterns: `spotter.e2e.seed` has rich OptionParser example
