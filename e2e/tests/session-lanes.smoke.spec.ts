import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";

test("team lanes smoke renders parallel lanes and captures full-page snapshot", async ({ page }) => {
  // Navigate directly to the known team-lead session from team-overlap fixtures
  const teamSessionId = "00000000-0000-0000-0000-000000000001";
  await page.goto(`/sessions/${teamSessionId}`);
  await waitForLiveViewReady(page, "session-root");

  // Assert view-mode-toggle is visible (confirms team session detected)
  const viewModeToggle = page.getByTestId("view-mode-toggle");
  await expect(viewModeToggle).toBeVisible();

  // Click "Lanes" button to switch to lanes view
  await viewModeToggle.getByText("Lanes").click();

  // Assert lanes container is visible
  const lanesContainer = page.locator(".lanes-container");
  await expect(lanesContainer).toBeVisible();

  // Assert at least 3 lane columns visible (team-lead, qa-tester, implementer)
  const laneColumns = page.locator(".lanes-column");
  await expect(laneColumns).toHaveCount(3, { timeout: 10_000 });

  await prepareFullPageSnapshot(page);
  await expect(page).toHaveScreenshot("session-lanes-smoke.png", {
    fullPage: true,
    animations: "disabled",
    maxDiffPixelRatio: 0.001,
  });
});
