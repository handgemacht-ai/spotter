import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";

test.describe("sessions page", () => {
  test("navigating to /sessions renders session table", async ({ page }) => {
    await page.goto("/sessions");
    await waitForLiveViewReady(page, "sessions-root");

    const firstSessionRow = page.getByTestId("session-row").first();
    await expect(firstSessionRow).toBeVisible();

    await prepareFullPageSnapshot(page);
    await expect(page).toHaveScreenshot("sessions-page.png", {
      fullPage: true,
      animations: "disabled",
      maxDiffPixelRatio: 0.001,
    });
  });

  test("dashboard (/) does not render session table", async ({ page }) => {
    await page.goto("/");
    await waitForLiveViewReady(page, "dashboard-root");

    await expect(page.getByTestId("session-row")).toHaveCount(0);
  });

  test("sidebar Sessions link is present and active on /sessions", async ({ page }) => {
    await page.goto("/sessions");
    await waitForLiveViewReady(page, "sessions-root");

    const sessionsLink = page.locator('a.sidebar-link[data-nav-path="/sessions"]');
    await expect(sessionsLink).toBeVisible();
    await expect(sessionsLink).toHaveText(/Sessions/);
    await expect(sessionsLink).toHaveClass(/is-active/);

    // Dashboard link should NOT be active
    const dashboardLink = page.locator('a.sidebar-link[data-nav-path="/"]');
    await expect(dashboardLink).not.toHaveClass(/is-active/);
  });

  test("session detail /sessions/:session_id still resolves", async ({ page }) => {
    await page.goto("/sessions");
    await waitForLiveViewReady(page, "sessions-root");

    const firstSessionRow = page.getByTestId("session-row").first();
    await expect(firstSessionRow).toBeVisible();

    const sessionId = await firstSessionRow.getAttribute("data-session-id");
    expect(sessionId).toBeTruthy();

    await page.goto(`/sessions/${sessionId}`);
    await waitForLiveViewReady(page, "session-root");

    await expect(page.getByTestId("transcript-container")).toBeVisible();
    await expect(page.locator('[data-testid="transcript-row"]').first()).toBeAttached();
  });
});
