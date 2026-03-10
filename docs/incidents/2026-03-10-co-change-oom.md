# Spotter Co-Change OOM Incident

Date: 2026-03-10
Follow-up issue: `le-bdy`
Containment issue: `le-d9e`

## Summary

`spotter` repeatedly exhausted memory on the Hetzner development machine while
running `Spotter.Transcripts.Jobs.ComputeCoChange` for project `handgemacht`
(`019cc564-775d-7bbf-96b8-8c35bf7f086d`).

The failure mode was a kernel OOM kill of `beam.smp` inside
`rig@spotter.service`, followed by automatic restart and re-enqueue of more
co-change work.

## Impact

- `spotter` restarted repeatedly throughout March 10, 2026.
- The machine entered severe memory pressure and swap churn.
- Other processes on the box were affected by global OOM pressure.
- Co-change data for `handgemacht` never reached a stable watermark.

## Observed Symptoms

Kernel and systemd logs showed repeated OOM kills for the same service:

- `2026-03-10 00:43:53`
- `2026-03-10 00:58:48`
- `2026-03-10 09:04:43`
- `2026-03-10 09:13:42`
- `2026-03-10 09:20:27`
- `2026-03-10 09:29:15`
- `2026-03-10 09:35:24`
- `2026-03-10 09:41:06`
- `2026-03-10 09:48:10`

Representative OOM evidence:

- killed process: `beam.smp`
- service: `rig@spotter.service`
- anonymous RSS at kill: about `63 GiB`
- total VM at kill: up to about `180 GiB`

Live reproduction during investigation:

- `09:55:45`: `41.1 GiB RSS`
- `09:55:50`: `46.6 GiB RSS`
- `09:55:55`: `52.8 GiB RSS`

At the same time, the app logged:

- `ComputeCoChange: computing co-change groups for project 019cc564-775d-7bbf-96b8-8c35bf7f086d`

This tied the active memory climb directly to the co-change job.

## Runtime Evidence

`oban_jobs` showed repeated `ComputeCoChange` rows stuck in `executing` or later
ending up `discarded`, while `ComputeHeatmap` completed normally.

Representative state during investigation:

- job `252`: `ComputeCoChange`, `executing`, attempt `3`
- job `259`: `ComputeCoChange`, `executing`, attempt `2`
- job `264`: `ComputeCoChange`, `executing`, attempt `2`
- job `270`: `ComputeCoChange`, `executing`, attempt `2`

The `project_ingest_states` row for `handgemacht` had:

- `co_change_last_run_at = NULL`
- `heatmap_last_run_at` populated

That means co-change never completed a successful full run for this project,
while heatmap did.

## Root Cause

The incident is not caused by normal Phoenix memory use. It is caused by the
combination of scheduling behavior and an algorithm with unbounded intermediate
growth.

### 1. Co-change was enqueued too aggressively

`ComputeCoChange` is enqueued from hook-driven paths on normal developer
activity, including file snapshots and transcript sync downstream jobs.

### 2. Worker uniqueness was too weak

`ComputeCoChange` used:

- `unique: [keys: [:project_id], period: 30]`

That allows new work for the same project to be queued again while a previous
run is still executing for minutes.

### 3. Missing watermark forced full rebuilds

Because `co_change_last_run_at` stayed `NULL`, every run for `handgemacht`
fell back to the full rebuild path instead of delta mode.

### 4. Full rebuild is combinatorial

`CoChangeIntersections` does all-pairs commit set intersections and then expands
intersections into all subsets of size `>= 2`.

That creates explosive intermediate state on repositories with large commits.

### 5. Repository shape was enough to trigger it

For `/home/marco/projects/handgemacht` over the last 30 days:

- commits: `180`
- file entries: `1977`
- average files per commit: about `11`
- largest commits observed: `122`, `87`, `75`, `69`, `63` files

Those larger commits make subset expansion especially dangerous.

## Why This Was Not Primarily a Transcript Problem

The active session inspected during the incident had a transcript around
`1.1 MiB`, and its `session_end` sync inserted about `1,438` messages.

Transcript parsing is still memory-heavy and should be revisited separately,
but the live memory growth matched `ComputeCoChange` directly and repeatedly.

## Containment Applied

As immediate containment in development:

- disabled co-change enqueue from hook paths
- disabled co-change enqueue from transcript sync downstream jobs
- made the `ComputeCoChange` worker return early when co-change is disabled
- set `config :spotter, co_change_enabled: false` in `config/dev.exs`

This is a stopgap, not a fix.

## Required Follow-Up

Tracked in `le-bdy`.

The permanent fix needs all of the following:

- prevent overlapping co-change work per project
- stop enqueue storms from normal hook activity
- make first-run bootstrap bounded in memory
- replace subset expansion with a bounded algorithm
- add failure telemetry that survives process crashes
- add explicit guardrails for large commits and large candidate sets

## Code Areas Involved

- `lib/spotter/transcripts/jobs/compute_co_change.ex`
- `lib/spotter/services/co_change_calculator.ex`
- `lib/spotter/services/co_change_intersections.ex`
- `lib/spotter/transcripts/jobs/sync_transcripts.ex`
- `lib/spotter_web/controllers/hooks_controller.ex`
