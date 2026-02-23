# UI Design Spec: Parallel Transcript Lanes

**Feature**: Side-by-side agent transcripts on a shared timeline
**Author**: ui-designer
**Status**: Draft
**Design System**: Graphite (spotter.css)

---

## 1. Concept

The Parallel Transcript Lanes view shows multiple Claude Code agent transcripts arranged as vertical columns (lanes) on a shared horizontal time axis. The primary goal: instantly see **when agents worked in parallel** vs **sequentially**, and navigate any individual transcript in context.

Key insight: this is a **swim lane diagram meets code review**. Each agent gets a lane; time flows downward. Overlapping regions glow to signal concurrency.

---

## 2. Layout — ASCII Wireframes

### 2.1 Full View (Desktop, >=1200px)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ← Session  ·  Session abc-123  ·  3 agents  ·  12m 34s        [Lanes] [List] │
├────────┬────────────────────────────────────────────────────────────────────┤
│        │                                                                    │
│  TIME  │   LEAD (main)          AGENT-A              AGENT-B               │
│  AXIS  │   ┌──────────┐        ┌──────────┐         ┌──────────┐          │
│        │   │ ● lead    │        │ ● agent-a│         │ ● agent-b│          │
│ 00:00  │   │  purple   │        │  cyan    │         │  amber   │          │
│        │   ├──────────┤        │          │         │          │          │
│        │   │ msg: user │        │          │         │          │          │
│ 00:05  │   │ prompt... │        │          │         │          │          │
│        │   ├──────────┤        │          │         │          │          │
│        │   │ msg: asst │        │          │         │          │          │
│ 00:12  │   │ "I'll sp..│        │          │         │          │          │
│        │   ├──────────┤        │          │         │          │          │
│        │   │ ▶ Task    │        │          │         │          │          │
│ 00:15 ─┼───┤ spawn A,B ├───────►├──────────┤────────►├──────────┤──── ● PARALLEL │
│  ▓▓▓▓  │   │          │  ┌─────│ msg: asst│  ┌─────│ msg: asst│   START  │
│  ▓▓▓▓  │   │ (waiting)│  │     │ "Reading │  │     │ "Checking│          │
│ 00:22  │   │          │  │     │  files.."│  │     │  tests.."│          │
│  ▓▓▓▓  │   │          │  │     ├──────────┤  │     ├──────────┤          │
│  ▓▓▓▓  │   │          │  │     │ ▶ Read   │  │     │ ▶ Bash   │          │
│ 00:30  │   │          │  │     │ src/..   │  │     │ npm test │          │
│  ▓▓▓▓  │   │          │  │     ├──────────┤  │     ├──────────┤          │
│ 00:35 ─┼───┤ resumes  │◄──────┤ ● done   │  │     │ msg: asst│──── ● PARTIAL │
│  ░░░░  │   │          │       └──────────┘  │     │ "Found 2 │   MERGE  │
│ 00:40  │   │ msg: asst │                     │     │  failures│          │
│        │   │ "Agent A  │                     │     ├──────────┤          │
│ 00:45 ─┼───┤ reported."│◄──────────────────────────┤ ● done   │──── ● ALL │
│        │   ├──────────┤                     └─────└──────────┘   MERGED  │
│        │   │ msg: asst │                                                   │
│ 00:50  │   │ "Summary: │                                                   │
│        │   │  ..."     │                                                   │
│        │   └──────────┘                                                   │
│        │                                                                    │
└────────┴────────────────────────────────────────────────────────────────────┘
```

Legend:
- `▓▓▓▓` = parallel region marker on the time axis (all agents active)
- `░░░░` = partial parallel (some agents still active)
- `● PARALLEL START` / `● ALL MERGED` = event markers on the timeline gutter
- `▶ Task` / `▶ Read` / `▶ Bash` = tool call entries

### 2.2 Lane Header (sticky)

```
┌──────────────────────────────────┐
│ ● lead (main)           12m 34s │
│   SpotterWeb.SessionLive         │
│   47 messages · 12 tool calls    │
└──────────────────────────────────┘
```

Each lane header sticks to the top of its column while scrolling. Contains:
- Color-coded dot matching the lane color
- Agent name + role label
- Duration
- Working context (cwd or module)
- Message & tool call counts

### 2.3 Time Axis Gutter (left column, sticky)

```
┌────────┐
│  TIME  │
├────────┤
│ 00:00  │  ← Absolute timestamps
│        │
│ 00:05  │
│        │
│ ▓ 00:15│  ← Parallel region starts (filled marker)
│ ▓      │
│ ▓      │
│ ▓ 00:35│  ← Agent A merges back
│ ░      │  ← Partial parallel
│ ░ 00:45│  ← All merged
│        │
│ 00:50  │
└────────┘
```

- Timestamps appear at regular intervals or on significant events
- `▓` filled bar = full parallel region
- `░` lighter bar = partial parallel (only some agents still active)
- Blank = sequential (single agent active)

### 2.4 Transcript Entry (within a lane)

```
┌───────────────────────────────────┐
│ assistant                  00:12  │
│ ┌─────────────────────────────── │
│ │ I'll spawn two subagents to    │
│ │ handle these tasks in parallel │
│ └─────────────────────────────── │
├───────────────────────────────────┤
│ ▶ Task (spawn)             00:15  │
│   name: "agent-a"                 │
│   type: general-purpose           │
└───────────────────────────────────┘
```

### 2.5 Responsive — Tablet (768–1199px)

At narrower widths, collapse to a **stacked tab view** instead of side-by-side:

```
┌─────────────────────────────────────────────┐
│ ← Session  ·  abc-123  ·  3 agents         │
├─────────────────────────────────────────────┤
│  [● Lead]  [● Agent-A]  [● Agent-B]  [All] │
├────────┬────────────────────────────────────┤
│  TIME  │  AGENT-A transcript (selected)     │
│        │  ┌─────────────────────────────    │
│ 00:15  │  │ msg: assistant                  │
│  ▓▓▓▓  │  │ "Reading files..."              │
│        │  ├─────────────────────────────    │
│ 00:22  │  │ ▶ Read src/app.ex               │
│  ▓▓▓▓  │  │ result: 142 lines              │
│        │  ├─────────────────────────────    │
│ 00:30  │  │ msg: assistant                  │
│        │  │ "Found the issue..."            │
│ 00:35  │  │ ● Done — returned to lead       │
│        │  └─────────────────────────────    │
└────────┴────────────────────────────────────┘
```

- Tab bar with colored dots for each agent
- Time axis stays visible on left
- Parallel region markers still shown on time gutter
- "All" tab shows interleaved timeline (all agents, time-sorted)

### 2.6 Responsive — Mobile (<768px)

Single column. Time axis becomes inline timestamps. No lanes.

```
┌─────────────────────────────────┐
│ ← Session abc-123               │
│ [● Lead ▾]  (agent selector)    │
├─────────────────────────────────┤
│ 00:15  assistant                │
│ "Reading files..."              │
├─────────────────────────────────┤
│ 00:22  ▶ Read src/app.ex        │
│ 142 lines                       │
├─────────────────────────────────┤
│ 00:35  ● Done                   │
└─────────────────────────────────┘
```

---

## 3. Agent Color Palette

Extend the existing Graphite accents. Each agent gets a unique hue. The lead/main agent uses purple (consistent with existing `--accent-purple` for subagents).

### 3.1 Lane Colors

| Agent Role     | Token                  | Value       | Usage                          |
|---------------|------------------------|-------------|--------------------------------|
| Lead (main)   | `--lane-lead`          | `#a78bfa`   | = existing accent-purple       |
| Agent A       | `--lane-agent-1`       | `#5bc4c8`   | = existing accent-cyan         |
| Agent B       | `--lane-agent-2`       | `#e5a84b`   | = existing accent-amber        |
| Agent C       | `--lane-agent-3`       | `#5b9cf5`   | = existing accent-blue         |
| Agent D       | `--lane-agent-4`       | `#4ac89a`   | = existing accent-green        |
| Agent E       | `--lane-agent-5`       | `#e85454`   | = existing accent-red          |
| Agent F+      | `--lane-agent-6`       | `#d97706`   | additional if needed           |

