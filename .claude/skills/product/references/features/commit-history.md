# Commit History & Detail

## Why This Exists

Users need to trace what code changes came from which Claude Code sessions, browse commit history with project/branch context, and deep-dive into individual commits to see diffs, co-change patterns, and linked session transcripts.

## What It Does

A two-level view: (1) commit timeline with project and branch filters, cursor pagination, conventional commit emoji, and session link confidence badges; (2) commit detail with full diff, co-change group analysis, list of changed files, and linked session transcripts.

## User Flow

1. Navigate to History via sidebar
2. Filter by project and/or branch
3. Browse commits in reverse chronological order
4. See session link confidence badges (Verified 1.0 / Inferred %)
5. Click a commit to open its detail page
6. View the diff (toggle full diff), co-change groups with frequency badges
7. See linked sessions and select one to view its transcript inline
8. Click changed files to navigate to file detail

## How It Works

`HistoryLive` loads projects and branches for filter chips, then queries commits with cursor pagination. Conventional commit types (feat, fix, chore, etc.) get emoji rendering. Session links show confidence via `SessionCommitLink.confidence`. `CommitDetailLive` uses `CommitDetailComputers` (AshComputer) to reactively load commit metadata, diff text, co-change rows, linked sessions, and transcript rendered lines for the selected session.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/history` | Commit history LiveView |
| GET | `/history/commits/:commit_id` | Commit detail LiveView |

## Key Files

- **LiveView**: `lib/spotter_web/live/history_live.ex`
- **LiveView**: `lib/spotter_web/live/commit_detail_live.ex`
- **Computers**: `lib/spotter_web/live/commit_detail_computers.ex`
- **Service**: `lib/spotter/services/commit_detail.ex`
- **Service**: `lib/spotter/services/commit_history.ex`
- **Service**: `lib/spotter/services/commit_diff_extractor.ex`

## Data Model

`Commit` with `has_many :commit_files` (CommitFile). `SessionCommitLink` joins Session and Commit with `link_type` and `confidence`. `CoChangeGroup` (belongs_to Project) tracks files frequently changed together.

## Constraints & Edge Cases

- Confidence badges: 1.0 = "Verified" (hook-captured), < 1.0 = "Inferred N%" (async enrichment)
- Cursor pagination prevents loading entire commit history
- Diff toggle: initially shows truncated diff, "Show full diff" loads complete output
- Linked session transcript is rendered inline in the commit detail sidebar
- Distilled summary status shown per session (pending/completed/error)
