# Component Inventory

## HEEX Component Modules

### TranscriptComponents
**Path**: `lib/spotter_web/components/transcript_components.ex`

| Function | Purpose |
|----------|---------|
| `transcript_panel/1` | Main transcript panel with row iteration, expand controls |
| `transcript_row/1` | Individual message row with type-based styling, tool badges, subagent links |
| `expand_control/1` | Expand/collapse toggle for tool results and hooks |

Helpers: `row_classes/3`, `linkify_file_refs/3`, `status_dot_class/1`, `compute_expand_groups/2`, `compute_tool_hook_controls/2`

### AnnotationComponents
**Path**: `lib/spotter_web/components/annotation_components.ex`

| Function | Purpose |
|----------|---------|
| `annotation_editor/1` | Form: selected text preview + comment + purpose selector (Note/Explain) |
| `annotation_cards/1` | List of annotation cards with source badges, explain streaming, delete |

### LanesComponents
**Path**: `lib/spotter_web/components/lanes_components.ex`

| Function | Purpose |
|----------|---------|
| `lanes_panel/1` | CSS Grid time-normalized table for parallel agent transcripts |
| `table_row/1` | Time + cell per lane |
| `table_cell/1` | Message cell: chevron, type badge, duration, tool badges, link badges |

Helpers: `lane_color/1`, `sanitize_agent_name/1`, `format_duration/2`, `format_msg_type/1`

### ImportModalComponents
**Path**: `lib/spotter_web/components/import_modal_components.ex`

| Function | Purpose |
|----------|---------|
| `import_modal/1` | Dialog for JSONL import: filters, transcript table, pagination, progress |

Helpers: `session_label/1`, `format_project_name/1`, `truncate_text/1`, `relative_time/1`

### Layouts
**Path**: `lib/spotter_web/components/layouts.ex`

Embeds templates from `layouts/` directory:
- `root.html.heex` — HTML shell, Google Fonts, sidebar nav, global search (Cmd+K)
- `app.html.heex` — Inner content renderer

## CSS Component Classes

### Buttons (`.btn`)

```css
padding: var(--space-2) var(--space-4);  /* 8px 16px */
border: 1px solid var(--border-default);
border-radius: var(--radius-sm);         /* 4px */
background: var(--surface-2);
font-weight: 500;
font-size: var(--text-sm);               /* 13px */
transition: background 0.15s, border-color 0.15s;
```

Variants: `.btn-primary` (blue), `.btn-success` (green), `.btn-danger` (red), `.btn-ghost` (transparent)

### Panels (`.panel`)

```css
background: var(--surface-1);
border: 1px solid var(--border-default);
border-radius: var(--radius-lg);  /* 8px */
padding: var(--space-4);          /* 16px */
```

### Cards (`.card`)

```css
background: var(--surface-2);
border: 1px solid var(--border-subtle);
border-radius: var(--radius-md);  /* 6px */
padding: var(--space-4);          /* 16px */
```

Hover: `border-color: var(--border-default)`

### Badges (`.badge`)

```css
padding: 2px var(--space-2);      /* 2px 8px */
border-radius: var(--radius-sm);  /* 4px */
font-size: var(--text-xs);        /* 12px */
font-weight: 500;
line-height: 1.4;
```

Semantic variants: `.badge-verified`, `.badge-inferred`, `.badge-error`, `.badge-agent`, `.badge-hot`, `.badge-warm`, `.badge-mild`, `.badge-cold`, `.badge-added`, `.badge-deleted`, `.badge-modified`, `.badge-renamed`

### Inputs

```css
background: var(--surface-1);
border: 1px solid var(--border-default);
border-radius: var(--radius-sm);
padding: var(--space-2) var(--space-3);  /* 8px 12px */
font-family: var(--font-ui);
font-size: var(--text-sm);
color: var(--text-primary);
/* Focus: border-color: var(--accent-blue) */
```

### Other Patterns

| Class | Purpose |
|-------|---------|
| `.page-header` | Page title area |
| `.breadcrumb` | Navigation breadcrumbs |
| `.filter-bar`, `.filter-btn` | Filter controls |
| `.empty-state` | Empty state messaging |
| `.sidebar-tab` | Tab navigation in sidebar panels |
| `.search-palette-*` | Global search (Cmd+K) overlay |
| `.ingest-progress` | Progress indicator |
| `.study-card` | Study mode cards |

## LiveView Hooks (`assets/js/`)

| Hook | File | Purpose |
|------|------|---------|
| `FlowGraph` | `flow_graph.js` | Cytoscape DAG visualization |
| `BrowserTimezone` | `app.js` | Client timezone detection |
| `StudyCard` | `app.js` | Card entrance + syntax highlighting |
| `StudyProgress` | `app.js` | Study progress tracking |
| `PreserveScroll` | `app.js` | Scroll position preservation |
| `TranscriptHighlighter` | `app.js` | Code highlighting in transcripts |
| `FileHighlighter` | `app.js` | File content highlighting |
| `DiffHighlighter` | `app.js` | Diff highlighting |
| `SnippetHighlighter` | `app.js` | Code snippet highlighting |
| `LaneDrag` | `hooks/lane_drag.js` | SortableJS lane tab reordering |
| `SortableColumns` | `hooks/sortable_columns.js` | Column drag-drop with localStorage |
| `ConnectorOverlay` | `hooks/connector_overlay.js` | SVG connectors between lanes |
| `TranscriptTaskRail` | `hooks/transcript_task_rail.js` | Task rail state + animations |
