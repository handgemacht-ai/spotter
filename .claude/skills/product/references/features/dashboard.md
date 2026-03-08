# Dashboard (Ongoing Sessions)

## Why This Exists

Users need an at-a-glance view of what Claude Code sessions are currently running across all projects, without digging through session lists or filtering by status.

## What It Does

Shows only currently active sessions as cards with live start/finish updates. Sessions appear when they start and disappear when they finish, all without page reloads.

## User Flow

1. Open Spotter (root URL `/`)
2. See cards for each ongoing session showing session ID, project (cwd), status badge, start time
3. Cards appear in real-time as new sessions start
4. Cards are removed when sessions finish (briefly shown as "finished" before removal)
5. Click "Review" on any card to navigate to the session detail transcript

## How It Works

`SessionActivityBroadcaster` emits PubSub events on the `session_activity` topic when sessions start or end. `DashboardLive` subscribes on mount and handles `session_started` and `session_finished` events to add/remove cards from its `sessions` assign. Recently finished sessions are tracked in a `finished_ids` MapSet for brief visual feedback before removal.

## Routes & Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | Dashboard LiveView |

## Key Files

- **LiveView**: `lib/spotter_web/live/dashboard_live.ex`
- **Service**: `lib/spotter/services/session_activity_broadcaster.ex`

## Data Model

Reads `Session` resources filtered to those without `session_ended_at`. Each session belongs to a `Project`.

## Constraints & Edge Cases

- Only shows sessions where `session_ended_at` is nil (truly ongoing)
- PubSub-driven: if a session start event is missed (e.g., LiveView mounts after the event), a refresh button reloads the full list
- No pagination needed — ongoing session count is typically small
