import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";

test("dashboard smoke uses stable selectors and full-page snapshot", async ({ page }) => {
  await page.goto("/");
  await waitForLiveViewReady(page, "dashboard-root");

  await expect(page.getByRole("button", { name: "Refresh" })).toBeVisible();
  await expect(page.getByTestId("session-row").first()).toBeVisible();

  await prepareFullPageSnapshot(page);
  await expect(page).toHaveScreenshot("dashboard-smoke.png", {
    fullPage: true,
    animations: "disabled",
    maxDiffPixelRatio: 0.001,
  });
});
