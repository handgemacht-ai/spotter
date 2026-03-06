# Product
Spotter helps to review Claude Code sessions and generated code. 

# Local Runtime (just)

Use `just` recipes from the repository root for day-to-day local runtime control:

- `just up` - Ensure OTEL stack + start Dolt + Phoenix. Idempotent: keeps healthy services running; if Phoenix is unhealthy, tries graceful process restart first, then falls back to full Overmind recycle.
- `just status` - Service health snapshot for Phoenix, Dolt, and Jaeger.
- `just logs` - Stream Overmind output.
- `just down` - Stop Phoenix/Overmind and Dolt.
- `just reset` - `down` + wipe Dolt volumes + clean `up`.
- `just otel-up` / `just otel-down` - Start/stop OTEL stack (delegates to shared workspace stack when available).
- `just otel-restart` / `just otel-status` - Restart and inspect OTEL stack health.
- `just test-smoke` - Run runtime smoke tests.

# Worktrees

## Daily workflow
git gtr new my-feature          # Create worktree folder: my-feature

## Run commands in worktree
git gtr run my-feature npm test # Run tests

## Navigate to worktree
gtr cd my-feature               # Requires: eval "$(git gtr init bash)"
cd "$(git gtr go my-feature)"   # Alternative without shell integration

## List all worktrees
git gtr list

## Remove when done
git gtr rm my-feature

## Or remove all worktrees with merged PRs/MRs (requires gh or glab CLI)
git gtr clean --merged

# Commit Linking

Sessions are linked to Git commits via hooks (deterministic, confidence 1.0) and async enrichment (inferred, confidence 0.60-0.90). Hook scripts must stay under 200ms and never call `git show` or `git patch-id`. See README for full details.

# Tracing Infrastructure

OpenTelemetry tracing is core infrastructure in Spotter. Do not remove instrumentation or disable tracing by default.

- Plugin/hook HTTP calls must preserve tracing metadata headers:
  - `traceparent` (when available)
  - `x-spotter-hook-event`
  - `x-spotter-hook-script`
- Hook scripts must remain non-blocking and fail-safe (silent failure is preferred over blocking Claude).
- `SPOTTER_OTEL_ENABLED=false` is only for local troubleshooting.

## Where manual tracing is required

Add manual spans where instrumentation is not automatic (Bandit/Phoenix/Ash cover common paths):

- Hook/controller business logic boundaries and explicit error branches
- Oban jobs and other background/async enrichment workers
- LiveView custom telemetry handlers and event-specific logic
- Phoenix Channels and stream lifecycle events (join/input/resize/stream start/stop)
- `Task`/`Task.Supervisor` boundaries and external service calls

## How to add manual tracing

- Controllers: wrap logic with `SpotterWeb.OtelTraceHelpers.with_span`.
- Jobs/services/channels: use `OpenTelemetry.Tracer.with_span`.
- Add structured attributes with `OpenTelemetry.Tracer.set_attribute/2`.
- Record failures with `OpenTelemetry.Tracer.set_status(:error, reason)` (or `SpotterWeb.OtelTraceHelpers.set_error/2` where applicable).
- Hook endpoints should set `x-spotter-trace-id` via `SpotterWeb.OtelTraceHelpers.put_trace_response_header/1`.

# Oban Worker Timeouts

Any Oban worker that calls git or LLM must implement `c:timeout/1`.

- `Oban.Plugins.Lifeline` rescues orphaned `executing` jobs

# Git Usage

- Never call `System.cmd("git", ...)` directly
- Use `Spotter.Services.GitRunner` (Port-based, timeout-safe) when available
- All repo content used for analysis must be read at the analyzed commit (git-backed), not from the working tree

# Agent Instructions

- Do not ignore credo lintings. Fix them.
- If commiting on a branch, always push to remote too.

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd list --status=closed --type=epic # See closed epics (worktrees)
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Merging a NAME worktree
Rebase the target branch onto main (not main onto target branch)
Merge the target branch with fast-forward 
Afterwards cleanup the branch and worktree (git gtr rm NAME) 
Cleanup tmux session: tmux kill-session -t spotter-NAME

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Auto-syncs to JSONL for version control
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update bd-42 --status in_progress --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task**: `bd update <id> --status in_progress`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Auto-Sync

bd automatically syncs with git:

- Exports to `.beads/issues.jsonl` after changes (5s debounce)
- Imports from JSONL when newer (e.g., after `git pull`)
- No manual export/import needed!

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

<!-- END BEADS INTEGRATION -->
