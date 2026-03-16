# Plans

## Why This Exists

Teams track epics and tasks in Dolt-backed beads databases. Spotter provides a read-only view of these plans, letting users browse epics across projects, drill into detail with parsed markdown sections, mermaid diagrams, acceptance criteria, and child tasks.

## What It Does

Two views: a plans list showing epics (grouped by project or filtered to a single project via sidebar), and a plan detail view with parsed markdown content, mermaid diagrams, GIVEN/WHEN/THEN acceptance tables, expandable child tasks, and text selection for annotations.

## User Flow

1. Navigate to Plans via sidebar
2. If a project is selected in the sidebar, see that project's epics in a flat table
3. If no project is selected, see epics grouped by project with section headers
4. Click an epic ID to navigate to its detail view
5. Detail view shows: title, status/priority badges, parsed markdown sections, mermaid diagrams, acceptance criteria table, and child tasks
6. Expand/collapse child tasks to see descriptions
7. Select text in sections to create review annotations
8. Click "Back to Plans" to return to the list

## How It Works

The shared ProjectContext on_mount hook provides the selected project from the sidebar. PlansLive resolves the project name from `@current_project_id` (mapping UUID to Ash project name), with a URL param fallback for direct links. When a project is selected, epics are loaded via `Spotter.Plans.list_plans/1`. When no project is selected, all projects are queried in parallel via `Task.async_stream` (max 4 concurrent) and displayed grouped by project.

PlanDetailLive loads a single epic and its children via `Spotter.Plans.get_plan/2` and `Plans.list_children/2`. The epic description is parsed into sections, mermaid blocks, and acceptance rows by `BeadContentParser`.

The `Spotter.Plans` coordinator abstracts over plan sources via the `PlanSource` behaviour. Currently the only source is `BeadsSource`, which delegates to `Spotter.Beads.BeadQueries` for Dolt database access.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/plans` | Plans list (grouped or filtered) |
| GET | `/plans/:project/:epic_id` | Plan detail view |

## Key Files

- **LiveView (list)**: `lib/spotter_web/live/plans_live.ex`
- **LiveView (detail)**: `lib/spotter_web/live/plan_detail_live.ex`
- **Components**: `lib/spotter_web/components/plan_components.ex`
- **Coordinator**: `lib/spotter/plans/plans.ex`
- **Behaviour**: `lib/spotter/plans/plan_source.ex`
- **Beads Source**: `lib/spotter/plans/beads_source.ex`
- **Content Parser**: `lib/spotter/beads/bead_content_parser.ex`
- **JS Hooks**: `assets/js/hooks/mermaid_hook.js`, `assets/js/hooks/plan_highlighter.js`

## Data Model

Epics and tasks are read from Dolt beads databases (one per project, named `beads_<project>`). Structs: `BeadStructs.Epic` (id, title, status, priority, description, created_at), `BeadStructs.Task` (id, title, status, priority, description, parent_id). Annotations created from text selection are stored as `Spotter.Transcripts.Annotation` resources in SQLite.

## Constraints & Edge Cases

- Project selection uses the global sidebar ProjectContext — no per-page project chips
- URL param `?project=<name>` fallback supports direct links when sidebar hasn't resolved a project
- All Dolt queries use a 2-second timeout with graceful fallback to empty results
- Grouped view queries projects in parallel (max 4 concurrent) to avoid N+1 sequential loading
- Empty projects (no epics) are excluded from the grouped view
- Mermaid diagrams are lazy-loaded via MermaidHook (not bundled)
- Text selection annotations require the PlanHighlighter JS hook
