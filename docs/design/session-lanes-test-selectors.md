# Session Lanes — UI Design Spec & Test Selector Map

## Overview

The session lanes view renders agent transcripts as side-by-side vertical columns
on a shared time axis. This spec defines stable `data-testid` selectors for e2e
testing and documents the visual hierarchy of the lanes layout.

---

## ASCII Wireframe — Full Layout with Test Hooks

```
+=========================================================================+
| data-testid="session-root"                                              |
|                                                                         |
|  [List] [Lanes]          <-- data-testid="view-mode-toggle"            |
|                                                                         |
|  +====================================================================+ |
|  | data-testid="lanes-panel"    (id="lanes-scroll", phx-hook)         | |
|  |                                                                    | |
|  | TAB BAR (role="tablist")                                           | |
|  | +----------------------------------------------------------------+ | |
|  | | [* lead]          [* agent-1]       [* agent-2]                | | |
|  | |  ^                  ^                 ^                        | | |
|  | |  lane-tab-lead      lane-tab-agent-1  lane-tab-agent-2        | | |
|  | +----------------------------------------------------------------+ | |
|  |                                                                    | |
|  | COLUMNS                                                            | |
|  | +----------+ +----------------------+ +------------------------+   | |
|  | | TIME     | | lead                 | | agent-1                |   | |
|  | | AXIS     | |                      | |                        |   | |
|  | |          | | lane-column-lead     | | lane-column-agent-1    |   | |
|  | |          | |                      | |                        |   | |
|  | | lanes-   | | +------------------+ | | +--------------------+ |   | |
|  | | time-    | | | HEADER           | | | | HEADER             | |   | |
|  | | axis     | | | * AgentName      | | | | * AgentName        | |   | |
|  | |          | | |   ^lane-name     | | | |   ^lane-name       | |   | |
|  | | +------+ | | |   2h 15m         | | | |   45m              | |   | |
|  | | |14:00 | | | |   ^lane-duration | | | |   ^lane-duration   | |   | |
|  | | |      | | | +------------------+ | | +--------------------+ |   | |
|  | | | over | | |                      | |                        |   | |
|  | | | lap  | | | +------------------+ | | +--------------------+ |   | |
|  | | | bar  | | | | assistant        | | | | assistant          | |   | |
|  | | |  ^   | | | | Some summary...  | | | | Some summary...    | |   | |
|  | | |  |   | | | +------------------+ | | +--------------------+ |   | |
|  | | |  |   | | |                      | |                        |   | |
|  | | |  overlap-bar-14:00              | |                        |   | |
|  | | |  |   | | | +------------------+ | | +--------------------+ |   | |
|  | | |14:00 | | | | user             | | | | tool               | |   | |
|  | | |  ^   | | | | Next message...  | | | | Tool result...     | |   | |
|  | | |  |   | | | +------------------+ | | +--------------------+ |   | |
|  | | |  overlap-time-14:00             | |                        |   | |
|  | | +------+ | |                      | |                        |   | |
|  | +----------+ +----------------------+ +------------------------+   | |
|  +====================================================================+ |
+=========================================================================+
```

---

## data-testid Naming Convention

### Agreed Scheme (architect-aligned)

| Element               | `data-testid` value              | Scope / Notes                    |
|-----------------------|----------------------------------|----------------------------------|
| Lanes container       | `lanes-panel`                    | Top-level panel wrapper          |
| Tab button            | `lane-tab-{agentName}`           | One per lane in tab bar          |
| Column div            | `lane-column-{agentName}`        | One per lane, holds header+msgs  |
| Agent name label      | `lane-name`                      | Inside lane header               |
| Duration label        | `lane-duration`                  | Inside lane header               |
| Time axis container   | `lanes-time-axis`                | Left gutter with timestamps      |
| Overlap bar           | `overlap-bar-{HH:MM}`           | Colored bar in time axis gutter  |
| Overlap time label    | `overlap-time-{HH:MM}`          | Timestamp text in overlap region |

### Naming Rules

1. **Kebab-case** — all lowercase, hyphen-separated (matches existing project convention)
2. **Parametric suffix** — dynamic values use `{paramName}` after a hyphen: `lane-tab-{agentName}`
3. **Agent name sanitization** — use the raw `agent_name` string from data, lowercased. Spaces become hyphens. E.g. agent name "Agent 1" becomes `lane-tab-agent-1`
4. **Time format** — `HH:MM` in 24h format matching `format_time/1` output (e.g. `overlap-bar-14:30`)
5. **No nesting in IDs** — selectors are flat; use DOM nesting for scoping (`[data-testid="lane-column-lead"] [data-testid="lane-name"]`)

