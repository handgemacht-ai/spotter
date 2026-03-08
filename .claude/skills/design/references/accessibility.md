# Accessibility

## ARIA Patterns in Use

| Pattern | Location | Usage |
|---------|----------|-------|
| `role="tablist"` / `role="tab"` | File metrics tabs | Tab navigation with `aria-current="page"` |
| `role="alert"` | Flash messages | Info and error notifications |
| `aria-expanded` | Co-change details, commit hotspots | Collapsible sections |
| `aria-label` | Icon buttons | Expand/collapse action buttons |

## Reduced Motion Support

```css
@media (prefers-reduced-motion: reduce) {
  .sidebar-tab.is-attention,
  .sidebar-tab-content.is-attention,
  .annotation-form.is-attention {
    animation: none !important;
  }
}
```

## Focus Management

- Input focus: `border-color: var(--accent-blue)`, outline removed (visible blue border instead)
- Global search (Cmd+K): keyboard navigation with arrow keys, Enter, Esc
- Form elements use visible labels

## Keyboard Navigation

- Global search palette: `Cmd/Ctrl+K` to open, `Esc` to close, arrows to navigate, `Enter` to select
- Collapsible sections: clickable headers toggle `aria-expanded`

## Color Contrast

The dark theme provides good contrast ratios:
- Primary text (`#e8eaf0`) on surface-0 (`#0c0e14`): ~14:1
- Secondary text (`#8b90a0`) on surface-0: ~6:1
- Accent blue (`#5b9cf5`) on surface-0: ~7:1

## Known Gaps

- No explicit skip-to-content links in root layout
- Sidebar navigation links lack `aria-label` attributes
- No focus traps in modal dialogs
- Some interactive elements may lack visible focus indicators beyond inputs

## Guidelines

- Every form control must have a label
- Keyboard focus must be visible
- No hover-only interactions — all hover effects must have keyboard equivalents
- Empty and error states must be clear and descriptive