### 3.2 Lane Background Tints (6% opacity of lane color)

Applied as `background` on the lane column when active:

| Token                        | Value                        |
|------------------------------|------------------------------|
| `--lane-lead-bg`             | `rgba(167, 139, 250, 0.06)` |
| `--lane-agent-1-bg`          | `rgba(91, 196, 200, 0.06)`  |
| `--lane-agent-2-bg`          | `rgba(229, 168, 75, 0.06)`  |
| `--lane-agent-3-bg`          | `rgba(91, 156, 245, 0.06)`  |
| `--lane-agent-4-bg`          | `rgba(74, 200, 154, 0.06)`  |
| `--lane-agent-5-bg`          | `rgba(232, 84, 84, 0.06)`   |

### 3.3 Parallel Region Indicators

| State             | Token                       | Value                        |
|-------------------|-----------------------------|------------------------------|
| Full parallel     | `--parallel-full`           | `rgba(91, 196, 200, 0.15)`  |
| Partial parallel  | `--parallel-partial`        | `rgba(91, 196, 200, 0.08)`  |
| Sequential        | (no background)             | transparent                  |
| Parallel gutter   | `--parallel-gutter-bar`     | `#5bc4c8` (accent-cyan)     |
| Partial gutter    | `--parallel-gutter-partial` | `rgba(91, 196, 200, 0.4)`   |

