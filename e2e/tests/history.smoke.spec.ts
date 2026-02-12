import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";

test("history smoke renders and captures full-page snapshot", async ({ page }) => {
  await page.goto("/history");
  await waitForLiveViewReady(page, "history-root");

  await expect(page.getByTestId("history-root")).toBeVisible();

  await prepareFullPageSnapshot(page);
  await expect(page).toHaveScreenshot("history-smoke.png", {
    fullPage: true,
    animations: "disabled",
    maxDiffPixelRatio: 0.001,
  });
});
