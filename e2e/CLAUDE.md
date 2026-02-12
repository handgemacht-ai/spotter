# E2E Snapshot Policy

This suite starts with full-page Playwright snapshots and strict visual tolerance:

- `toHaveScreenshot(..., { maxDiffPixelRatio: 0.001 })`

If recurring flakiness appears due to full-page rendering drift, report it with:

1. failing snapshot names
2. trace/video artifacts
3. route and browser details

Do not automatically switch to component-level snapshots. Escalate to the user, who will decide whether component snapshots are a better fit.