### Review Notes

The proposed scheme is **approved** with one suggestion:

- **Add `lane-header`** — already exists in the codebase (`data-testid="lane-header"` on `.lanes-header`). Consider making it parametric: `lane-header-{agentName}` for disambiguation when multiple lanes are visible. However, since headers are always scoped inside their column, the current static `lane-header` is acceptable if tests scope selectors to the parent column.

---

## Visual Hierarchy

### Component Nesting (DOM order)

```
lanes-panel
  tablist
    lane-tab-{name}  (N buttons)
  lanes-time-axis
    overlap-bar-{HH:MM}  (per overlap region)
    overlap-time-{HH:MM}
  lane-column-{name}  (N columns)
    lane-header
      lane-name
      lane-duration
    lane-entry  (N message entries)
```

### Visual Weight (highest to lowest)

1. **Lane tabs** — primary navigation; active tab has `is-active` class
2. **Lane headers** — sticky, colored dot + bold agent name + muted duration
3. **Overlap bars** — colored indicators in time axis gutter (full vs partial)
4. **Message entries** — body content, role label + summary text
5. **Time axis labels** — lowest weight, tertiary color, monospace font

### Color System

Lane colors use CSS custom properties defined in `@lane_colors`:

| Token            | Purpose               |
|------------------|-----------------------|
| `--lane-lead`    | Lead/primary agent    |
| `--lane-agent-1` | Agent 1 accent        |
| `--lane-agent-2` | Agent 2 accent        |
| `--lane-agent-3` | Agent 3 accent        |
| `--lane-agent-4` | Agent 4 accent        |
| `--lane-agent-5` | Agent 5 accent        |
| `--lane-agent-6` | Agent 6 (fallback)    |

Each lane column has a 3px left border in its lane color. Tab buttons show a 6px colored dot; headers show an 8px colored dot.

---

## Spacing & Typography Tokens

### Typography (from component inline styles)

| Element          | Font weight | Font size          | Font family          | Color                  |
|------------------|-------------|--------------------|----------------------|------------------------|
| Agent name       | 600 (semi)  | body (inherited)   | system default        | `--text-primary` (inh) |
| Duration         | normal      | `var(--text-xs)`   | system default        | `--text-secondary`     |
| Message count    | normal      | `var(--text-xs)`   | system default        | `--text-secondary`     |
| Message role     | normal      | `var(--text-xs)`   | system default        | `--text-secondary`     |
| Time axis label  | normal      | `var(--text-xs)`   | `var(--font-mono)`   | `--text-tertiary`      |
| Time axis header | normal      | `var(--text-xs)`   | system default        | `--text-tertiary`      |

### Layout

| Property                  | Value                         |
|---------------------------|-------------------------------|
| View mode toggle gap      | `var(--space-1)`              |
| View mode toggle margin   | `margin-bottom: var(--space-2)` |
| Lane column left border   | `3px solid var(--lane-color)` |
| Tab dot size              | 6px diameter circle           |
| Header dot size           | 8px diameter circle           |

---

## E2E Testing Guidance

### Selector Patterns for Playwright

```js
// Container
page.locator('[data-testid="lanes-panel"]')

// Specific lane tab
page.locator('[data-testid="lane-tab-lead"]')

// Lane column scoped selectors
const leadCol = page.locator('[data-testid="lane-column-lead"]')
leadCol.locator('[data-testid="lane-name"]')    // "lead" text
leadCol.locator('[data-testid="lane-duration"]') // "2h 15m" text

// Overlap regions
page.locator('[data-testid="overlap-bar-14:00"]')
page.locator('[data-testid="overlap-time-14:00"]')

// Count assertions
page.locator('[data-testid^="lane-tab-"]')     // all tabs
page.locator('[data-testid^="lane-column-"]')  // all columns
page.locator('[data-testid^="overlap-bar-"]')  // all overlap bars
```

### What to Assert

| Assertion                         | Selector pattern                              |
|-----------------------------------|-----------------------------------------------|
| Lanes view is rendered            | `lanes-panel` visible                         |
| Correct number of agents          | Count `lane-tab-*` buttons                    |
| Tab-column correspondence         | Each tab name matches a column name            |
| Lane name text                    | `lane-name` text content inside column         |
| Lane duration present             | `lane-duration` text matches `/\d+[hms]/`     |
| Overlap regions exist             | At least one `overlap-bar-*` present           |
| Active tab state                  | Tab button has `is-active` class               |
| Tab switching works               | Click tab -> column gains `is-active`          |
