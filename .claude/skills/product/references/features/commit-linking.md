# Session-to-Commit Linking

## Why This Exists

The core value proposition of Spotter is tracing Claude Code sessions to the code they produced. Without linking, sessions and commits are disconnected — you can't answer "which session created this commit?" or "what commits did this session produce?"

## What It Does

A two-phase system that links sessions to commits: (1) deterministic hook capture with 100% confidence for commits created during a session, and (2) async enrichment that infers additional links via commit ancestry, patch matching, and file overlap analysis.

## User Flow

This feature has no direct UI — it's the data backbone that powers commit badges in session detail, session links in commit history, and the commit sidebar throughout Spotter.

## How It Works

### Phase 1: Deterministic Capture (Hook Path)

The `post-tool-capture.sh` plugin script runs after each Bash tool use:
1. Compares `HEAD` before and after tool execution
2. Computes `git rev-list` for new commit hashes (capped at 50)
3. POSTs `session_id`, `base_head`, `head`, and `new_commit_hashes` to `/api/hooks/commit-event`

These are stored as `observed_in_session` links with `confidence: 1.0`.

### Phase 2: Async Enrichment

The `EnrichCommits` Oban worker enriches commit metadata (parents, author, changed files, patch-id) and `SessionCommitLinker` computes inferred links:

| Link Type | Confidence | Criteria |
|-----------|------------|---------|
| `observed_in_session` | 1.00 | Commit hash captured by hook |
| `descendant_of_observed` | 0.90 | Parent is an observed commit |
| `patch_match` | 0.85 | Stable patch-id matches an observed commit |
| `file_overlap` | 0.60 | Jaccard overlap >= 0.70, time delta <= 360 min |

Only links with `confidence >= 0.60` are persisted.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/hooks/commit-event` | Receive commit hashes from hook |

## Key Files

- **Service**: `lib/spotter/services/session_commit_linker.ex`
- **Service**: `lib/spotter/services/commit_patch_extractor.ex`
- **Job**: `lib/spotter/transcripts/jobs/enrich_commits.ex`
- **Job**: `lib/spotter/transcripts/jobs/ingest_recent_commits.ex`
- **Plugin script**: `spotter-plugin/scripts/post-tool-capture.sh`
- **Controller**: `lib/spotter_web/controllers/hooks_controller.ex` (commit_event action)

## Data Model

`SessionCommitLink` joins `Session` and `Commit` with `link_type` (4-value enum), `confidence` (float 0.0-1.0), and `evidence` (map). Upserted with identity on `{session_id, commit_id}` to prevent duplicates. `Commit` stores enriched metadata: `parent_hashes`, `patch_id_stable`, `changed_files`.

## Constraints & Edge Cases

- Hook scripts must stay under 200ms (p95 target: 75ms)
- No `git show` or `git patch-id` in hook scripts (deferred to backend workers)
- Silent-fail semantics: hooks never block Claude Code
- Commits created outside Claude hooks are not deterministically observed (inference only)
- Squash merges may produce low-confidence links
- cURL timeouts in hooks: `--connect-timeout 0.1`, `--max-time 0.3`
- Max 50 commit hashes per hook event
