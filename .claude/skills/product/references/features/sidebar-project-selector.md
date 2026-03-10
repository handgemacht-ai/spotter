# Global Project Selector (Sidebar)

## Why This Exists

Every page in Spotter needs project context, but previously each page had its own project filter bar with duplicated selection logic. Users had to re-select their project on every page navigation, and 7 LiveViews contained near-identical project selection code.

## What It Does

A single global project selector in the sidebar that provides project context to all pages. The selected project persists across navigation via URL query params. All per-page project filter bars have been removed.

## User Flow

1. Open any page in Spotter
2. The sidebar shows the current project in a dropdown between the brand section and nav links
3. Click the dropdown to see all available projects
4. Select a different project — the page refreshes with data for that project
5. Navigate to other pages — the project selection is preserved via `?project=<id>` in nav links
6. If no project is specified, the first project is auto-selected

## How It Works

**Architecture: Plug + on_mount + standalone JS hybrid**

- `SpotterWeb.Plugs.ProjectContext` plug runs on every request: loads projects via `Ash.read()`, reads `?project=` (primary) or `?project_id=` (legacy) query params, validates/defaults, assigns `@projects` and `@current_project_id` on conn for root layout rendering
- `SpotterWeb.ProjectContext` on_mount hook fires in LiveView mount: loads projects, resolves `current_project_id` from URL params, makes it available to all LiveViews in the `:project_scoped` live_session
- `project_selector.js` standalone init (not a LiveView hook — root layout is outside LiveView DOM) handles dropdown toggle, project selection with navigation, keyboard/click-outside close
- `SpotterWeb.ProjectHelpers` shared module provides `parse_project_id/1`, `first_project_id/1`, `normalize_project_id/2`, `project_exists?/2` used by both plug and on_mount

**URL `?project=<id>` is the single source of truth.** Sidebar nav links carry this param so navigation preserves context.

## Routes & Endpoints

No dedicated route. The selector appears in the root layout on every page. Routes wrapped in `live_session :project_scoped` receive project context via on_mount.

## Key Files

- **Plug**: `lib/spotter_web/plugs/project_context.ex`
- **On Mount**: `lib/spotter_web/project_context.ex`
- **Helpers**: `lib/spotter_web/project_helpers.ex`
- **Layout**: `lib/spotter_web/components/layouts/root.html.heex`
- **JS**: `assets/js/project_selector.js`
- **CSS**: `priv/static/assets/spotter.css` (project selector styles)
- **Router**: `lib/spotter_web/router.ex` (live_session :project_scoped)

## Data Model

Uses existing `Spotter.Transcripts.Project` resource (id, name, pattern, timezone). No new data model changes.

## Constraints & Edge Cases

- Root layout is outside LiveView's managed DOM — `phx-hook` won't fire there, so project_selector.js uses standalone initialization
- `on_mount` doesn't re-fire on patches — `handle_params` in each LiveView must re-resolve `current_project_id`
- Legacy `?project_id=` param is supported as fallback for backwards compatibility
- Invalid/non-existent project IDs fall back to the first available project
- One project is always selected — no "All Projects" aggregation view
