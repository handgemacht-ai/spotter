# Known Limitations

## Session Linking
- Commits created outside Claude Code hooks are not deterministically observed (inference only)
- Squash merges may require inference and can produce low-confidence links
- Git-only in V1 — no GitHub/GitLab API integration for PR-level linking

## Access & Deployment
- No authentication (localhost prototype, single implicit user)
- No production deployment support (local-dev only)
- No installer or bundle path for end users

## Analysis
- `.spotterignore` only applies to co-change analysis, not heatmap computation
- Heatmap uses a fixed 30-day rolling window (configurable per project but not per query)
- File size tab shows current sizes only, not historical trends

## Technical
- Context leak in telemetry handlers (`sp-nuvm` known issue — affects `start_span`/`end_span` in long-lived processes)
- Transcript import capped at 500 discovered files per scan
- FTS5 search index requires periodic reindexing via Oban job
