import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot } from "../support/liveview";
import { LanesPage } from "../support/pages/lanes";

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

  test("overlap regions are present", async () => {
    await lanes.expectOverlapsPresent();
  });

  test("time axis is visible", async () => {
    await expect(lanes.timeAxis).toBeVisible();
  });

  test("full-page visual snapshot", async ({ page }) => {
    await prepareFullPageSnapshot(page);
    await expect(page).toHaveScreenshot("session-lanes-smoke.png", {
      fullPage: true,
      animations: "disabled",
      maxDiffPixelRatio: 0.001,
    });
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
