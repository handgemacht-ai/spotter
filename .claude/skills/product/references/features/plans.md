# Plans

## Why This Exists

Teams track epics and tasks in Dolt-backed beads databases. Spotter provides a read-only view of these plans, letting users browse epics across projects, drill into detail with parsed markdown sections, mermaid diagrams, acceptance criteria, and child tasks.

## What It Does

Two views: a plans list showing epics (grouped by project or filtered to a single project via sidebar), and a plan detail view with full Earmark-rendered markdown content (syntax-highlighted code blocks via PlanContentHook), mermaid diagrams, GIVEN/WHEN/THEN acceptance tables, navigable child tasks, dependencies, text selection for creating annotations, and inline annotation highlights with click-to-scroll and pulse animation. Existing annotations display as annotation cards below the content.

## User Flow

1. Navigate to Plans via sidebar
2. If a project is selected in the sidebar, see that project's epics in a flat table
3. If no project is selected, see epics grouped by project with section headers
4. Click an epic ID to navigate to its detail view
5. Detail view shows: bead header (type chip, ID, title, status/priority badges, assignee), classification chips (type, scope, complexity), Earmark-rendered markdown sections with syntax-highlighted code blocks, mermaid diagrams, acceptance criteria cards (GIVEN/WHEN/THEN), navigable dependency list with blocking indicators, and navigable child tasks
6. Click child task IDs to navigate to their own detail view
7. Existing annotations appear as amber-highlighted text passages inline in rendered content
8. Click an inline highlight to pulse-animate and scroll to center
9. Annotation cards section below content shows all annotations with source badge, comment, and delete button
10. Select text in sections to create review annotations (keyboard Shift+Arrow and mouse selection supported)
11. Click "Back to Plans" to return to the list

## How It Works

The shared ProjectContext on_mount hook provides the selected project from the sidebar. PlansLive resolves the project name from `@current_project_id` (mapping UUID to Ash project name), with a URL param fallback for direct links. When a project is selected, epics are loaded via `Spotter.Plans.list_plans/1`. When no project is selected, all projects are queried in parallel via `Task.async_stream` (max 4 concurrent) and displayed grouped by project.

PlanDetailLive loads any bead (epic, task, bug, chore) and its children, dependencies, and annotations in parallel via `Task.async`. The bead description is parsed into sections, mermaid blocks, and acceptance rows by `BeadContentParser`. Narrative sections are rendered as HTML via Earmark with `code_class_prefix: "language-"`, and PlanContentHook applies hljs syntax highlighting on code blocks client-side.

The `Spotter.Plans` coordinator abstracts over plan sources via the `PlanSource` behaviour. Currently the only source is `BeadsSource`, which delegates to `Spotter.Beads.BeadQueries` for Dolt database access.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/plans` | Plans list (grouped or filtered) |
| GET | `/plans/:project/:bead_id` | Plan detail view (any bead type) |

## Key Files

- **LiveView (list)**: `lib/spotter_web/live/plans_live.ex`
- **LiveView (detail)**: `lib/spotter_web/live/plan_detail_live.ex`
- **Components**: `lib/spotter_web/components/plan_components.ex`
- **Coordinator**: `lib/spotter/plans/plans.ex`
- **Behaviour**: `lib/spotter/plans/plan_source.ex`
- **Beads Source**: `lib/spotter/plans/beads_source.ex`
- **Content Parser**: `lib/spotter/beads/bead_content_parser.ex`
- **JS Hooks**: `assets/js/hooks/mermaid_hook.js`, `assets/js/hooks/plan_content_hook.js`

## Data Model

Epics and tasks are read from Dolt beads databases (one per project, named `beads_<project>`). Structs: `BeadStructs.Epic` (id, title, status, priority, issue_type, assignee, description, created_at), `BeadStructs.Task` (id, title, status, priority, description, parent_id), `BeadStructs.Dependency` (depends_on_id, type, depends_on_title, depends_on_status). Classification and acceptance criteria are extracted from bead descriptions by `BeadContentParser`. Annotations created from text selection are stored as `Spotter.Transcripts.Annotation` resources in SQLite.

## Constraints & Edge Cases

- Project selection uses the global sidebar ProjectContext — no per-page project chips
- URL param `?project=<name>` fallback supports direct links when sidebar hasn't resolved a project
- All Dolt queries use a 2-second timeout with graceful fallback to empty results
- Grouped view queries projects in parallel (max 4 concurrent) to avoid N+1 sequential loading
- Empty projects (no epics) are excluded from the grouped view
- Mermaid diagrams are lazy-loaded via MermaidHook (not bundled)
- Text selection annotations require the PlanContentHook JS hook
- Code blocks in bead descriptions get syntax highlighting via hljs (elixir, javascript, bash, json, diff, plaintext)
- Mermaid SVG text selections are excluded from annotation creation
- Inline annotation highlights use fuzzy whitespace-normalized matching (TreeWalker) — text spanning multiple DOM elements is not highlighted but still shows in annotation cards
- Annotation highlight reruns are cached to avoid unnecessary DOM churn on unrelated LiveView patches
- Annotations are passed to the JS hook via `data-annotations` JSON attribute (omitted when empty)
