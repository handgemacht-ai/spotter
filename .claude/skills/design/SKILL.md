---
description: "Graphite Design System reference for Spotter. Reference when making UI/layout/CSS/interaction changes."
user-invocable: true
---

# Design — Spotter

Use this skill for any Spotter UI/layout/CSS/interaction changes.

## When To Use

Use this skill when you touch any of:
- `lib/spotter_web/live/**`
- `lib/spotter_web/components/**`
- `lib/spotter_web/**.heex`
- `priv/static/assets/spotter.css`
- `assets/**`

## Stack

- **CSS**: Custom "Graphite Design System" with CSS variables. No Tailwind, no CSS framework.
- **Fonts**: Bricolage Grotesque (UI) + JetBrains Mono (code), loaded via Google Fonts.
- **JS**: esbuild, Phoenix LiveView hooks. Libraries: cytoscape, highlight.js, marked, dompurify, sortablejs.
- **Templates**: Phoenix HEEX components.

## Non-Negotiables

- Avoid generic, boilerplate layouts — keep the UI intentional and a bit surprising, but not chaotic.
- Ensure pages work on both desktop and mobile.
- Use existing CSS variables from `references/color-palette.md` — never hard-code colors.
- Reuse existing class conventions (`.btn`, `.badge`, `.panel`, `.card`, `.page-header`) from `references/component-inventory.md`.
- Prefer existing fonts already loaded in `root.html.heex`.
- Use meaningful animations sparingly — see `references/motion-and-interaction.md`.
- Preserve the app shell (sidebar + topbar + main content) unless explicitly changing it.

## Review Checklist

- Responsive (mobile + desktop)
- Empty state
- Error state
- Loading state (where relevant)
- No regressions in navigation or spacing
- Design tokens match `references/color-palette.md` and `references/typography.md`
- Every form control has a label
- Keyboard focus is visible
- No hover-only interactions

## References

- [Color Palette](references/color-palette.md) — color tokens, CSS variables, hex values
- [Typography](references/typography.md) — fonts, type scale, weights, line-heights
- [Spacing & Layout](references/spacing-and-layout.md) — grid, spacing tokens, breakpoints
- [Component Inventory](references/component-inventory.md) — existing UI components with paths
- [Motion & Interaction](references/motion-and-interaction.md) — animation patterns, timing values
- [Branding](references/branding.md) — logo, brand colors, visual identity
- [Accessibility](references/accessibility.md) — ARIA patterns, focus management
