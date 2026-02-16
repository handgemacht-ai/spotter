# Product
Spotter helps to review Claude Code sessions and generated code. 

# Architecture
Ash, Phoenix, LiveView, xterm.js, tmux

The prototype runs on localhost, and has no authentication.

This project is greenfield. No legacy fallbacks, backwards compatability or similar is needed.

# Worktrees

## Daily workflow
git gtr new my-feature          # Create worktree folder: my-feature

## Run commands in worktree
git gtr run my-feature npm test # Run tests

## Navigate to worktree
gtr cd my-feature               # Requires: eval "$(git gtr init bash)"
cd "$(git gtr go my-feature)"   # Alternative without shell integration

## List all worktrees
git gtr list

## Remove when done
git gtr rm my-feature

## Or remove all worktrees with merged PRs/MRs (requires gh or glab CLI)
git gtr clean --merged

# Commit Linking

Sessions are linked to Git commits via hooks (deterministic, confidence 1.0) and async enrichment (inferred, confidence 0.60-0.90). Hook scripts must stay under 200ms and never call `git show` or `git patch-id`. See README for full details.

# Tracing Infrastructure

OpenTelemetry tracing is core infrastructure in Spotter. Do not remove instrumentation or disable tracing by default.

- Plugin/hook HTTP calls must preserve tracing metadata headers:
  - `traceparent` (when available)
  - `x-spotter-hook-event`
  - `x-spotter-hook-script`
- Hook scripts must remain non-blocking and fail-safe (silent failure is preferred over blocking Claude).
- `SPOTTER_OTEL_ENABLED=false` is only for local troubleshooting.

## Where manual tracing is required

Add manual spans where instrumentation is not automatic (Bandit/Phoenix/Ash cover common paths):

- Hook/controller business logic boundaries and explicit error branches
- Oban jobs and other background/async enrichment workers
- LiveView custom telemetry handlers and event-specific logic
- Phoenix Channels and stream lifecycle events (join/input/resize/stream start/stop)
- `Task`/`Task.Supervisor` boundaries and external service calls

## How to add manual tracing

- Controllers: wrap logic with `SpotterWeb.OtelTraceHelpers.with_span`.
- Jobs/services/channels: use `OpenTelemetry.Tracer.with_span`.
- Add structured attributes with `OpenTelemetry.Tracer.set_attribute/2`.
- Record failures with `OpenTelemetry.Tracer.set_status(:error, reason)` (or `SpotterWeb.OtelTraceHelpers.set_error/2` where applicable).
- Hook endpoints should set `x-spotter-trace-id` via `SpotterWeb.OtelTraceHelpers.put_trace_response_header/1`.

# Agent Patterns

Standard patterns for all Claude/agent integrations in Spotter. Follow these conventions when adding or modifying agent code.

## 1) Single-turn (no tools) via ClaudeCode.Client

Use `Spotter.Services.ClaudeCode.Client.query_text/3` or `query_json_schema/4` for single-turn prompts with no tool use.

**Required:**

- Wrap calls in `OpenTelemetry.Tracer.with_span/2`
- Set span attributes: `spotter.model_requested`, `spotter.timeout_ms`, `spotter.input_bytes`
- Use explicit `timeout_ms` option (never rely on default in production workers)

**Reference:** `lib/spotter/services/claude_code/client.ex`

```elixir
Tracer.with_span "spotter.my_feature.query" do
  Tracer.set_attribute("spotter.model_requested", model)
  Tracer.set_attribute("spotter.timeout_ms", timeout_ms)

  Client.query_json_schema(system_prompt, user_prompt, schema,
    model: model,
    timeout_ms: timeout_ms
  )
end
```

## 2) Tool-loop agent via Claude Agent SDK + MCP server

Use for multi-turn agents that need to call tools (spec agent, test agent, hotspot agent).

**Required SDK options:**

```elixir
%ClaudeAgentSDK.Options{
  tools: [],                              # no built-in tools
  allowed_tools: allowed_tools,           # explicit allowlist
  permission_mode: :dont_ask,             # no interactive prompts
  max_turns: @max_turns,                  # explicit int
  mcp_servers: %{"server-name" => server} # in-process MCP server
}
```

**Required observability:**

- Use `ClaudeAgentFlow.build_opts/1` to inject `TRACEPARENT` env and enable streaming
- Wrap the SDK stream with `ClaudeAgentFlow.wrap_stream/2` with `flow_keys`:
  - `FlowKeys.project(project_id)` when available
  - `FlowKeys.commit(commit_hash)` when available

**Required tool security:**

- Process-dictionary-bound scope (e.g. `ToolHelpers.set_project_id/1`) — never trust model-supplied scope parameters
- Clean up process dictionary in `after` block
- Referential integrity checks on foreign keys before writes

**Reference:** `lib/spotter/product_spec/agent/runner.ex`

```elixir
ToolHelpers.set_project_id(to_string(input.project_id))
ToolHelpers.set_commit_hash(input.commit_hash)

try do
  base_opts = %ClaudeAgentSDK.Options{
    mcp_servers: %{"spec-tools" => server},
    allowed_tools: allowed_tools,
    max_turns: @max_turns
  }

  opts = ClaudeAgentFlow.build_opts(base_opts)

  system_prompt
  |> ClaudeAgentSDK.query(opts)
  |> ClaudeAgentFlow.wrap_stream(flow_keys: flow_keys)
  |> Enum.reduce(acc, &collect/2)
after
  ToolHelpers.set_project_id(nil)
  ToolHelpers.set_commit_hash("")
end
```

## 3) Oban worker timeouts for LLM/git

Any Oban worker that calls git or LLM must implement `c:timeout/1`.

**Rules:**

- Worker `timeout/1` must be strictly greater than any internal `timeout_ms` passed to Claude Agent SDK
- Recommended: worker timeout = SDK timeout + 30s buffer for setup/teardown
- `Oban.Plugins.Lifeline` rescues orphaned `executing` jobs

## 4) Git usage in agent-adjacent code

- Never call `System.cmd("git", ...)` directly in agent-adjacent code
- Use `Spotter.Services.GitRunner` (Port-based, timeout-safe) when available
- All repo content used for analysis must be read at the analyzed commit (git-backed), not from the working tree

## 5) Canonical span naming

| Domain | Prefix | Example |
|---|---|---|
| Hotspot analysis | `spotter.commit_hotspots.*` | `spotter.commit_hotspots.agent.run` |
| Test sync | `spotter.commit_tests.*` | `spotter.commit_tests.agent.run_file` |
| Product spec | `spotter.product_spec.*` | `spotter.product_spec.invoke_agent` |
| Claude queries | `spotter.claude_code.*` | `spotter.claude_code.query` |
| Git operations | `spotter.git.*` | `spotter.git.run` |
| File detail | `spotter.file_detail.*` | `spotter.file_detail.load_file_content` |

# Agent Instructions

- Do not ignore credo lintings. Fix them.
- If commiting on a branch, always push to remote too.

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd list --status=closed --type=epic # See closed epics (worktrees)
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Merging a NAME worktree
Rebase the target branch onto main (not main onto target branch)
Merge the target branch with fast-forward 
Afterwards cleanup the branch and worktree (git gtr rm NAME) 
Cleanup tmux session: tmux kill-session -t spotter-NAME

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
