---
version: "1.0"
created: 2026-03-22
last_updated: 2026-03-22
period: "March–April 2026"
status: active
tags: [annotations, product-feedback, overlay-integration, mcp, image-storage]
---

# Product Roadmap — Spotter: March–April 2026

## Summary

Unify the two disconnected annotation systems — Spotter's structured annotation model (SQLite/Ash, resolution workflows, MCP, Reviews dashboard) and the browser overlay's visual capture (screenshots with Fabric.js markup, element picking, CSS selectors). The overlay becomes a thin capture client that pushes into Spotter via the existing Go API acting as a proxy. Spotter becomes the single source of truth for all annotations, including visual product feedback with image data.

## Features

### Product Feedback Source Type
**Scope**: Add `product_feedback` as a new annotation source type. This represents feedback captured during browser-based visual review — it may or may not include screenshots. The name reflects the intent (product feedback) not the capture mechanism (overlay/screenshot).
**User groups**: Solopreneur reviewing deployed apps in the browser, AI agents resolving feedback via MCP.
**Boundaries**:
- IN: New `:product_feedback` atom in source enum. Add to session_id exemption list (product_feedback annotations have no Claude Code session context). Migration to add the new enum value.
- IN: Update `source_badge/1` and `source_badge_class/1` in annotation components. Add badge styling for the new source.
- IN: Relax `bead_id` validation — currently locked to `source == :plan`, open to all source types. Any annotation can optionally link to a bead.
- OUT: No changes to existing source types or their behavior.
**Dependencies**: None — this is the foundation all other items build on.
**Assumptions**: The existing resolution workflow (code_change, process_change, tooling_change, doc_change, wont_fix) is sufficient for resolving visual product feedback. No new resolution kinds needed.
**Open questions**: None.

### Image Storage with DI Abstraction
**Scope**: Add first-class image storage to annotations via an `ImageStore` behaviour, following the existing `PlanSource` DI pattern. The behaviour defines `store(image_binary, annotation_id) -> {:ok, reference}`, `fetch(reference) -> {:ok, binary}`, and `delete(reference) -> :ok`. The default implementation stores blobs in SQLite. The annotation model gets an `image_ref` field that the behaviour resolves.
**User groups**: System-internal — consumed by the REST endpoint (write) and MCP tools / Reviews dashboard (read).
**Boundaries**:
- IN: `ImageStore` behaviour module. `SqliteImageStore` implementation (default). New `image_ref` attribute on annotation resource. Migration for the new column.
- IN: Configuration via `config :spotter, Spotter.ImageStore, adapter: Spotter.ImageStore.SqliteAdapter`.
- OUT: No S3/filesystem implementations this month — just the behaviour so it's swappable later.
- OUT: No image processing (resizing, compression, format conversion). Store the PNG as-is.
**Dependencies**: Depends on "Product Feedback Source Type" (needs the model changes in place first, though technically independent).
**Assumptions**: SQLite blob performance is acceptable at expected volumes (estimated <50 screenshots/week, 500KB–2MB each). The ImageStore behaviour is simple enough that the DI overhead is minimal.
**Open questions**: At what SQLite database size should we revisit the storage adapter? No hard number — monitor organically.

### Visual Metadata in Annotations
**Scope**: Store overlay-captured context (CSS selectors, element rects, HTML snippets, viewport dimensions, contained elements) in the annotation's existing `metadata` JSON map, namespaced under `feedback.*` to avoid collision with resolution metadata (`resolution`, `resolution_kind`, `resolved_at`).
**User groups**: AI agents resolving product feedback (they use CSS selectors and element context to understand what the user marked up), Reviews dashboard (displays viewport/element context alongside the screenshot).
**Boundaries**:
- IN: Namespace convention: `feedback.css_selector`, `feedback.element_rect`, `feedback.html_snippet`, `feedback.viewport`, `feedback.contained_elements`. Document the schema.
- IN: No schema validation on write — the metadata map accepts any keys. The namespace is a convention, not enforcement.
- OUT: No new first-class attributes for visual metadata — it all goes into the metadata map.
**Dependencies**: Depends on "Product Feedback Source Type".
**Assumptions**: The metadata map is flexible enough. Agents can parse the namespaced keys without confusion.
**Open questions**: None.

### REST Annotation Endpoint in Spotter
**Scope**: New Phoenix controller with two endpoints for creating annotations and attaching images. The overlay's Go API proxies to these instead of writing to the filesystem.
**User groups**: The Go overlay-api (only consumer). Not exposed to end users or agents directly.
**Boundaries**:
- IN: `POST /api/annotations` — accepts JSON body with annotation fields (source, comment, selected_text, bead_id, project_id, metadata). Returns annotation ID. Creates annotation via existing Ash `:create` action.
- IN: `POST /api/annotations/:id/image` — accepts binary image body (or multipart). Stores via ImageStore behaviour. Sets `image_ref` on the annotation.
- IN: No authentication beyond tailnet isolation. No CORS needed (Go proxy is server-to-server).
- OUT: No PUT/DELETE endpoints this month. Annotations are resolved via MCP, not REST.
- OUT: No rate limiting, request size limits beyond what Phoenix/Plug defaults provide.
**Dependencies**: Depends on "Product Feedback Source Type" and "Image Storage with DI Abstraction".
**Assumptions**: The Go overlay-api can make HTTP calls to Spotter's Phoenix server. Both run on the same tailnet, reachable by hostname.
**Open questions**: None.

