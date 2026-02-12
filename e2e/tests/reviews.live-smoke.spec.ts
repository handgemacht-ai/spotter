import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";

test("reviews live smoke launches conversation and captures full-page snapshot", async ({ page }) => {
  test.setTimeout(90_000);

  await page.goto("/reviews");
  await waitForLiveViewReady(page, "reviews-root");

  const projectButton = page
    .locator('button[phx-value-project-id]:not([phx-value-project-id="all"])')
    .first();

  await expect(projectButton).toBeVisible();
  await projectButton.click();

  const openConversationButton = page.getByRole("button", { name: "Open conversation" });
  await expect(openConversationButton).toBeVisible();
  await openConversationButton.click();

  await expect(page.getByText("Launched review session:", { exact: false })).toBeVisible();

  await prepareFullPageSnapshot(page);
  await expect(page).toHaveScreenshot("reviews-live-smoke.png", {
    fullPage: true,
    animations: "disabled",
    maxDiffPixelRatio: 0.001,
  });
});
