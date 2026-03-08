# File Metrics (Heatmap, Hotspots, Co-change, File Size)

## Why This Exists

Understanding codebase health requires identifying patterns: which files change most often (heatmap), which areas get repeated fixes (hotspots), which files always change together (co-change), and which files are unusually large.

## What It Does

A four-tab analysis page — heatmap, hotspots, co-change, and file size — with per-project scoping, min score filters, sort controls, and expandable detail views. Each tab provides a different lens on code quality and change patterns.

## User Flow

1. Navigate to File Metrics via sidebar (or project-scoped URL)
2. Select a project if not already scoped
3. Switch between tabs:
   - **Heatmap**: files ranked by change frequency (30-day window), filterable by min heat score
   - **Hotspots**: code regions that get repeated changes, filterable by min overall score
   - **Co-change**: groups of files that always change together, with scope (file/directory), expandable member stats
   - **File size**: files ranked by size
4. Click file names to navigate to file detail

## How It Works

Heatmap and co-change data are computed by Oban background jobs (`ComputeHeatmap`, `ComputeCoChange`) triggered on commit ingestion. `HeatmapCalculator` computes change frequency over a 30-day window. `CoChangeCalculator` identifies files that appear together in commits. `CommitHotspotMetrics` scores code regions by frequency, recency, and impact. The LiveView loads precomputed data from Ash resources with client-side filtering.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/file-metrics` | File metrics LiveView (all projects) |
| GET | `/projects/:project_id/file-metrics` | Project-scoped file metrics |

## Key Files

- **LiveView**: `lib/spotter_web/live/file_metrics_live.ex`
- **Service**: `lib/spotter/services/heatmap_calculator.ex`
- **Service**: `lib/spotter/services/co_change_calculator.ex`
- **Service**: `lib/spotter/services/co_change_intersections.ex`
- **Service**: `lib/spotter/services/commit_hotspot_metrics.ex`
- **Service**: `lib/spotter/services/commit_hotspot_filters.ex`
- **Job**: `lib/spotter/transcripts/jobs/compute_heatmap.ex`
- **Job**: `lib/spotter/transcripts/jobs/compute_co_change.ex`

## Data Model

`FileHeatmap` (belongs_to Project): `relative_path`, `change_count_30d`, `heat_score` (0-100). `CoChangeGroup` (belongs_to Project): `scope`, `group_key`, `members` array, `frequency_30d`. `CoChangeGroupMemberStat`: per-member size/LOC. `CoChangeGroupCommit`: individual commit records per group. `CommitHotspot` (belongs_to Project, Commit): `relative_path`, `line_start/end`, `snippet`, `reason`, `overall_score` (0-100).

## Constraints & Edge Cases

- Heatmap uses a 30-day rolling window (configurable via `ProjectIngestState.heatmap_window_days`)
- Co-change computation respects `.spotterignore` patterns
- Hotspots are per-commit (multiple hotspots can exist for the same file across commits)
- Oban jobs have 30-second uniqueness deduplication to avoid redundant recomputation
- File size tab reads current file sizes, not historical
