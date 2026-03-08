# Subagent Detail

## Why This Exists

When reviewing a team session, users may want to focus on a single agent's transcript without the noise of other agents, while retaining the same annotation workflow available in the session detail view.

## What It Does

Renders the transcript for a single subagent within a session, with the same text selection and annotation capture workflow as the full session detail page.

## User Flow

1. From session detail or lanes view, click on a subagent name/link
2. See the subagent's transcript in isolation
3. Select text to create annotations (same review/explain workflow)
4. Annotations are scoped to the subagent

## How It Works

`SubagentLive` loads the session and filters messages to those belonging to the specified `agent_id`. Uses the same `TranscriptRenderer` pipeline and annotation components as `SessionLive`.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/sessions/:session_id/agents/:agent_id` | Subagent detail LiveView |

## Key Files

- **LiveView**: `lib/spotter_web/live/subagent_live.ex`

## Data Model

`Subagent` belongs_to `Session`, has_many `Messages`. `Annotation` can belong_to a `Subagent` (nullable).

## Constraints & Edge Cases

- If the agent_id doesn't match any subagent, shows a "not found" state
- Annotations created here are scoped to the subagent (visible in Reviews page with subagent context)
