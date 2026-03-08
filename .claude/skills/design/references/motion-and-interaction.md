# Motion & Interaction

Source: `priv/static/assets/spotter.css`, `assets/js/app.js`

## Standard Transition

All interactive elements use **0.15s** timing:
```css
transition: background 0.15s, color 0.15s;
transition: background 0.15s, border-color 0.15s;
```

## Keyframe Animations

### `spotter-sidebar-tab-attention` (550ms, ease-out)
Subtle Y-translate bounce + blue text-shadow glow. Used for attention-needed tabs (e.g., new reviews).

### `spotter-sidebar-panel-attention` (700ms, ease-out)
Panel pulse with expanding box-shadow ring (`rgba(91, 156, 245, 0.18)`).

### `explain-pulse` (1.5s, ease-in-out, infinite)
Opacity: 1 → 0.6 → 1. Used for streaming annotation explanations.

### `lane-pulse` (expanding box-shadow)
Radial pulse for lane activity: `rgba(91, 196, 200, 0.4)` expanding to 8px then fading.

### `modal-slide-up` (0.15s, ease-out)
Dialog entrance: opacity 0 → 1, translateY(8px) → 0.

### `progress-complete` (0.6s)
Green glow: `rgba(74, 200, 154, 0.25)` → `0.6` → `0.4`.

### `study-card-exit` (0.2s, cubic-bezier)
Slide left + scale down: translateX(-20px), scale(0.96), opacity 0.

### `pulse-text` (opacity pulse)
Loading indicator text pulse.

## JS Animation Helpers

### `pulseClass(el, className, durationMs = 650)`
Force CSS animation restart by removing and re-adding a class. Defined in `app.js`.

### TranscriptTaskRail Timing
- Enter: 280ms
- Status update: 420ms
- Leave: 220ms

## Interactive States

### Buttons
- Default: `background: var(--surface-2)`, border: `var(--border-default)`
- Hover: `background: var(--surface-3)`, border: `var(--border-strong)`
- Disabled: opacity 0.5, pointer-events none

### Sidebar Tabs
- Default: color `--text-tertiary`, border-bottom transparent
- Hover: color `--text-secondary`
- Active: color `--accent-blue`, border-bottom `--accent-blue`

### Inputs
- Focus: `border-color: var(--accent-blue)`, outline none

### Cards/Panels
- Hover: border-color brightens (subtle → default)

### Links
- Hover: color `--accent-blue`, text-decoration underline

### Table Rows
- Hover: background `var(--surface-1)`

## Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  .sidebar-tab.is-attention,
  .sidebar-tab-content.is-attention,
  .annotation-form.is-attention {
    animation: none !important;
  }
}
```
