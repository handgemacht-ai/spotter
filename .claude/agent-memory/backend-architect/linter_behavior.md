---
name: Linter auto-reverts unused aliases
description: The post-write hook runs compile with --warnings-as-errors and a linter that auto-reverts changes causing warnings like unused aliases. Must write all code using new aliases in a single atomic write.
type: feedback
---

When adding new aliases to a file, the post-write linter hook will revert the alias additions if no code in the file uses them yet. This means you cannot incrementally add aliases first and then add code that uses them in a separate edit.

**Why:** The build hook compiles with `--warnings-as-errors` and auto-reverts files that produce warnings.

**How to apply:** Always use the Write tool (full file rewrite) instead of Edit when adding aliases alongside new code that references them. Both the alias and the code using it must be present in the same write operation.
