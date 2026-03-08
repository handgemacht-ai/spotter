# Spacing & Layout

Source: `priv/static/assets/spotter.css`

## Spacing Scale (4px Base Unit)

| Variable | Value | Multiplier | Usage |
|----------|-------|-----------|-------|
| `--space-1` | 4px | 1x | Tight spacing |
| `--space-2` | 8px | 2x | Small gaps, badge padding |
| `--space-3` | 12px | 3x | Comfortable spacing, input padding |
| `--space-4` | 16px | 4x | Standard padding/margin |
| `--space-5` | 24px | 6x | Section spacing |
| `--space-6` | 32px | 8x | Large sections |
| `--space-7` | 48px | 12x | Major sections |
| `--space-8` | 64px | 16x | Full-page margins |

## Border Radius

| Variable | Value | Usage |
|----------|-------|-------|
| `--radius-sm` | 4px | Buttons, badges, small elements |
| `--radius-md` | 6px | Cards, standard components |
| `--radius-lg` | 8px | Panels, larger surfaces |

## App Shell Layout

```
+------+------------------------------------------+
|      | Topbar (breadcrumb, 12px 16px padding)   |
| Side |------------------------------------------+
| bar  |                                          |
| 200px|          Main Content                    |
|      |          (flex: 1, min-width: 0)         |
|      |                                          |
+------+------------------------------------------+
```

### Sidebar
- Width: `200px`, flex-shrink: 0
- Position: sticky, height: 100vh, overflow-y: auto
- Padding: `var(--space-4) var(--space-3)` (16px 12px)
- Background: `var(--surface-1)`
- Border: right 1px solid `--border-subtle`
- Gap: `var(--space-5)` (24px) between sections

### Topbar
- Padding: `var(--space-3) var(--space-4)` (12px 16px)
- Border: bottom 1px solid `--border-subtle`
- Font size: `var(--text-xs)` (12px)

### Main Content
- Container max-width: 1200px, auto margins
- Padding: `var(--space-4)` (16px)

## Session Layout (2-Panel)

```css
.session-layout {
  display: flex;
  gap: 0;
  height: calc(100vh - 37px);
}
.session-transcript { flex: 3; overflow-y: auto; }
.session-sidebar { flex: 1; border-left: 1px solid var(--border-default); }
```

## Lanes Grid (CSS Grid)

```css
grid-template-columns: 100px repeat(N, minmax(280px, 420px));
```
- Sticky time column, scrollable agent columns
- Uses `display: contents` for header row

## Responsive Breakpoints

| Breakpoint | Behavior |
|------------|----------|
| `max-width: 767px` | Mobile: stack layouts, reduce columns |
| `max-width: 1024px` | Tablet: session layout stacks vertically (60vh transcript / 40vh sidebar) |

Desktop-first approach: styles default to desktop, media queries override for smaller screens.
