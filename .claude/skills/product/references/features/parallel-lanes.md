# Parallel Lanes View

## Why This Exists

Team sessions have multiple agents (lead, implementer, tester, etc.) working in parallel. A linear transcript view makes it impossible to understand the temporal relationship between agents. Users need a side-by-side timeline to see what each agent was doing at each point in time.

## What It Does

A CSS Grid table layout within the session detail page showing each agent as a column with a sticky time column. Detects idle periods (>60s gaps), renders inter-agent SendMessage link badges with SVG hover connectors, supports drag-and-drop column reordering, and provides full-fidelity transcript rendering in each lane.

## User Flow

1. Open a team session detail page
2. Toggle from "List" to "Lanes" view mode
3. See agents side-by-side in a time-aligned grid
4. Hover over a link badge to see an SVG connector line to the recipient agent
5. Click a link badge to open a message drawer with content preview
6. Click "Jump to response" to scroll to the recipient's message
7. Drag column headers to reorder agents (order persisted to localStorage)
8. Use toolbar: expand all / collapse all / collapse idle

## How It Works

`ParallelLanes.compute/1` processes session messages into per-agent lanes, detects idle periods (gaps > 60s between messages), and includes rendered lines via `TranscriptRenderer`. The CSS Grid table uses `grid-template-columns` with a sticky first column for wall clock + offset display. Row normalization groups messages into 1-second buckets for time alignment. `SortableColumns` JS hook enables drag-and-drop on desktop, persisting order to localStorage keyed by session ID. `ConnectorOverlay` JS hook draws dashed SVG connector lines with arrowheads on badge hover (100ms debounce). `LaneDrag` hook handles tab bar reordering. `ComputedLaneCache` caches computed lane data per team.

## Routes & Endpoints

No dedicated route — view mode toggle within `SessionLive` at `/sessions/:session_id`.

## Key Files

- **Component**: `lib/spotter_web/components/lanes_components.ex`
- **Domain**: `lib/spotter/transcripts/parallel_lanes.ex`
- **Cache**: `lib/spotter/transcripts/computed_lane_cache.ex`
- **JS**: `assets/js/hooks/sortable_columns.js`
- **JS**: `assets/js/hooks/connector_overlay.js`
- **JS**: `assets/js/hooks/lane_drag.js`
- **LiveView host**: `lib/spotter_web/live/session_live.ex`
- **Telemetry**: `lib/spotter/observability/parallel_lanes_telemetry.ex`

## Data Model

`ComputedLaneCache` (belongs_to Team) stores pre-computed lane payloads as Erlang terms. Input: `Session` messages grouped by `Subagent.agent_name`. `Team` and `TeamMember` define the agent roster.

## Constraints & Edge Cases

- Idle periods are only shown for gaps > 60 seconds
- Column reorder is session-scoped (localStorage), not persisted to DB
- SVG overlay is `pointer-events: none` to avoid blocking grid interactions
- Responsive: below 1199px breakpoint, lanes collapse to a tab bar with one visible lane at a time
- Full transcript rendering per lane (not just message text — includes tool blocks, code, markdown)
