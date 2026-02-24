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

  test("renders correct number of agent headers", async () => {
    await lanes.expectAgentHeaderCount(3);
  });

  test("lane agent names match fixture data", async () => {
    await lanes.expectLaneName(AGENTS.lead.name, AGENTS.lead.name);
    await lanes.expectLaneName(AGENTS.qa.name, AGENTS.qa.name);
    await lanes.expectLaneName(AGENTS.impl.name, AGENTS.impl.name);
  });

  test("agent header durations match deterministic fixture timing", async () => {
    await lanes.expectAgentHeaderDuration(
      AGENTS.lead.name,
      AGENTS.lead.duration,
    );
    await lanes.expectAgentHeaderDuration(AGENTS.qa.name, AGENTS.qa.duration);
    await lanes.expectAgentHeaderDuration(
      AGENTS.impl.name,
      AGENTS.impl.duration,
    );
  });

  test("time header column is visible", async () => {
    await lanes.expectTimeHeaderVisible();
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

  test("s0p.2 telemetry: render_lane emits spans per agent with correct attributes", async () => {
    // Wait for lanes to fully render — spans are emitted during page load
    await lanes.expectAgentHeaderCount(3);

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

      expect(
        agentName,
        "Span must include lane_agent_name attribute",
      ).toBeDefined();

      expect(
        msgCount,
        "Span must include message_count attribute",
      ).toBeDefined();
      expect(
        Number(msgCount!.value),
        "message_count must be positive",
      ).toBeGreaterThan(0);

      expect(
        span.duration,
        "Span should have a positive duration",
      ).toBeGreaterThan(0);
    }
  });
});

test.describe("session-lanes CSS layout", () => {
  let lanes: LanesPage;

  test.beforeEach(async ({ page }) => {
    lanes = new LanesPage(page);
    await lanes.goto(TEAM_SESSION_ID);
    await lanes.switchToLanesView();
  });

  test("grid container uses CSS Grid display", async () => {
    await lanes.expectGridLayout();
  });

  test("agent headers are arranged side-by-side", async () => {
    await lanes.expectAgentHeadersSideBySide();
  });

  test("grid is horizontally scrollable when lanes overflow viewport", async () => {
    await lanes.expectGridHorizontallyScrollable();
  });
});

const AGENT_NAMES = [AGENTS.lead.name, AGENTS.qa.name, AGENTS.impl.name];

test.describe("session-lanes table grid", () => {
  let lanes: LanesPage;

  test.beforeEach(async ({ page }) => {
    lanes = new LanesPage(page);
    await lanes.goto(TEAM_SESSION_ID);
    await lanes.switchToLanesView();
  });

  test("grid element exists with data-testid", async () => {
    await expect(lanes.grid()).toBeVisible();
  });

  test("sticky time column header is the first column", async () => {
    await lanes.expectTimeHeaderVisible();
    await lanes.expectTimeHeaderSticky();
  });

  test("agent header cells exist for each lane agent", async () => {
    await lanes.expectAgentHeaderCount(3);
    for (const name of AGENT_NAMES) {
      await expect(lanes.agentHeader(name)).toBeVisible();
    }
  });

  test("data rows render with lanes-row testid", async () => {
    await lanes.expectMinRowCount(1);
  });

  test("each row has cells per agent", async () => {
    await lanes.expectRowCellsPerAgent(AGENT_NAMES);
  });
});

test.describe("session-lanes collapsed messages", () => {
  let lanes: LanesPage;

  test.beforeEach(async ({ page }) => {
    lanes = new LanesPage(page);
    await lanes.goto(TEAM_SESSION_ID);
    await lanes.switchToLanesView();
  });

  test("messages render collapsed by default", async () => {
    await lanes.expectMessagesCollapsedByDefault();
  });

  test("collapsed messages show role and content preview", async () => {
    await lanes.expectCollapsedMessageContent();
  });

  test("clicking a collapsed message expands it", async () => {
    await lanes.clickToExpandFirstMessage();
  });
});

test.describe("session-lanes idle periods", () => {
  let lanes: LanesPage;

  test.beforeEach(async ({ page }) => {
    lanes = new LanesPage(page);
    await lanes.goto(TEAM_SESSION_ID);
    await lanes.switchToLanesView();
  });

  test("idle rows render with duration labels", async () => {
    await lanes.expectIdleRowsWithLabels();
  });
});

