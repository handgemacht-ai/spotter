# E2E Snapshot Policy

This suite starts with full-page Playwright snapshots and strict visual tolerance:

- `toHaveScreenshot(..., { maxDiffPixelRatio: 0.001 })`

If recurring flakiness appears due to full-page rendering drift, report it with:

1. failing snapshot names
2. trace/video artifacts
3. route and browser details

Do not automatically switch to component-level snapshots. Escalate to the user, who will decide whether component snapshots are a better fit.

# Deterministic Test Data (Scenarios)

E2E tests use deterministic fixture data seeded via `mix spotter.e2e.seed`. Fixtures live in `test/fixtures/transcripts/` and are organized into **scenarios** — named subdirectories with known session IDs.

## Seed and cleanup commands

```bash
mix spotter.e2e.seed --scenario team-overlap   # Seed only team-overlap fixtures
mix spotter.e2e.seed --cleanup --scenario team-overlap  # Remove team-overlap data
mix spotter.e2e.seed                            # Seed all fixtures
mix spotter.e2e.seed --cleanup                  # Clean up all scenario data
```

Seeding wipes the target directory and replaces it with only the requested fixtures. The task also upserts an `e2e-spotter` project in the DB so `SyncTranscripts` processes the fixture files.

## Available scenarios

| Scenario | Fixture dir | Session IDs | Description |
|---|---|---|---|
| `team-overlap` | `test/fixtures/transcripts/team-overlap/` | `000...001`, `000...002`, `000...003` | Three overlapping agent sessions for lane/timeline tests |

## Adding a new scenario

1. Create a subdirectory under `test/fixtures/transcripts/<name>/` with deterministic `.jsonl` files (use zero-padded UUIDs like `00000000-0000-0000-0000-00000000000N`).
2. Register the scenario in `lib/mix/tasks/spotter.e2e.seed.ex` by adding an entry to `@scenarios`:
   ```elixir
   @scenarios %{
     "team-overlap" => %{subdir: "team-overlap", session_ids: [...]},
     "my-scenario"  => %{subdir: "my-scenario",  session_ids: ["00000000-..."]}
   }
   ```
3. Add a test in `test/mix/tasks/spotter.e2e.seed_test.exs` covering seed and cleanup for the new scenario.
4. Reference the deterministic session IDs in your Playwright tests.

# Page Object Model (POM) Convention

Each e2e view has a corresponding POM class in `e2e/support/pages/<name>.ts`. POMs encapsulate all `data-testid` selectors and provide assertion helpers so tests read as semantic statements rather than raw locator queries.

## Structure

```
e2e/
  support/
    pages/
      lanes.ts          # LanesPage — session-lanes view
      <view-name>.ts    # One POM per view
    liveview.ts         # Shared LiveView helpers
  tests/
    session-lanes.smoke.spec.ts
    <view-name>.smoke.spec.ts
```

## Writing a new POM

1. Create `e2e/support/pages/<view>.ts` exporting a class with:
   - Constructor accepting `Page` and setting up root locators via `getByTestId`
   - `goto(id)` method that navigates and waits for LiveView connection
   - Selector methods returning `Locator` (e.g. `column(name)`, `tab(name)`)
   - Assertion helpers prefixed with `expect` (e.g. `expectColumnCount(n)`)
2. Use `data-testid` attributes from the design spec (`docs/design/<view>-test-selectors.md`).
3. Write tests in `e2e/tests/<view>.smoke.spec.ts` using the POM — tests should not contain raw CSS selectors.
