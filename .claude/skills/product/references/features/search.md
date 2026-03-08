# Full-Text Search

## Why This Exists

With many sessions and commits across projects, users need a way to find specific content — a particular error message, function name, or conversation topic — without manually browsing.

## What It Does

FTS5-based full-text search across session transcripts and commits, with optional project scoping and relevance scoring. Returns ranked results with kind, title, subtitle, and URL.

## User Flow

1. Type a query in the search input
2. See ranked results showing: kind (session/commit), project, title, subtitle, relevance score
3. Click a result to navigate to the session or commit detail

## How It Works

`SearchController` handles `GET /api/search` with query params `q`, optional `project_id`, and `limit`. The search module uses FTS5 (SQLite full-text search) or LIKE fallback to query across message content and commit subjects/bodies. Results are scored by relevance and returned as JSON with `kind`, `project_id`, `external_id`, `title`, `subtitle`, `url`, `score`.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/search` | Full-text search API |

## Key Files

- **Controller**: `lib/spotter_web/controllers/search_controller.ex`
- **Search module**: `lib/spotter/search/`

## Data Model

Searches across `Message.content` and `Commit` subjects/bodies. FTS5 index is maintained by the search indexer. Results reference `Session` and `Commit` resources.

## Constraints & Edge Cases

- FTS5 provides relevance scoring; LIKE is the fallback for non-FTS queries
- Project scoping is optional — omit `project_id` for cross-project search
- Results include a URL for direct navigation to the source
- Search reindexing is handled by an Oban job
