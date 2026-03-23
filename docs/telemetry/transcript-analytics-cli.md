# Transcript Analytics CLI

CLI commands for searching, inspecting, and comparing transcript-derived tool call runs.

## Prerequisites

Tool call runs are derived from imported transcript messages. Run `mix spotter.transcripts.sync` first to ensure transcripts are imported.

## Commands

### `mix spotter.transcripts.sync`

Import or re-import transcript files.

```bash
# Sync a specific session
mix spotter.transcripts.sync --session <session-id>

# Sync from a file
mix spotter.transcripts.sync --file /path/to/session.jsonl

# Sync from configured transcript roots
mix spotter.transcripts.sync --transcript-root /path/to/transcripts
```

### `mix spotter.transcripts.search`

Search tool call runs across sessions with filters.

```bash
# Find long-running Bash commands
mix spotter.transcripts.search --tool Bash --min-duration-ms 300000

# Search by project and status
mix spotter.transcripts.search --project spotter --status error

# JSON output for scripts
mix spotter.transcripts.search --tool Read --format json --limit 10
```

**Options:**
- `--project` — Filter by project name
- `--worktree` — Filter by worktree name
- `--session` — Filter by session ID
- `--tool` — Filter by tool name
- `--command-contains` — Filter by command text substring
- `--min-duration-ms` — Minimum duration in milliseconds
- `--max-duration-ms` — Maximum duration in milliseconds
- `--status` — Filter by status (completed, error, ongoing, orphan)
- `--limit` — Max results (default 50)
- `--format` — Output format: `table` (default) or `json`

### `mix spotter.transcripts.inspect`

Show detailed context for a session's tool call runs.

```bash
# List all runs for a session
mix spotter.transcripts.inspect --session <session-id>

# Inspect a specific tool use with surrounding context
mix spotter.transcripts.inspect --session <session-id> --tool-use-id toolu_abc123 --context 30
```

**Options:**
- `--session` — Session ID (required)
- `--tool-use-id` — Specific tool use to inspect
- `--context` — Number of surrounding transcript lines (default 20)
- `--format` — Output format: `table` (default) or `json`

### `mix spotter.transcripts.compare`

Compare tool call runs between session cohorts.

```bash
# Compare two sessions
mix spotter.transcripts.compare \
  --left-session <session-a> \
  --right-session <session-b>

# Compare with filters
mix spotter.transcripts.compare \
  --left-session <old> \
  --right-session <new> \
  --tool Bash --group-by command_fingerprint --format json
```

**Options:**
- `--left-session` — Left cohort session ID (repeatable)
- `--right-session` — Right cohort session ID (repeatable)
- `--tool` — Filter by tool name
- `--command-contains` — Filter by command text
- `--group-by` — Group by `tool_name` (default) or `command_fingerprint`
- `--format` — Output format: `table` (default) or `json`

## Session Slices

Slices provide focused transcript views on the session page.

### Creating a slice (programmatic)

Slices are created via the `SessionSlice` Ash resource. A future CLI command (`mix spotter.transcripts.slice.register`) will be added in bead .4.

### Viewing a slice

Navigate to `/sessions/:session_id?slice=:slice_id` to view only the highlighted transcript windows. Use "Show full transcript" to return to the complete view.