### Go Overlay API as Spotter Proxy
**Scope**: Modify the Go overlay-api to forward annotation creation to Spotter's REST endpoint instead of writing JSON+PNG to the filesystem. The overlay JavaScript remains completely unchanged — it still calls `/__overlay/api/annotation` on the Go API.
**User groups**: Anyone using the browser overlay to capture visual feedback.
**Boundaries**:
- IN: Replace filesystem write in Go handler with two HTTP calls to Spotter: (1) create annotation, (2) attach image.
- IN: Pass through all captured data: bead_id, project, comment, CSS selector, element rect, viewport, HTML snippet, contained elements → mapped to Spotter's annotation fields and metadata namespace.
- IN: Orphan risk accepted — if image attach fails after annotation creation, the annotation exists without an image. No retry logic, no cleanup.
- OUT: No changes to the overlay JavaScript or UI. No new Go endpoints.
- OUT: No local fallback if Spotter is unreachable — the save fails and the user sees an error.
**Dependencies**: Depends on "REST Annotation Endpoint in Spotter". The overlay must be updated after the endpoint exists.
**Assumptions**: Spotter is always running when the overlay is in use (both are on the same tailnet, started together via `just up`).
**Open questions**: None.

### MCP: Image-Aware Annotation Tools
**Scope**: Extend MCP tool surface to support image annotations. Two changes: (1) `list_review_annotations` gains a `has_image` boolean in its response so agents know which annotations have screenshots, (2) new `get_annotation_image` tool that returns base64 image data for a specific annotation.
**User groups**: AI agents reviewing product feedback via Claude Code MCP integration.
**Boundaries**:
- IN: `has_image` field derived from whether `image_ref` is non-nil.
- IN: `get_annotation_image` tool: accepts annotation_id, returns base64 PNG as MCP image content type. Scoped by project (same as existing tools).
- IN: Optional MCP elicitation before returning large images (>1MB) — asks user "Include screenshot (X KB)?" before sending. Claude Code supports elicitation since v2.1.76.
- IN: `list_review_annotations` continues to support `bead_id` filtering (already works) — agents can fetch all annotations for a specific bead.
- OUT: No pagination for annotation lists this month. Current volumes don't justify it.
- OUT: No image thumbnails in MCP responses — full image or nothing.
**Dependencies**: Depends on "Image Storage with DI Abstraction" (needs ImageStore.fetch to serve images).
**Assumptions**: MCP elicitation works in AshAi.Mcp.Router context — needs verification. If not supported, skip elicitation and always return the image (agents can decide whether to request it). Base64 images in MCP responses are viable at <2MB.
**Open questions**: Verify AshAi.Mcp.Router supports elicitation. If not, the fallback is straightforward — always return the image when requested.

### Reviews Dashboard: Image Annotations
**Scope**: Extend the Reviews dashboard (ReviewsLive) to display product feedback annotations with screenshot thumbnails that expand on click.
**User groups**: Solopreneur reviewing all annotations in one place.
**Boundaries**:
- IN: Thumbnail display in annotation cards when `has_image` is true. Clickable thumbnail expands to full-size image (modal overlay or lightbox).
- IN: `product_feedback` source badge with distinct styling.
- IN: Visual metadata display — show CSS selector, viewport info alongside the screenshot when expanded.
- OUT: No separate tab or view for product feedback — they appear in the same Reviews list alongside all other annotation types.
- OUT: No lazy loading or virtualization of thumbnails — not needed at current volumes.
- OUT: No inline image editing or re-annotation from the dashboard.
**Dependencies**: Depends on "Image Storage with DI Abstraction" (thumbnail rendering) and "Product Feedback Source Type" (badge/filter).
**Assumptions**: Thumbnails can be served directly from SQLite blobs via a Phoenix endpoint (or the ImageStore behaviour). No CDN or caching needed at current scale.
**Open questions**: Thumbnail dimensions — start with a reasonable default (e.g., 200px wide, aspect-ratio preserved) and adjust based on how it looks.

