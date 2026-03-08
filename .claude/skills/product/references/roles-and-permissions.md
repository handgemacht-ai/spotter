# Roles & Permissions

Spotter is a localhost prototype with **no authentication**. There is a single implicit user with full access to all features.

## Access Model

| Role | Capabilities | Restrictions |
|------|-------------|-------------|
| Local user | All pages, all actions, all API endpoints | None |
| Claude Code agent (via MCP) | 4 MCP tools: list/resolve annotations, create hotspot, submit retro | Project-scoped via header/session/fallback |

## MCP Project Scoping

MCP tools are scoped to a project using a priority chain:
1. `x-spotter-project-dir` header (explicit)
2. `session_id` query param from `CLAUDE_ENV_FILE` (session context)
3. Most recent session's project (fallback)

This is not authentication — it's context scoping to ensure tools operate on the right project.
