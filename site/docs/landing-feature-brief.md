# Spotter Landing Page Feature Messaging Brief

## ICP and Problem

The primary user is engineering teams reviewing Claude Code sessions and generated code. These teams rely on AI coding agents that produce significant volumes of terminal output, transcript data, and code changes across multiple sessions and repositories.

Today, reviewing Claude Code sessions means scrolling through raw terminal logs and fragmented transcript files scattered across local directories. There is no structured way to connect a session's conversation to the commits it produced, no surface for identifying risky changes, and no mechanism to trace what an agent did across subagent boundaries. Teams lose time re-reading logs they already reviewed, miss errors buried in tool output, and cannot confidently assess whether AI-generated code is safe to merge.

## Core Value Proposition

Hero headline: Review Claude Code sessions with commit-level intelligence.

Hero supporting copy: Spotter turns raw terminal and transcript streams into searchable timelines, linked commits, AI-ranked hotspots, and traceable execution context.

Primary CTA label: View the code on GitHub

Secondary CTA label: Track roadmap in beads

## Feature Blocks

### Live Transcript + Terminal Parity

- Review sessions with a synchronized terminal replay alongside a structured transcript, so you never lose the context of what the agent saw when it made a decision.
- Search, scroll, and annotate directly in the transcript without switching between raw log files and terminal windows.
- See tool calls, errors, and rework events inline so failed attempts are visible at a glance rather than buried in output.

### Session-to-Commit Lineage

- Every commit created during a Claude Code session is automatically linked back to that session with verified confidence, so you know exactly which conversation produced which code.
- Inferred links surface related commits even when they were not directly captured, using parent ancestry, patch matching, and file overlap signals.
- Browse commit history filtered by project and branch, with session associations displayed alongside each commit for fast cross-referencing.

### AI Hotspots + Co-change Evidence

- AI-scored hotspots rank code snippets by review priority using a multi-factor rubric, so reviewers focus on the riskiest changes first instead of reading diffs linearly.
- Co-change analysis groups files that were modified together across sessions, revealing implicit coupling and unexpected dependencies before they cause merge conflicts.
- Heatmaps visualize file-level churn and edit frequency per project, giving teams a quick overview of where AI agents concentrated their changes.

### Subagent-aware Review Flow

- Subagents spawned during a session are listed with their own message counts and timestamps, so reviewers can drill into each agent's contribution separately.
- Navigate from a parent session to any subagent transcript with a single click, maintaining full context about the session hierarchy.
- Annotate subagent transcripts independently, keeping review notes scoped to the specific agent that produced the code under review.

### Tracing + Local E2E Confidence

- End-to-end OpenTelemetry instrumentation traces requests from plugin hooks through Phoenix controllers, Ash actions, and LiveView interactions, so every operation is observable.
- Local E2E tests with Playwright run against real transcript fixtures inside Docker, giving teams confidence that the review workflow works before deploying changes.
- Silent-fail hook semantics guarantee that Spotter never blocks Claude Code, keeping agent performance within the sub-200ms budget even when the review server is unavailable.

## How It Works

1. Install the Spotter hooks in your Claude Code environment and start the Phoenix server locally. As you work with Claude Code, hooks automatically capture session events and commit metadata in the background without interrupting your workflow.

2. Open the Spotter dashboard to see all your projects and sessions organized by recency. Click any session to enter the review view, where a live terminal replay runs alongside a structured, searchable transcript with inline errors, tool calls, and rework indicators.

3. Use the sidebar to inspect linked commits, review AI-scored hotspots that flag the riskiest changes, and add annotations to specific terminal selections or transcript passages. Drill into subagent transcripts when sessions spawned child agents, and use the commit history and co-change views to trace how AI-generated code flows into your repository.

## Product Guardrails

- Do not claim managed cloud hosting. Spotter is a self-hosted, localhost application that runs on the developer's own machine.
- Do not claim authentication or authorization features. The prototype has no user accounts, login, or access control.
- Do not invent benchmark or performance numbers. Only reference the documented hook performance contract (p95 <= 75ms, hard budget <= 200ms) and Playwright snapshot tolerance (maxDiffPixelRatio: 0.001).
- Keep positioning aligned to open-source localhost prototype. Spotter is greenfield software under active development, not a production SaaS product.