### Plans View: Search, Filter & Sort
**Scope**: Make the Plans list view usable at scale (hundreds of beads per project). Add server-side fuzzy search across bead ID + title + description, hide-closed-by-default toggle, sortable column headers (priority desc default, date), and fix two rendering bugs: task count shows em-dash instead of actual child count, and plain-text bead descriptions (no markdown headers) are silently dropped. Remove the grouped/all-projects view — PlansLive always requires a project selection.
**User groups**: Solo developer browsing and triaging beads across projects.
**Boundaries**:
- IN: Text search input with 300ms debounce, server-side `LIKE` queries against Dolt (`WHERE id LIKE ? OR title LIKE ? OR description LIKE ?`). Searches both epics and orphan beads as separate Dolt queries, merged into one flat list.
- IN: Hide-closed toggle (default: hide closed). Server-side SQL filter — toggling "show closed" triggers a new async Dolt query, not client-side reveal.
- IN: Clickable column headers for Priority and Created columns. Toggle asc/desc on click. Default: priority descending. Date defaults to newest-first (desc).
- IN: All filter/sort state persisted as URL params (`?q=...&hide_closed=true&sort=priority&dir=desc`). `handle_params` restores state — browser back button preserves filters after navigating to a plan detail.
- IN: Task count via subquery in `list_epics` SQL (avoid N+1). Display count in Tasks column, but Tasks is not a sortable column.
- IN: Plain-text description fallback — when `BeadContentParser.extract_sections_ordered/1` returns `[]` but `description` is non-nil, render the full description string through Earmark as a single section. Render inside the `bead-sections` div to preserve PlanContentHook and annotation selection support.
- IN: Remove grouped/all-projects view entirely (delete `load_grouped_epics/0`, `grouped_plans/1`, the `:grouped` async handler). If no project is selected, show a "Select a project" prompt.
- IN: Dolt error surfacing — distinguish `:connection_refused` ("Dolt is not running"), `:unknown_project` ("Project not found"), and `:query_timeout` ("Query timed out") with user-facing messages in the table area. Replace silent empty-state fallback.
- IN: Update E2E tests — delete grouped-view tests, add tests for search, filter, sort, and error states. Regenerate visual snapshots.
- OUT: No client-side filtering. No search over child task content (search is epics + orphan beads at list level only). No sort by task count. No explicit "Back to Plans" link with filter params — browser back is sufficient.
**Dependencies**: None — standalone improvement to existing view.
**Assumptions**: Dolt `LIKE` substring matching is performant enough for hundreds of rows. No need for full-text search or Levenshtein scoring at current scale.
**Open questions**: None.

## Production Readiness

### Error Visibility for Overlay → Spotter Pipeline
**Scope**: When the Go overlay-api fails to push an annotation to Spotter (Spotter down, network error, validation failure), the user should see a clear error in the overlay UI. Currently the overlay shows a success/fail toast for filesystem writes — the same UX applies, just triggered by the HTTP response from Spotter instead.
**Why now**: Without this, failed annotation saves are silent — the user thinks their feedback was captured but it wasn't.
**Dependencies**: Depends on "Go Overlay API as Spotter Proxy".

## Technical Excellence

### Structured Logging for Annotation Pipeline
**Scope**: Add structured log entries in both the Go overlay-api (proxy calls) and the Phoenix REST endpoint (annotation creation, image storage). Include: annotation_id, bead_id, project, image_size_bytes, success/failure, duration_ms. Use existing logging infrastructure in both services.
**Why now**: The annotation pipeline crosses two services (Go → Elixir). When something fails, structured logs are the only way to debug without reproducing the issue.
**Dependencies**: Depends on "REST Annotation Endpoint in Spotter" and "Go Overlay API as Spotter Proxy".

## Security & Compliance

No items this month. All services are behind the tailnet. No user-facing authentication, no PII in annotations, no external data flows.

## Anti-Goals

### What NOT to Build
- **Overlay UI changes**: The overlay's Fabric.js markup, Cropper.js capture, element picker, bead tree, diff viewer, notes editor — all stay exactly as-is. The only change is the Go backend's storage target.
- **New overlay features**: No new capture modes, no new annotation types from the overlay side.
- **Billing/auth**: Not in scope. Tailnet membership is the only access control.
- **Image processing**: No resizing, compression, format conversion, or thumbnail generation. Store and serve the original PNG.
- **Migration of old annotations**: Existing filesystem annotations under `{project}/.annotations/{bead_id}/` are not migrated to Spotter. They remain accessible via the Go API's existing list endpoint until manually cleaned up.
- **Pagination in MCP**: Annotation list volumes don't justify cursor-based pagination yet.
- **Multiple ImageStore adapters**: Only the SQLite blob adapter is built. The behaviour exists for future S3/filesystem swaps, but no second implementation this month.

### What NOT to Invest In
- **High-availability for Spotter**: Single SQLite database is fine at current scale. No replication, no read replicas.
- **CDN or caching for screenshots**: Direct blob serving from SQLite/Phoenix is acceptable.
- **Annotation analytics**: No dashboards for annotation volume, resolution rates, or trends.

## Open Questions

- **AshAi.Mcp.Router elicitation support**: Does the current AshAi MCP integration support MCP elicitation? If not, skip elicitation and always return images when the agent requests them via `get_annotation_image`. This is a nice-to-have, not a blocker.
- **SQLite blob performance at scale**: Monitor database size growth as screenshots accumulate. If performance degrades, swap the ImageStore adapter to filesystem storage. No action needed until observed.
- **Thumbnail dimensions**: Start with 200px wide, aspect-ratio preserved. Adjust after seeing it in context on the Reviews dashboard.
