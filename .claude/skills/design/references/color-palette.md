# Color Palette

Source: `priv/static/assets/spotter.css` (Graphite Design System)

## Surface Layers (Dark Theme)

| Variable | Hex | Purpose |
|----------|-----|---------|
| `--surface-0` | `#0c0e14` | Base background |
| `--surface-1` | `#13161f` | Sidebar, panels, modals |
| `--surface-2` | `#1a1e2a` | Cards, inputs, elevated surfaces |
| `--surface-3` | `#232836` | Hover/elevated state |
| `--surface-4` | `#2d3344` | Interactive/pressed state |

## Text Colors

| Variable | Hex | Usage |
|----------|-----|-------|
| `--text-primary` | `#e8eaf0` | Main text content |
| `--text-secondary` | `#8b90a0` | Secondary text, labels |
| `--text-tertiary` | `#555a6e` | Disabled, muted, placeholders |

## Accent Colors

| Variable | Hex | Purpose |
|----------|-----|---------|
| `--accent-blue` | `#5b9cf5` | Primary action, links, focus, selected states |
| `--accent-green` | `#4ac89a` | Success, verified states |
| `--accent-amber` | `#e5a84b` | Warning, inferred states |
| `--accent-red` | `#e85454` | Error, danger states |
| `--accent-purple` | `#a78bfa` | Secondary accent, agent lead |
| `--accent-cyan` | `#5bc4c8` | Tertiary accent, parallel flows |

## Border Colors

| Variable | Hex | Usage |
|----------|-----|-------|
| `--border-subtle` | `#1e2230` | Soft dividers |
| `--border-default` | `#2a2f3e` | Standard borders |
| `--border-strong` | `#3a4052` | Strong emphasis borders |

## Lane Colors (Multi-Agent Visualization)

| Variable | Hex | Agent |
|----------|-----|-------|
| `--lane-lead` | `#a78bfa` | Lead agent (purple) |
| `--lane-agent-1` | `#5bc4c8` | First subagent (cyan) |
| `--lane-agent-2` | `#e5a84b` | Second subagent (amber) |
| `--lane-agent-3` | `#5b9cf5` | Third subagent (blue) |
| `--lane-agent-4` | `#4ac89a` | Fourth subagent (green) |
| `--lane-agent-5` | `#e85454` | Fifth subagent (red) |
| `--lane-agent-6` | `#d97706` | Sixth subagent (orange) |

Lane background tints use 6% opacity: e.g. `--lane-lead-bg: rgba(167, 139, 250, 0.06)`

## Parallel Region Indicators

| Variable | Value | Purpose |
|----------|-------|---------|
| `--parallel-full` | `rgba(91, 196, 200, 0.15)` | Fully parallel sections |
| `--parallel-partial` | `rgba(91, 196, 200, 0.08)` | Partially parallel |
| `--parallel-gutter-bar` | `#5bc4c8` | Vertical gutter indicator |
| `--parallel-gutter-partial` | `rgba(91, 196, 200, 0.4)` | Partial gutter |

## Badge Colors

### Status Badges

| Class | Background | Text |
|-------|------------|------|
| `.badge-verified` | `rgba(74, 200, 154, 0.15)` | `--accent-green` |
| `.badge-inferred` | `rgba(229, 168, 75, 0.15)` | `--accent-amber` |
| `.badge-error` | `rgba(232, 84, 84, 0.15)` | `--accent-red` |
| `.badge-agent` | `rgba(167, 139, 250, 0.15)` | `--accent-purple` |

### Heatmap Badges

| Class | Background | Text |
|-------|------------|------|
| `.badge-hot` | `#dc2626` | `#fff` |
| `.badge-warm` | `#ea580c` | `#fff` |
| `.badge-mild` | `#ca8a04` | `#fff` |
| `.badge-cold` | `#6b7280` | `#fff` |

### Git Diff Badges

| Class | Background | Text |
|-------|------------|------|
| `.badge-added` | `#16a34a` | `#fff` |
| `.badge-deleted` | `#dc2626` | `#fff` |
| `.badge-modified` | `#2563eb` | `#fff` |
| `.badge-renamed` | `#ca8a04` | `#fff` |

### Retro Category Badges

| Class | Color Variable |
|-------|---------------|
| `.retro-category-knowledge_gained` | `--accent-blue` |
| `.retro-category-effective_strategy` | `--accent-green` |
| `.retro-category-gotcha` | `--accent-amber` |
| `.retro-category-requirements_clarity` | `--accent-purple` |
| `.retro-category-struggle` | `--accent-red` |

## Dynamic Color Mixing

For tinted backgrounds without defining every combination:
```css
background: color-mix(in srgb, var(--accent-green) 8%, transparent);
```