### 3.4 Spawn/Merge Event Markers

| Event          | Icon | Color                  | Description                         |
|---------------|------|------------------------|-------------------------------------|
| Spawn          | `●`  | lane color of spawned  | Appears in parent lane + arrow to child |
| Return/Merge   | `●`  | lane color of returned | Appears at bottom of child lane     |
| Connection line | `─`  | `--border-strong`      | Dashed line connecting spawn to lane start |

---

## 4. Typography

All values reference existing Graphite tokens.

| Element                | Font             | Size             | Weight | Color               |
|-----------------------|------------------|------------------|--------|---------------------|
| Lane header — name     | `--font-ui`      | `--text-base`    | 600    | `--text-primary`    |
| Lane header — meta     | `--font-ui`      | `--text-xs`      | 400    | `--text-secondary`  |
| Time axis labels       | `--font-mono`    | `--text-xs`      | 400    | `--text-tertiary`   |
| Message role label     | `--font-ui`      | `--text-xs`      | 600    | `--text-secondary`  |
| Message content        | `--font-ui`      | `--text-sm`      | 400    | `--text-primary`    |
| Tool call label        | `--font-mono`    | `--text-xs`      | 500    | lane accent color   |
| Tool call detail       | `--font-mono`    | `--text-xs`      | 400    | `--text-secondary`  |
| Event marker label     | `--font-ui`      | `--text-xs`      | 600    | `--accent-cyan`     |
| Tab labels             | `--font-ui`      | `--text-sm`      | 500    | `--text-secondary`  |
| Tab labels (active)    | `--font-ui`      | `--text-sm`      | 600    | `--text-primary`    |

---

## 5. Spacing Tokens

| Element                    | Token          | Value  |
|---------------------------|----------------|--------|
| Time axis width            | —              | 64px   |
| Lane min-width             | —              | 320px  |
| Lane gap                   | `--space-1`    | 4px    |
| Lane internal padding      | `--space-3`    | 12px   |
| Message vertical gap       | `--space-2`    | 8px    |
| Message internal padding   | `--space-3`    | 12px   |
| Lane header height         | —              | 56px   |
| Lane header padding        | `--space-3`    | 12px   |
| Parallel region bar width  | —              | 3px    |
| Event marker diameter      | —              | 8px    |
| Spawn arrow thickness      | —              | 1px    |

---

## 6. Interaction States

### 6.1 Hover — Lane Header

```css
/* Hover: slight surface lift + border glow */
background: var(--surface-3);
border-color: <lane-color>;  /* e.g. var(--lane-agent-1) */
transition: background 0.15s, border-color 0.15s;
```

### 6.2 Hover — Transcript Entry

```css
/* Hover: subtle highlight, matching existing transcript-row pattern */
background: var(--surface-3);
border-left: 3px solid <lane-color>;
transition: background 0.15s;
```

### 6.3 Selection — Transcript Entry

```css
/* Selected: stronger highlight + accent border */
background: rgba(<lane-color-rgb>, 0.12);
border-left: 3px solid <lane-color>;
box-shadow: inset 0 0 0 1px rgba(<lane-color-rgb>, 0.2);
```

### 6.4 Hover — Time Axis Region

Hovering a time position highlights the corresponding row across **all visible lanes** (cross-lane highlight):

```css
/* Time hover band — full-width highlight across all lanes */
.lanes-time-highlight {
  background: rgba(255, 255, 255, 0.03);
  pointer-events: none;
  position: absolute;
  left: 0;
  right: 0;
  height: <row-height>;
  transition: opacity 0.1s;
}
```

### 6.5 Scroll Sync

- All lanes scroll together vertically (shared scroll container)
- Time axis remains sticky-left
- Lane headers remain sticky-top
- Horizontal overflow: scroll container allows horizontal pan if lanes exceed viewport

### 6.6 Click — Spawn/Merge Event

Clicking a spawn event in the parent lane scrolls the child lane to its starting message and pulses the lane header:

```css
/* Pulse animation on spawn click */
@keyframes lane-pulse {
  0%   { box-shadow: 0 0 0 0 rgba(<lane-color-rgb>, 0.4); }
  70%  { box-shadow: 0 0 0 8px rgba(<lane-color-rgb>, 0); }
  100% { box-shadow: 0 0 0 0 rgba(<lane-color-rgb>, 0); }
}
```

### 6.7 Collapsed Lane State

Lanes can be collapsed to a thin vertical bar (24px) showing only the color indicator and agent name rotated vertically. Double-click to expand.

```
┌──┐  ┌──────────────────┐  ┌──┐
│ A│  │  Agent-B (active) │  │ C│
│ g│  │  full transcript  │  │ g│
│ e│  │  content here...  │  │ e│
│ n│  │                   │  │ n│
│ t│  │                   │  │ t│
│  │  │                   │  │  │
│ A│  │                   │  │ C│
└──┘  └──────────────────┘  └──┘
```

