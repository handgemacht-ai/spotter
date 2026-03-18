---
name: spotter_project_conventions
description: Key conventions and gotchas in the Spotter codebase relevant to code review
type: project
---

`System.cmd("git", ...)` is used in many services (file_detail, git_log_reader, heatmap_calculator, etc.) despite CLAUDE.md saying to prefer GitRunner. This is widespread pre-existing practice — flag new occurrences but treat as low-confidence given the pattern is not consistently enforced.

OTEL span naming convention: `spotter.<domain>.<function>` (e.g., `spotter.skill_folder.detect_folders`).

`FileDetail.resolve_repo_root/1` calls `System.cmd("git", ["-C", cwd, "rev-parse", "--show-toplevel"])` directly — new services delegating to it inherit this pattern.

The `sanitize_html/1` function in SkillFolderReader uses regex-based sanitization rather than a proper HTML parser — a known limitation to flag as critical in new code since regex cannot reliably parse HTML.

**Why:** Regex HTML sanitization is bypassable via nested/malformed tags, HTML entities, and whitespace tricks (e.g., `<scr<script>ipt>`).
**How to apply:** In any new service rendering markdown to HTML, flag regex-only sanitization as critical. Recommend HtmlSanitizeEx or Phoenix.HTML.Safe instead.

The `@dangerous_tags` regex in `SkillFolderReader` intentionally strips `svg` tags, yet `card_meta/1` in `FolderComponents` emits SVG icon strings through `Phoenix.HTML.raw/1`. The SVG there is a hardcoded compile-time string literal, so it is not user-controlled — this is safe. Treat `Phoenix.HTML.raw` calls as safe only when the value is a hardcoded string literal or passed through `sanitize_html/1` first.

`FolderViewLive.handle_params/3` uses a single-clause pattern match on `%{"folder_path" => ..., "project_id" => ...}`. Because the route always provides both keys, no fallback clause is needed. The `@folder_path` assign is first set in `handle_params`, but `mount/3` does not set it; if `render/1` were called before `handle_params` (possible in some edge cases such as disconnected renders in tests), it would crash on `@folder_path`. Established pattern in this codebase is to initialise all assigns used in `render` from `mount/3`.

`FolderViewLive.handle_event("delete_annotation")` authorises deletion by checking `source: :file` but never verifies `project_id` matches the current project — an annotation from a different project with `source: :file` can be deleted. Compare with `PlanDetailLive` which checks `bead_id == socket.assigns.bead.id`.

`FolderContentHook` in `folder_content_hook.js` registers `mouseup`/`keyup` on `document` (not `this.el`). `PlanContentHook` registers on `this.el`. The `document`-level listeners fire for clicks anywhere on the page — including outside the folder panel — and will emit `clear_selection` events spuriously whenever the user clicks elsewhere while `FolderViewLive` is mounted.

The path traversal check in `FolderViewLive.handle_params/3` only rejects literal `".."` path segments, not encoded variants like `%2e%2e` — however Phoenix decodes URL segments before dispatching so encoded variants will already be decoded to `..` before they reach the check. The check is sufficient given Phoenix routing.

All LiveViews in this project use `use Phoenix.LiveView` directly (no `use SpotterWeb, :live_view` macro exists — SpotterWeb module is absent).

`RepoLive` (2026-03 review): `start_async(socket, :lazy_load, fn -> ...)` uses a fixed atom key — concurrent rapid folder clicks will silently cancel each other because Phoenix LiveView replaces an in-flight async task when the same key is re-launched. Only one lazy load can proceed at a time. The `@impl true` annotation on the second `handle_async/3` clause is also missing (follows the same inconsistency pattern as `PlansLive`). `maybe_expand_directory/5` on `{:error, _}` sets `expanded: true` on the node, causing it to render as visually expanded even though loading failed — inconsistent UX. In-flight lazy-load silently dropped (no error state shown); this is consistent with existing silent failure convention.
