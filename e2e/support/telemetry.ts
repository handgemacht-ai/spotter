import { expect } from "@playwright/test";

const JAEGER_BASE_URL = process.env.JAEGER_URL ?? "http://localhost:14686";
const OTEL_SERVICE = process.env.OTEL_SERVICE_NAME ?? "unknown_service:erl";

interface JaegerTag {
  key: string;
  type: string;
  value: string | number | boolean;
}

interface JaegerSpan {
  operationName: string;
  tags: JaegerTag[];
  spanID: string;
  traceID: string;
  startTime: number;
  duration: number;
}

interface JaegerTrace {
  traceID: string;
  spans: JaegerSpan[];
}

interface JaegerResponse {
  data: JaegerTrace[];
  errors: unknown;
}

/**
 * Query Jaeger for traces matching an operation within a recent time window.
 */
export async function queryTraces(
  operation: string,
  opts: { lookback?: string; limit?: number } = {},
): Promise<JaegerTrace[]> {
  const lookback = opts.lookback ?? "5m";
  const limit = opts.limit ?? 20;

  const url = new URL(`${JAEGER_BASE_URL}/api/traces`);
  url.searchParams.set("service", OTEL_SERVICE);
  url.searchParams.set("operation", operation);
  url.searchParams.set("lookback", lookback);
  url.searchParams.set("limit", String(limit));

  const res = await fetch(url.toString());
  if (!res.ok) {
    throw new Error(`Jaeger query failed: ${res.status} ${res.statusText}`);
  }

  const body = (await res.json()) as JaegerResponse;
  return body.data ?? [];
}

/**
 * Find all spans with a given operation name across returned traces.
 */
export function findSpans(traces: JaegerTrace[], operation: string): JaegerSpan[] {
  return traces.flatMap((t) => t.spans.filter((s) => s.operationName === operation));
}

/**
 * Get a tag value from a span by key.
 */
export function getTagValue(span: JaegerSpan, key: string): string | number | boolean | undefined {
  const tag = span.tags.find((t) => t.key === key);
  return tag?.value;
}

async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Poll Jaeger until at least `minCount` spans appear for the operation,
 * or timeout after `timeoutMs` (default 8s). Polls every 1s.
 */
async function pollForSpans(
  operation: string,
  minCount: number,
  opts: { lookback?: string; timeoutMs?: number } = {},
): Promise<JaegerSpan[]> {
  const timeoutMs = opts.timeoutMs ?? 8000;
  const pollInterval = 1000;
  const deadline = Date.now() + timeoutMs;

  let spans: JaegerSpan[] = [];
  while (Date.now() < deadline) {
    const traces = await queryTraces(operation, { lookback: opts.lookback });
    spans = findSpans(traces, operation);
    if (spans.length >= minCount) return spans;
    await sleep(pollInterval);
  }

  return spans;
}

/**
 * Assert that at least one span exists for the given operation with the expected attributes.
 * Polls Jaeger with retry to handle OTEL batch exporter flush latency.
 */
export async function assertSpanEmitted(
  operation: string,
  expectedAttrs: Record<string, string | number | boolean>,
  opts: { lookback?: string } = {},
): Promise<JaegerSpan> {
  const spans = await pollForSpans(operation, 1, { lookback: opts.lookback });

  expect(spans.length, `Expected at least one '${operation}' span in Jaeger`).toBeGreaterThan(0);

  const matching = spans.find((span) =>
    Object.entries(expectedAttrs).every(([key, value]) => getTagValue(span, key) === value),
  );

  expect(
    matching,
    `Expected '${operation}' span with attributes ${JSON.stringify(expectedAttrs)}. ` +
      `Found ${spans.length} span(s) but none matched. ` +
      `Actual attributes: ${JSON.stringify(spans.map((s) => s.tags.map((t) => `${t.key}=${t.value}`)))}`,
  ).toBeDefined();

  return matching!;
}

/**
 * Assert that multiple spans exist for the given operation, each matching a set of attributes.
 * Polls Jaeger with retry to handle OTEL batch exporter flush latency.
 */
export async function assertSpansEmitted(
  operation: string,
  expectedSets: Record<string, string | number | boolean>[],
  opts: { lookback?: string } = {},
): Promise<JaegerSpan[]> {
  const spans = await pollForSpans(operation, expectedSets.length, { lookback: opts.lookback });

  expect(
    spans.length,
    `Expected at least ${expectedSets.length} '${operation}' span(s) in Jaeger, found ${spans.length}`,
  ).toBeGreaterThanOrEqual(expectedSets.length);

  const matched: JaegerSpan[] = [];
  for (const attrs of expectedSets) {
    const match = spans.find(
      (span) =>
        !matched.includes(span) &&
        Object.entries(attrs).every(([key, value]) => getTagValue(span, key) === value),
    );

    expect(
      match,
      `Expected '${operation}' span with attributes ${JSON.stringify(attrs)}. ` +
        `Found ${spans.length} span(s) but no unmatched span fits.`,
    ).toBeDefined();

    matched.push(match!);
  }

  return matched;
}