---

## 7. Parallel vs Sequential Visual Language

### 7.1 Parallel Regions

When 2+ agents are active simultaneously:
- **Time gutter**: solid `--parallel-gutter-bar` (3px cyan bar) runs along the time axis
- **Background wash**: `--parallel-full` applied across all active lane columns
- **Entry marker**: small "⫽" parallel icon on the first message in each concurrent lane
- **Region boundary**: top/bottom edges get a subtle horizontal rule in `--accent-cyan` at 20% opacity

### 7.2 Sequential Regions

When only one agent is active:
- No special background
- No gutter bar
- Standard lane rendering

### 7.3 Transition Points

Where the session goes from sequential to parallel (or vice versa):

```
Sequential region
─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─    ← dashed rule, accent-cyan @ 20%
  ● PARALLEL START (2 agents)     ← event label
▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓    ← parallel region background
▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─    ← dashed rule
  ● ALL MERGED                    ← event label
Sequential region
```

---

## 8. Component Inventory

| Component                  | Purpose                                        |
|---------------------------|------------------------------------------------|
| `ParallelLanesContainer`  | Main layout: time axis + lane columns          |
| `LaneColumn`              | Single agent lane with sticky header + messages |
| `LaneHeader`              | Agent name, dot, stats — sticky                |
| `TimeAxis`                | Left gutter with timestamps + parallel markers |
| `TranscriptEntry`         | Individual message or tool call in a lane      |
| `SpawnEvent`              | Visual spawn indicator with connection arrow   |
| `MergeEvent`              | Visual merge/return indicator                  |
| `ParallelRegionMarker`    | Background wash + gutter bar for overlap zones |
| `LaneTabBar`              | Responsive tab selector for <1200px            |
| `CollapsedLane`           | Thin vertical bar for minimized lanes          |

---

## 9. CSS Architecture Notes

All new styles should be added as a `/* --- Parallel Lanes --- */` section in `spotter.css`, following the existing flat-class convention (no BEM, no nesting beyond one level). Prefix all classes with `lanes-`:

```
.lanes-container
.lanes-time-axis
.lanes-column
.lanes-header
.lanes-entry
.lanes-entry:hover
.lanes-entry.is-selected
.lanes-spawn-event
.lanes-merge-event
.lanes-parallel-region
.lanes-tab-bar
.lanes-tab
.lanes-tab.is-active
.lanes-collapsed
```

New CSS custom properties should be added to `:root` alongside existing Graphite tokens.

---

## 10. Accessibility Notes

- Lane colors are chosen from the existing Graphite palette which meets WCAG AA contrast on `--surface-0` / `--surface-1`
- Parallel regions use background + gutter bar (dual indicator — not color alone)
- Spawn/merge events include text labels alongside icons
- Tab bar uses `role="tablist"` / `role="tab"` / `role="tabpanel"` ARIA pattern
- Keyboard: Tab focuses lanes, arrow keys navigate between entries, Enter opens detail
- Screen reader: parallel regions announced as "parallel work started, 2 agents active"

---

## 11. Motion / Animation

| Interaction              | Animation                              | Duration | Easing          |
|-------------------------|----------------------------------------|----------|-----------------|
| Lane collapse/expand     | Width transition                       | 200ms    | ease-out        |
| Hover highlight          | Background fade                        | 150ms    | ease (existing) |
| Spawn pulse              | Box-shadow pulse (see 6.6)             | 600ms    | ease-out        |
| Cross-lane time hover    | Opacity fade of highlight band         | 100ms    | linear          |
| Tab switch               | Opacity crossfade                      | 150ms    | ease            |
| Scroll to spawn target   | Smooth scroll                          | 300ms    | ease-out        |
| Parallel region enter    | Background opacity fade-in             | 200ms    | ease-in         |

All motion respects `prefers-reduced-motion: reduce` — disable animations, show final state immediately.

---

## Design Rationale

1. **Reuse existing Graphite tokens** — no new colors, just new semantic aliases. The 6 accent colors map naturally to up to 6 concurrent agents.
2. **Swim lanes, not Gantt** — developers already understand swim lanes from CI/CD pipelines and git branch graphs. Time flows downward (like transcripts), not left-to-right.
3. **Parallel = cyan wash** — cyan is the most neutral of the accents, doesn't clash with any lane color, and reads as "ambient information" rather than "warning" or "success".
4. **Progressive disclosure** — full lanes on desktop, tabs on tablet, single-agent on mobile. Same data, different density.
5. **Consistent with existing patterns** — subagent rows already use `accent-purple` with 6% opacity backgrounds. This spec extends that convention to multi-lane layout.
6. **Cross-lane hover** — the single most useful interaction for understanding "what was happening at this moment across all agents?"
