# Retros (Agent Retrospectives)

## Why This Exists

Claude Code agents can learn from their sessions, but observations are lost without structured capture. Retrospectives allow agents to reflect on what worked, what didn't, and what surprised them — creating a corpus of patterns that improve workflows over time.

## What It Does

A project-filtered browser for retrospective submissions. Each submission contains items in 5 categories with expandable cards and rating buttons. Agents submit retros via MCP; humans browse and rate them here.

## User Flow

1. Navigate to Retros via sidebar
2. Select a project from filter chips (shows per-project submission counts)
3. Browse submissions — each shows agent name, session link, submitted_at
4. Expand a submission to see categorized items:
   - knowledge_gained, effective_strategy, gotcha, requirements_clarity, struggle
5. Rate individual items: useful / undecided / not_useful
6. Rating distribution shown on collapsed headers

## How It Works

`RetrosLive` loads `RetroSubmission` resources filtered by project, with nested `RetroItem` preloads. Expansion state tracked in `expanded_ids` assign. Rating updates call the `RetroItem.rate` action. Submissions are created by Claude Code agents via the MCP `submit_retro` tool, which creates a `RetroSubmission` with nested `RetroItem` records.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/retros` | Retros LiveView |

## Key Files

- **LiveView**: `lib/spotter_web/live/retros_live.ex`
- **Resource**: `lib/spotter/transcripts/retro_submission.ex`
- **Resource**: `lib/spotter/transcripts/retro_item.ex`

## Data Model

`RetroSubmission` belongs_to `Session` and `Project`, has_many `RetroItem`. Each `RetroItem` has `category` (5-value enum), `observation`, `explanation`, and `rating` (useful/undecided/not_useful, default: undecided).

## Constraints & Edge Cases

- 5 categories: knowledge_gained, effective_strategy, gotcha, requirements_clarity, struggle
- Rating is per-item, not per-submission
- Agents submit via MCP tool (not the UI) — the UI is read + rate only
- No action items — retrospectives capture observations only (by design)
- Color-coded category badges in the UI
