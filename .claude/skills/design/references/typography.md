# Typography

Source: `priv/static/assets/spotter.css`, `lib/spotter_web/components/layouts/root.html.heex`

## Font Families

| Variable | Font | Fallbacks | Usage |
|----------|------|-----------|-------|
| `--font-ui` | `Bricolage Grotesque` | `-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif` | All UI text |
| `--font-mono` | `JetBrains Mono` | `Fira Code, monospace` | Code, pre, terminal |

### Font Import

Loaded in `root.html.heex` via Google Fonts:
```html
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,400;12..96,500;12..96,600;12..96,700&display=swap" rel="stylesheet" />
```

Weights available: 400, 500, 600, 700. Optical sizing: 12px-96px.

## Type Scale

| Variable | Size | Usage |
|----------|------|-------|
| `--text-xs` | 12px | Small labels, badges, breadcrumbs |
| `--text-sm` | 13px | Body text (default), buttons, form labels |
| `--text-base` | 14px | Regular text, h3 headings |
| `--text-lg` | 18px | h2 headings, subheadings |
| `--text-xl` | 24px | h1 headings, page titles |

## Heading Hierarchy

| Element | Font Size | Font Weight | Line Height |
|---------|-----------|-------------|-------------|
| `h1` | `--text-xl` (24px) | 600 | 1.3 |
| `h2` | `--text-lg` (18px) | 600 | 1.3 |
| `h3` | `--text-base` (14px) | 600 | 1.3 |
| `h4, h5, h6` | inherit | 600 | 1.3 |

## Body Text

| Property | Value |
|----------|-------|
| Font Family | `var(--font-ui)` |
| Font Size | `var(--text-sm)` (13px) |
| Line Height | 1.5 |
| Color | `var(--text-primary)` |

## Line Height Scale

| Value | Usage |
|-------|-------|
| 1 | Badges, tight elements |
| 1.3 | Headings |
| 1.4 | Button text, form labels |
| 1.5 | Body text (standard) |
| 1.6 | Long-form content |

## Font Weight Usage

| Weight | Value | Usage |
|--------|-------|-------|
| Normal | 400 | Code blocks (monospace) |
| Medium | 500 | Button text, secondary labels, badges |
| Semibold | 600 | Headings, emphasis, primary labels |
| Bold | 700 | Sidebar logo, strong emphasis |

## Letter Spacing

| Context | Value |
|---------|-------|
| Section labels (uppercase) | `0.05em` |
| Alternative labels | `0.03em` |
