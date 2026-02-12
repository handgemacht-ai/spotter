import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";

test("session smoke renders transcript and captures full-page snapshot", async ({ page }) => {
  await page.goto("/");
  await waitForLiveViewReady(page, "dashboard-root");

  const firstSessionRow = page.getByTestId("session-row").first();
  await expect(firstSessionRow).toBeVisible();

  const sessionId = await firstSessionRow.getAttribute("data-session-id");
  expect(sessionId).toBeTruthy();

  await page.goto(`/sessions/${sessionId}`);
  await waitForLiveViewReady(page, "session-root");

  await expect(page.getByTestId("transcript-container")).toBeVisible();
  await expect(page.getByTestId("transcript-row").first()).toBeVisible();

  await prepareFullPageSnapshot(page);
  await expect(page).toHaveScreenshot("session-smoke.png", {
    fullPage: true,
    animations: "disabled",
    maxDiffPixelRatio: 0.001,
  });
});
