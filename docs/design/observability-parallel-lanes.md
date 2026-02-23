# Observability Spec: Parallel Transcript Lanes

Feature: Parallel Transcript Lanes
Status: Review
Author: observability-manager

## Traces

### Backend Spans

| Span Name | Parent | Attributes | Notes |
|---|---|---|---|
| `spotter.parallel_lanes.compute` | request/LiveView span | `session_id: string`, `lane_count: integer`, `overlap_count: integer`, `timeline_duration_ms: integer`, `message_count: integer` | Wraps full `ParallelLanes.compute/1` call |
| `spotter.parallel_lanes.load_messages` | `compute` | `session_id: string`, `message_count: integer` | DB query for session messages |
| `spotter.parallel_lanes.load_subagents` | `compute` | `session_id: string`, `subagent_count: integer` | DB query for session subagents |
| `spotter.parallel_lanes.build_lanes` | `compute` | `lane_count: integer` | Grouping + lane struct construction |
| `spotter.parallel_lanes.overlap_regions` | `compute` | `overlap_count: integer` | Sweep-line overlap detection |

**Implementation notes:**
- Use `OpenTelemetry.Tracer.with_span/3` in `ParallelLanes.compute/1`
- On error, call `OpenTelemetry.Tracer.set_status(:error, reason)`
- Set attributes with `OpenTelemetry.Tracer.set_attribute/2` after values are computed
- The `load_messages` and `load_subagents` child spans are optional — Ash/Ecto auto-instrumentation may cover DB queries. Add only if the auto-spans don't carry enough context (session_id, counts).

### LiveView Spans

| Span Name | Parent | Attributes | Notes |
|---|---|---|---|
| `spotter.session_live.switch_view_mode` | LiveView request | `mode: string ("thread" \| "lanes")`, `session_id: string` | Fires on toggle click |

**Implementation note:** Use `SpotterWeb.OtelTraceHelpers.with_span` if available, otherwise `OpenTelemetry.Tracer.with_span`. The LiveView event handler for the toggle should wrap its logic in a span.

### Frontend (Browser)

No custom browser spans required. The JS `LaneScrollSync` hook is UI-only synchronization — no meaningful latency to trace. If scroll performance becomes an issue, add browser Performance API marks later.

## Metrics

| Type | Name | Labels | Description |
|---|---|---|---|
| Histogram | `spotter.parallel_lanes.compute.duration_ms` | `session_id` | Time to compute lane data (ms) |
| Counter | `spotter.parallel_lanes.compute.count` | — | Number of compute/1 invocations |
| Counter | `spotter.parallel_lanes.compute.error_count` | `error_type` | Compute failures |
| Histogram | `spotter.parallel_lanes.lane_count` | — | Distribution of lane counts per computation |
| Histogram | `spotter.parallel_lanes.overlap_count` | — | Distribution of overlap region counts |

**Implementation notes:**
- Use `:telemetry.execute/3` to emit events, configure OpenTelemetry metrics exporter to scrape them
- Alternatively, emit via `OpenTelemetry` metrics API if the project uses OTel metrics SDK
- `session_id` label on histogram is for debugging — drop it in production if cardinality is a concern

## Baggage

No new baggage keys required for this feature. The parallel lanes computation is:
- Single-service (no cross-service calls)
- Synchronous within a LiveView request
- Does not call external APIs

Existing `traceparent` propagation from Phoenix covers request correlation.

## Alerts

| Condition | Severity | Action |
|---|---|---|
| `spotter.parallel_lanes.compute.duration_ms` p99 > 2000ms | warn | Investigate slow session — likely high message count. Consider pagination or caching. |
| `spotter.parallel_lanes.compute.error_count` > 5 in 5min | critical | Check logs for `compute/1` failures. Likely data integrity issue (missing session, corrupt messages). |
| `spotter.parallel_lanes.compute.duration_ms` p99 > 5000ms | critical | Session rendering is degraded. Emergency: add caching layer or limit lane computation to recent messages. |

## Integration with Existing Task #13

Task #13 already specifies the top-level `spotter.parallel_lanes.compute` span. This spec extends it with:
- Child spans for DB queries and overlap detection (optional, add if debugging needs arise)
- LiveView toggle span
- Metrics definitions
- Alert thresholds

The architects should implement the **required** items (top-level compute span + metrics) first. Child spans and alerts are stretch goals for the initial implementation.

## Priority

**Must have (P0):**
- `spotter.parallel_lanes.compute` span with all attributes
- `spotter.parallel_lanes.compute.duration_ms` histogram
- `spotter.parallel_lanes.compute.error_count` counter

**Nice to have (P1):**
- Child spans for load_messages, load_subagents, overlap_regions
- `spotter.session_live.switch_view_mode` span
- Lane count and overlap count histograms
- Alert rules
