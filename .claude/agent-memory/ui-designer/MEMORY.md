## Graphite Design System

Spotter uses "Graphite Design System" — dark theme tokens in `priv/static/assets/spotter.css` lines 1-80. No `.claude/skills/front-end-design/` exists. Key token families:
- Surfaces: `--surface-0` (#0c0e14) to `--surface-4` (#2d3344)
- Text: `--text-primary` (#e8eaf0), `--text-secondary` (#8b90a0), `--text-tertiary` (#555a6e)
- Accents: blue (#5b9cf5), green (#4ac89a), amber (#e5a84b), red (#e85454), purple (#a78bfa), cyan (#5bc4c8)
- Borders: subtle (#1e2230), default (#2a2f3e), strong (#3a4052)
- Fonts: Bricolage Grotesque (--font-ui), JetBrains Mono (--font-mono)
- Spacing: --space-1 (4px) to --space-8 (64px)
- Radii: sm (4px), md (6px), lg (8px)
- Type: xs (12px), sm (13px), base (14px), lg (18px), xl (24px)

## Plan Detail Page

PlanContentHook (`assets/js/hooks/plan_content_hook.js`) handles text selection annotations + hljs + image click. It attaches to `#plan-sections` div. The hook tree-walks its `this.el` for annotation highlights and checks `this.el.contains()` for selection scope — so all annotatable content must be inside that container.
