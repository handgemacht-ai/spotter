# Transcript Import

## Why This Exists

Sessions started before Spotter was running, or sessions from other machines, need to be imported manually. Historical backfill and recovery requires scanning the filesystem for JSONL transcript files.

## What It Does

A modal (embedded in the Sessions page) that discovers JSONL transcript files from `~/.claude/projects`, shows them in a filterable/sortable/paginated table, and allows selecting individual sessions or entire teams for bulk import.

## User Flow

1. On the Sessions page, click "Import" button
2. Modal opens and loads available transcripts from the filesystem
3. Filter by project name, sort by last modified/message count/project
4. Page through results
5. Select individual transcripts via checkboxes, or "Import Team" for bulk team import
6. Click Import — progress indicator shows during import
7. Errors are displayed inline if any imports fail
8. Modal closes on completion; session list refreshes via PubSub

## How It Works

`TranscriptDiscovery` scans `~/.claude/projects` directories for JSONL files, extracting metadata (message count, team name, agent name, project name, timestamps) from the first line and `sessions-index.json`. Results are capped at 500. Already-imported sessions are detected via batch DB check. `TranscriptListing` provides in-memory pagination, sorting, and text search over the discovery results. Team grouping (`group_by_team/1`) clusters sessions by team name for bulk import. Import runs as an async Task that triggers `SyncTranscripts` per session.

## Routes & Endpoints

No dedicated route — embedded as a modal component in `SessionsLive`.

## Key Files

- **Component**: `lib/spotter_web/components/import_modal_components.ex`
- **Service**: `lib/spotter/services/transcript_discovery.ex`
- **Service**: `lib/spotter/services/transcript_listing.ex`
- **LiveView host**: `lib/spotter_web/live/sessions_live.ex`

## Data Model

Discovery results are ephemeral (not persisted). On import, `Session` and `Message` resources are created via `SyncTranscripts` job. `Project` is auto-created or matched by name.

## Constraints & Edge Cases

- Discovery capped at 500 results to avoid memory issues
- Already-imported sessions are marked in the table (not selectable)
- Team bulk import imports all members of a team in one click
- Import is async — errors are collected and displayed after completion
- PubSub broadcast on import completion refreshes the session list