test.describe("session-lanes drag-and-drop reordering", () => {
  let lanes: LanesPage;

  test.beforeEach(async ({ page }) => {
    lanes = new LanesPage(page);
    await lanes.goto(TEAM_SESSION_ID);
    await lanes.switchToLanesView();
  });

  test("drag handle visible on agent header hover", async () => {
    await lanes.expectDragHandleOnHover(AGENTS.lead.name);
  });

  test("reorder via hook pushes new column order", async ({ page }) => {
    // Verify initial order
    await lanes.expectAgentOrder(AGENT_NAMES);

    // Get current session IDs from DOM
    const sessionIds = await lanes.getAgentSessionIdOrder();
    expect(sessionIds.length).toBe(3);

    // Reverse the order programmatically (simulates SortableJS onEnd callback)
    const reversed = [...sessionIds].reverse();
    await lanes.reorderColumnsViaHook(reversed);

    // Verify the order changed
    const newOrder = await lanes.getAgentHeaderOrder();
    expect(newOrder).toEqual([...AGENT_NAMES].reverse());
  });

  test("reset order button restores original order", async () => {
    // Get session IDs and reorder programmatically
    const sessionIds = await lanes.getAgentSessionIdOrder();
    await lanes.reorderColumnsViaHook([...sessionIds].reverse());

    // Reset button should be visible after reorder
    await lanes.expectResetOrderVisible();
    await lanes.resetOrderButton().click();

    // Order should be restored
    await lanes.expectAgentOrder(AGENT_NAMES);
  });

  test("column order persists in localStorage after reorder", async ({
    page,
  }) => {
    // Get session IDs and reorder
    const sessionIds = await lanes.getAgentSessionIdOrder();
    const reversed = [...sessionIds].reverse();
    await lanes.reorderColumnsViaHook(reversed);

    // Check localStorage was set
    const stored = await page.evaluate((teamSessionId) => {
      const key = `spotter:lane-order:${teamSessionId}`;
      const raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : null;
    }, TEAM_SESSION_ID);

    expect(stored, "localStorage should contain reordered session IDs").toEqual(
      reversed,
    );
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

test.describe("session-lanes inter-agent connectors and drawer", () => {
  let lanes: LanesPage;

  test.beforeEach(async ({ page }) => {
    lanes = new LanesPage(page);
    await lanes.goto(TEAM_SESSION_ID);
    await lanes.switchToLanesView();
  });

  test("inter-agent message link badges are rendered", async () => {
    await lanes.expectMinBadgeCount(2);
    // Both sent and received badges should exist
    const sentCount = await lanes.badgesByDirection("sent").count();
    const receivedCount = await lanes.badgesByDirection("received").count();
    expect(sentCount, "should have sent badges").toBeGreaterThanOrEqual(1);
    expect(receivedCount, "should have received badges").toBeGreaterThanOrEqual(
      1,
    );
  });

  test("badge hover shows SVG connector line and highlights receiver cell", async () => {
    const sentBadge = lanes.badgesByDirection("sent").first();
    await expect(sentBadge).toBeVisible();

    // No connector lines before hover
    await lanes.expectNoConnectorLines();

    // Hover the sent badge
    await sentBadge.hover();
    // Wait for debounce (100ms) + render
    await lanes.page.waitForTimeout(200);

    await lanes.expectConnectorLineVisible();
    await lanes.expectHighlightedCell();
  });

  test("badge click opens drawer with peer name and preview", async () => {
    await lanes.expectDrawerHidden();

    // Click a sent badge (implementer → qa-tester)
    const sentBadge = lanes.badgesByDirection("sent").first();
    await sentBadge.click();

    // Drawer should open with direction and peer info
    await expect(lanes.drawer()).toBeVisible();
    const directionText = await lanes.drawerDirection().textContent();
    const peerText = await lanes.drawerPeer().textContent();
    const previewText = await lanes.drawerPreview().textContent();

    expect(
      directionText,
      "drawer should show direction label",
    ).toBeTruthy();
    expect(peerText, "drawer should show peer name").toBeTruthy();
    expect(
      previewText && previewText.length > 0,
      "drawer should show preview text",
    ).toBe(true);
  });

  test("clicking drawer close button hides the drawer", async () => {
    // Open the drawer
    const sentBadge = lanes.badgesByDirection("sent").first();
    await sentBadge.click();
    await expect(lanes.drawer()).toBeVisible();

    // Close it
    await lanes.drawerCloseButton().click();
    await lanes.expectDrawerHidden();
  });

  test("clicking outside the drawer closes it", async ({ page }) => {
    // Open the drawer
    const sentBadge = lanes.badgesByDirection("sent").first();
    await sentBadge.click();
    await expect(lanes.drawer()).toBeVisible();

    // Click on an empty area (the lanes panel itself)
    await lanes.panel.click({ position: { x: 10, y: 10 } });
    await lanes.expectDrawerHidden();
  });
});
