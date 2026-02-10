# Product
Spotter helps to review Claude Code sessions and generated code. 

# Architecture
Ash, Phoenix, LiveView, xterm.js, tmux

The prototype runs on localhost, and has no authentication.

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

# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

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

