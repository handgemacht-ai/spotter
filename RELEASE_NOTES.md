# Release Notes

## 2026-03-08

- Spotter now discovers and imports transcripts from multiple configurable root directories, with hook-provided path hints for faster resolution.

## 2026-03-06

- The home page now shows only your currently running sessions with live status updates, so you can see at a glance what's active right now.
- All sessions — past and present — have moved to a dedicated Sessions page, filterable by project from a new sidebar link.
- The "session ended" timestamp is now labeled more clearly throughout the app.

## 2026-03-04

- New command telemetry page shows how long shell commands take, how often they fail, and which ones are still running — updated live as new data arrives.

## 2026-02-27

- You can now browse and rate agent retrospectives in a dedicated Retros page, filtered by project, with expandable cards showing categorized observations and quick rating buttons.
- The Spotter plugin for Claude Code now exposes a smaller, more focused set of tools — keeping just what's needed for code review and retrospective workflows, reducing clutter for agents.

## 2026-02-26

- Claude Code agents can now submit structured retrospectives after each session, reflecting on what went well, what was frustrating, what surprised them, what they'd do differently, and what questions remain open.
- Retrospective data is stored and queryable, making it possible to spot patterns across sessions and improve agent workflows over time.

## 2026-02-24

- Team session timelines now show a structured table view with a sticky time column, making it easy to follow what each agent did and when.
- Idle periods (gaps longer than 60 seconds) are clearly marked so you can see when agents were waiting.
- Messages sent between agents are linked — hover over a link badge to see a connector line to the recipient, and click to open a detail drawer with a preview and jump-to-response button.
- Lane columns can be reordered by dragging their headers, and your preferred order is remembered per session.
- Long messages are collapsed by default with expand/collapse controls, including a toolbar to expand all, collapse all, or collapse only idle rows.
- Team sessions can now be imported in one click and display each team member's conversation side-by-side in reorderable, fully-rendered columns.

## 2026-02-23

- Made session lane views more reliable with stronger end-to-end test coverage and more stable test interactions.

## 2026-02-23 (earlier)

- Improved reliability of session tracing in lane workflows.
- Improved performance and responsiveness when switching transcript views and working with parallel transcript lanes.
