import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot } from "../support/liveview";
import { LanesPage } from "../support/pages/lanes";
import { assertSpansEmitted } from "../support/telemetry";

/**
 * Deterministic fixture data (test/fixtures/transcripts/team-overlap/):
 *   team-lead:    10:00 – 10:30 (30m, session 001)
 *   qa-tester:    10:05 – 10:20 (15m, session 002)
 *   implementer:  10:10 – 10:30 (20m, session 003)
 */
const TEAM_SESSION_ID = "00000000-0000-0000-0000-000000000001";

const AGENTS = {
  lead: { name: "team-lead", duration: /30m/ },
  qa: { name: "qa-tester", duration: /15m/ },
  impl: { name: "implementer", duration: /20m/ },
} as const;

test.describe("session-lanes", () => {
  let lanes: LanesPage;

  test.beforeEach(async ({ page }) => {
    lanes = new LanesPage(page);
    await lanes.goto(TEAM_SESSION_ID);
    await lanes.switchToLanesView();
  });

  test("renders correct number of lane columns", async () => {
    await lanes.expectColumnCount(3);
  });

  test("lane agent names match fixture data", async () => {
    await lanes.expectLaneName(AGENTS.lead.name, AGENTS.lead.name);
    await lanes.expectLaneName(AGENTS.qa.name, AGENTS.qa.name);
    await lanes.expectLaneName(AGENTS.impl.name, AGENTS.impl.name);
  });

  test("lane durations match deterministic fixture timing", async () => {
    await lanes.expectLaneDuration(AGENTS.lead.name, AGENTS.lead.duration);
    await lanes.expectLaneDuration(AGENTS.qa.name, AGENTS.qa.duration);
    await lanes.expectLaneDuration(AGENTS.impl.name, AGENTS.impl.duration);
  });

  test("no time axis is rendered (independent scrollable panels)", async ({
    page,
  }) => {
    await expect(page.getByTestId("lanes-time-axis")).toHaveCount(0);
  });

  test("lane columns are independently scrollable", async () => {
    await lanes.expectColumnsIndependentlyScrollable();
  });

  test("full-page visual snapshot", async ({ page }) => {
    await prepareFullPageSnapshot(page);
    await expect(page).toHaveScreenshot("session-lanes-smoke.png", {
      fullPage: true,
      animations: "disabled",
      maxDiffPixelRatio: 0.01,
    });
  });
});

test.describe("session-lanes telemetry", () => {
  let lanes: LanesPage;

  test.beforeEach(async ({ page }) => {
    lanes = new LanesPage(page);
    await lanes.goto(TEAM_SESSION_ID);
    await lanes.switchToLanesView();
  });

  test("s0p.2 telemetry: render_lane emits spans per agent with correct attributes", async ({
    page,
  }) => {
    // Wait for lanes to fully render — spans are emitted during page load
    await lanes.expectColumnCount(3);

    // Verify one render_lane span per agent with required attributes (polls Jaeger with retry)
    const spans = await assertSpansEmitted(
      "spotter.lanes.render_lane",
      [
        { lane_agent_name: AGENTS.lead.name },
        { lane_agent_name: AGENTS.qa.name },
        { lane_agent_name: AGENTS.impl.name },
      ],
      { lookback: "5m" },
    );

    // Each span must have session_id and message_count attributes
    for (const span of spans) {
      const sessionId = span.tags.find((t) => t.key === "session_id");
      const agentName = span.tags.find((t) => t.key === "lane_agent_name");
      const msgCount = span.tags.find((t) => t.key === "message_count");

      expect(sessionId, "Span must include session_id attribute").toBeDefined();
      expect(
        String(sessionId!.value),
        "session_id must be a valid UUID",
      ).toMatch(/^[0-9a-f-]{36}$/);

      expect(agentName, "Span must include lane_agent_name attribute").toBeDefined();

      expect(msgCount, "Span must include message_count attribute").toBeDefined();
      expect(
        Number(msgCount!.value),
        "message_count must be positive",
      ).toBeGreaterThan(0);

      expect(span.duration, "Span should have a positive duration").toBeGreaterThan(0);
    }
  });
});

test.describe("session-lanes responsive tabs", () => {
  test.use({ viewport: { width: 768, height: 900 } });

  let lanes: LanesPage;

  test.beforeEach(async ({ page }) => {
    lanes = new LanesPage(page);
    await lanes.goto(TEAM_SESSION_ID);
    await lanes.switchToLanesView();
  });

  test("tab bar is visible at narrow viewport", async () => {
    await lanes.expectTabCount(3);
  });

  test("first tab is active by default", async () => {
    await lanes.expectTabActive(AGENTS.lead.name);
  });

  test("clicking a tab switches the active lane", async () => {
    await lanes.clickTab(AGENTS.qa.name);
    await lanes.expectTabActive(AGENTS.qa.name);
  });
});
