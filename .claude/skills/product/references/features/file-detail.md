# File Detail & Browser

## Why This Exists

When reviewing code changes, users need to see files in their full project context — with git blame attribution, the ability to annotate specific lines, and links to related sessions and commits.

## What It Does

A file browser and viewer with blame/raw view modes, text selection for annotation capture, directory navigation with breadcrumbs, and a sidebar with annotations, sessions, and commits tabs. Supports hotspot highlighting via query params.

## User Flow

1. Navigate from commit detail, file metrics, or direct URL
2. If a directory, browse files/folders with parent breadcrumb navigation
3. If a file, view content in blame or raw mode
4. Select lines of text to create an annotation (review or explain)
5. Switch sidebar tabs to see related annotations, sessions, or commits
6. Click a hotspot or annotation to highlight the relevant lines

## How It Works

`FileDetailLive` uses `FileDetailComputers` (AshComputer) for reactive data. The `FileDetail` service reads file content at the analyzed commit (git-backed, not working tree). `FileBlame` provides line-by-line blame attribution. Text selection triggers a JS hook that captures line range + selected text and pushes to the LiveView. The sidebar loads annotations scoped to the file path, sessions that touched the file, and commits that changed it. Query params (`highlight_hotspot_id`, `highlight_annotation_id`) trigger line highlighting.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/projects/:project_id/files/*relative_path` | File detail/browser LiveView |

## Key Files

- **LiveView**: `lib/spotter_web/live/file_detail_live.ex`
- **Computers**: `lib/spotter_web/live/file_detail_computers.ex`
- **Service**: `lib/spotter/services/file_detail.ex`
- **Service**: `lib/spotter/services/file_blame.ex`
- **Service**: `lib/spotter/services/file_metrics.ex`

## Data Model

File content is read from git (not Ash resources). Annotations are scoped by `relative_path` + `project_id`. `AnnotationFileRef` links annotations to specific files with line ranges. `FileSnapshot` tracks file states captured by hooks.

## Constraints & Edge Cases

- File content is always read at the analyzed commit, not from the working tree
- Directory entries show files and subdirectories with navigation
- Blame mode shows commit hash + author per line
- Hotspot highlighting scrolls to and highlights the specified line range
- Annotations require a project context (project_id in URL)
