import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";

test("reviews live smoke shows MCP review instructions and captures full-page snapshot", async ({ page }) => {
  test.setTimeout(90_000);

  await page.goto("/reviews");
  await waitForLiveViewReady(page, "reviews-root");

  const instructionPanel = page.getByTestId("mcp-review-instructions");
  await expect(instructionPanel).toBeVisible();
  await expect(instructionPanel.getByRole("heading", { name: "Review in Claude Code" })).toBeVisible();

  await prepareFullPageSnapshot(page);
  await expect(page).toHaveScreenshot("reviews-live-smoke.png", {
    fullPage: true,
    animations: "disabled",
    maxDiffPixelRatio: 0.001,
  });
});
