# Code Explorer Memory for spotter-gdz

## Epic: Generic Plan Sources with Dolt Fix

**Summary**: Fix Dolt config bugs, introduce PlanSource behaviour abstraction, wrap BeadQueries in BeadsSource, create Plans coordinator, migrate PlansLive to global sidebar selector.

**Key Paths**:
- `lib/spotter/beads/dolt_config.ex` — Dolt connection config (buggy defaults)
- `lib/spotter/beads/client.ex` — MyXQL pool manager, discovery SQL (buggy discovery)
- `lib/spotter/beads/bead_queries.ex` — High-level query API wrapping Client
- `lib/spotter/beads/bead_structs.ex` — Epic, Task, Dependency structs
- `lib/spotter/plans/` — **NEW** (doesn't exist yet)
- `lib/spotter_web/live/plans_live.ex` — Plan list view (tightly coupled to BeadQueries)
- `lib/spotter_web/live/plan_detail_live.ex` — Plan detail view with annotations
- `lib/spotter_web/components/plan_components.ex` — Plan UI components
- `lib/spotter_web/project_context.ex` — on_mount hook for project context
- `config/runtime.exs` — Runtime env var configuration

## Codebase State

### lib/spotter/beads/dolt_config.ex
- **Line 10**: `@default_port 14_065` — WRONG, should be 3307 (shared workspace Dolt, not bd CLI default)
- **Line 28**: `database: database_name(project_name)`
- **Line 36-38**: `database_name/1` returns `"beads_#{project_name}"` — WRONG, most databases on port 3307 don't use "beads_" prefix

### lib/spotter/beads/client.ex
- **Line 253**: Discovery SQL `WHERE SCHEMA_NAME LIKE 'beads_%'` — WRONG, filters out non-prefixed databases like aufgabenschmiede, le
- **Line 268**: `String.replace_prefix(db_name, "beads_", "")` — Assumes beads_ prefix exists

### lib/spotter_web/live/plans_live.ex
- **Lines 5-7**: Direct `BeadQueries` import + hard coupling
- **Lines 40-48**: Own project selector event handling (`select_project`)
- **Line 51**: Directly calls `BeadQueries.project_summaries()`
- Missing integration with global sidebar project selector (`ProjectContext`)

### config/runtime.exs
- **Lines 25-29**: DoltConfig uses `SPOTTER_DOLT_*` env vars and port 13307 (Spotter internal)
- **Lines 32-38**: ProductSpec.Repo (different Dolt server, MUST NOT CHANGE)
- Need separate `BEADS_DOLT_*` env vars for port 3307

## Ready Tasks

### spotter-gdz.1 (Priority 1 — bugfix)
"Fix DoltConfig port and database discovery"
- Fix runtime.exs: add BEADS_DOLT_* env vars
- Fix DoltConfig defaults: port→3307, username→"root", password→""
- Fix DoltConfig.database_name: drop "beads_" prefix
- Fix Client discovery SQL: change LIKE to filter system schemas
- Fix Client.aggregate_epic_counts: use db_name as-is

### spotter-gdz.2 (Priority 1 — feature)
"Introduce PlanSource behaviour"
- Create lib/spotter/plans/plan_source.ex (behaviour module)
- Minimal callbacks: list_projects, list_plans, get_plan, list_children

## Architecture Patterns

- **Configuration**: Application.get_env for app config + defaults
- **OTEL Tracing**: Tracer.with_span, set_attribute, set_status
- **Error Handling**: {:ok, val} | {:error, reason}
- **Struct Mapping**: rows_to_maps helper for MyXQL.Result
- **Pool Management**: Lazy-started per-project pools with prefix __MODULE__.Pool
