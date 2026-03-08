# Branding

## Logo

CSS-only logo — no image files. Rendered in the sidebar:
- 28x28px square with `--accent-blue` background
- White "S" letter, `--font-ui`, font-weight 700
- Border-radius: `var(--radius-sm)` (4px)

Adjacent title: "Spotter" in `--text-primary`, font-weight 600.

## Brand Colors

Primary brand color is `--accent-blue` (`#5b9cf5`), used for:
- Logo background
- Primary button backgrounds
- Active navigation states
- Focus rings
- Links

## Fonts

- **UI**: Bricolage Grotesque — a distinctive, slightly quirky geometric sans-serif with optical sizing
- **Code**: JetBrains Mono — clean, developer-oriented monospace

## Visual Identity

- **Dark mode only** — no light theme
- **Graphite design system** — layered dark surfaces (#0c0e14 → #2d3344)
- **Grain texture overlay** on body (SVG fractal noise, opacity 0.03) adds subtle depth
- **Color accent philosophy**: semantic colors (blue=action, green=success, amber=warning, red=error, purple=agent, cyan=parallel)

## Navigation Icons

All inline SVGs (16x16) in `root.html.heex`:
- Dashboard: 2x2 grid
- Sessions: horizontal lines
- Reviews: speech bubble
- Retros: clock with history arrow
- History: clock face
- File metrics: gradient grid
- Telemetry: line chart / document

## Static Assets

No PNG/SVG/ICO logo files. All branding is CSS-based.
- CSS bundle: `/assets/spotter.css`
- JS bundle: `/assets/app.js`
- Fonts: Google Fonts CDN
