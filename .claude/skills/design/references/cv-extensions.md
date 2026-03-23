# CV Extensions

## Theme Classification
- **Theme**: dark
- **Background**: #0c0e14 (primary), #13161f (secondary)
- **Rationale**: Graphite Design System uses a dark surface layer stack (surface-0 through surface-4) with light text on dark backgrounds

## Tolerance Values
| Property | Default | Tolerance | Severity if exceeded |
|----------|---------|-----------|---------------------|
| Spacing (padding/margin) | per token | ±2px | medium |
| Font size | per token | ±1px | high |
| Border radius | per token | ±1px | low |
| Color | per palette | CIEDE2000 ΔE ≤ 3 | medium |
| Line height | per token | ±2px | low |

## Component Visual Signatures

### Transcript Panel
- **Expected location**: Main content area, full width
- **Key visual features**: Row-based message list with type-based styling, tool badges, expand/collapse controls; surface-1 background
- **Size range**: Full viewport width minus sidebar (~220px sidebar), rows 40–80px tall

### Lanes Panel
- **Expected location**: Main content area (alternative to transcript)
- **Key visual features**: CSS Grid time-normalized table with color-coded lane columns (purple lead, cyan/amber/blue/green agent lanes), 6% opacity lane backgrounds
- **Size range**: Full content width, variable height based on timeline

### Annotation Editor
- **Expected location**: Sidebar panel or overlay
- **Key visual features**: Form with selected text preview, comment textarea, purpose selector (Note/Explain); surface-2 background
- **Size range**: 280–400px wide, 160–240px tall

### Annotation Cards
- **Expected location**: Below annotation editor in sidebar
- **Key visual features**: List of cards with source badges, explain streaming indicator, delete action; surface-2 background with subtle border
- **Size range**: 280–400px wide, 80–200px per card

### Buttons (.btn)
- **Expected location**: Throughout UI (toolbars, forms, modals)
- **Key visual features**: 8px/16px padding, 4px border-radius, surface-2 background, 1px border-default border; variants: primary (blue), success (green), danger (red), ghost (transparent)
- **Size range**: 28–36px tall, 60–160px wide

### Panels (.panel)
- **Expected location**: Content containers, sidebars
- **Key visual features**: Surface-1 background, 1px border-default, 8px border-radius, 16px padding
- **Size range**: 200–800px wide, variable height

### Cards (.card)
- **Expected location**: Within panels and content areas
- **Key visual features**: Surface-2 background, 1px border-subtle, 6px border-radius, 16px padding; hover state shifts border to border-default
- **Size range**: 200–600px wide, 80–300px tall

### Badges (.badge)
- **Expected location**: Inline with text, status indicators, tool tags
- **Key visual features**: 2px/8px padding, 4px border-radius, 12px font, 500 weight; semantic color variants (verified=green, inferred=amber, error=red, agent=purple)
- **Size range**: 20–24px tall, 40–120px wide

### Import Modal
- **Expected location**: Centered overlay
- **Key visual features**: Dialog with filters, transcript table, pagination controls, progress indicator; surface-1 background
- **Size range**: 600–900px wide, 400–700px tall
