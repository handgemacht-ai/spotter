# Dashboard (Ongoing Sessions + Skill Folder Cards)

## Why This Exists

Users need an at-a-glance view of what Claude Code sessions are currently running across all projects, plus quick access to skill/memory folders without navigating the repo tree.

## What It Does

Shows two sections:
1. **Skill folder cards** — quick-link cards for detected `.claude/` skill and memory folders (Agent Memory, Product Skill, Design Skill, Claude Rules), linking directly to the inline folder viewer
2. **Ongoing sessions** — currently active sessions as rows with live start/finish updates

## User Flow

1. Open Spotter (root URL `/`)
2. If the current project has `.claude/` skill/memory folders, see cards above the sessions table
3. Each card shows icon, label, path, file count — click to navigate to `/projects/:id/folders/:path`
4. See rows for each ongoing session showing session ID, project (cwd), status badge, start time
5. Rows appear in real-time as new sessions start
6. Rows are marked "finished" when sessions end
7. Click "Review" on any row to navigate to the session detail transcript

## How It Works

On `handle_params`, `DashboardLive` resolves the current project via `ProjectHelpers.load_and_resolve/1` (reading `?project=` query param) and detects skill folders via `SkillFolderReader.detect_folders/1`. Skill folder detection is deferred to connected mount only (skips git + filesystem I/O on static render). Cards are rendered using `FolderComponents.folder_card/1`.

`SessionActivityBroadcaster` emits PubSub events on the `session_activity` topic when sessions start or end. `DashboardLive` subscribes on mount and handles `session_started` and `session_finished` events to add/remove rows from its `sessions` assign.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | Dashboard LiveView |

## Key Files

- **LiveView**: `lib/spotter_web/live/dashboard_live.ex`
- **Component**: `lib/spotter_web/components/folder_components.ex` (folder_card/1)
- **Service**: `lib/spotter/services/skill_folder_reader.ex` (detect_folders/1)
- **Service**: `lib/spotter/services/session_activity_broadcaster.ex`

## Data Model

Reads `Session` resources filtered to those without `session_ended_at`. Uses `SkillFolderReader` to detect known `.claude/` folders from the project's repo root (resolved via session cwd + git).

## Constraints & Edge Cases

- Only shows sessions where `session_ended_at` is nil (truly ongoing)
- PubSub-driven: if a session start event is missed, a refresh button reloads the full list
- No pagination needed — ongoing session count is typically small
- Skill folder cards only appear when project has `.claude/` directories with known folder types
- No cards when no project is selected or project has no repo root
- Project switching via sidebar updates cards via `handle_params`
