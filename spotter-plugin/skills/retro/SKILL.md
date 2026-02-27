---
description: "Submit structured retrospective observations via Spotter MCP"
allowed-tools: Bash, Read, Grep, Glob
context: inline
---

# Structured Session Retrospective

Submit structured observations about this session to Spotter for cross-session learning.

**This is observation collection only. Do NOT propose action items, rule changes, or improvements.**

## Step 1: Identify the session

Use the `$SPOTTER_SESSION_ID` environment variable:

```bash
echo $SPOTTER_SESSION_ID
```

Pass this value directly as `session_id` in the `submit_retro` call.

## Step 2: Reflect across the 5 categories

For each category below, think about what happened during this session. Not every category will have observations — skip categories with nothing meaningful to report.

### knowledge_gained
Facts about the codebase, tools, or environment you learned during this session. Things that would help a future agent working in the same area.

### effective_strategy
Approaches that worked well. Include **why** they worked so the insight transfers to other contexts, not just what you did.

### gotcha
Unexpected behavior, undocumented quirks, tricky edge cases you encountered. The kind of thing that would trip up another agent.

### requirements_clarity
Where the task specification was ambiguous, incomplete, or misleading. Be specific about what was unclear and what you had to assume.

### struggle
Where you had difficulty. Describe factually what happened — do not speculate about root causes or propose fixes. Root-cause analysis requires external telemetry that you don't have access to.

## Step 3: Wait — Re-examine your observations

**Before submitting, pause and reconsider:**

- Are any of your "effective_strategy" observations actually rationalizations of choices you made for other reasons?
- Are you missing any "gotcha" observations because you worked around issues without noticing them?
- Did you attribute struggles to external factors when the difficulty was in your own approach?
- Are your "knowledge_gained" items truly new knowledge, or things you should have already known from project docs?

Revise your observations based on this re-examination.

## Step 4: Compose a summary

Write a single sentence summarizing the session. This is optional but helpful for scanning retrospectives later.

## Step 5: Submit via MCP

Call the `submit_retro` MCP tool with:

- **session_id**: The session ID from Step 1
- **summary**: Your one-sentence summary (or omit)
- **items**: Array of observations, each with:
  - **category**: One of `knowledge_gained`, `effective_strategy`, `gotcha`, `requirements_clarity`, `struggle`
  - **observation**: What happened (factual)
  - **explanation**: Why it matters (the transferable insight)

Example call structure:

```json
{
  "session_id": "<session-id>",
  "summary": "Implemented retro resources and MCP actions for structured self-report.",
  "items": [
    {
      "category": "gotcha",
      "observation": "Ash create actions do not support require_atomic? — only update actions do.",
      "explanation": "When porting patterns from update actions to create actions, check which DSL options are valid for each action type."
    },
    {
      "category": "knowledge_gained",
      "observation": "MCP tool arguments arrive as string-keyed maps.",
      "explanation": "Access fields with item[\"key\"] not item[:key] when processing MCP input in after_action callbacks."
    }
  ]
}
```

## Rules

- **NO action items.** Do not propose changes, improvements, or fixes. Only observe.
- **NO root-cause analysis** for struggles. Describe what happened, not why.
- **Be specific.** "The tests were hard" is not useful. "The test setup required manual Sandbox.checkout because async: true caused FK violations" is useful.
- **Be honest.** The value of self-report depends on accuracy, not positivity.
- **Skip empty categories.** Not every session touches all 5 dimensions.
- Do NOT spawn agents or teams — this is a fast inline skill.
