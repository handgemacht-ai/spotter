import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";
import { randomUUID } from "crypto";

const BASE_URL = process.env.SPOTTER_BASE_URL ?? "http://127.0.0.1:1110";

/** POST to session-start hook to create an ongoing session. */
async function triggerSessionStart(sessionId: string): Promise<void> {
  const res = await fetch(`${BASE_URL}/api/hooks/session-start`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      session_id: sessionId,
      pane_id: `pane-${sessionId.slice(0, 8)}`,
      cwd: "/tmp/e2e-dashboard-test",
    }),
  });
  expect(res.ok, `session-start hook failed: ${res.status}`).toBe(true);
}

/** POST to session-end hook to finish a session. */
async function triggerSessionEnd(sessionId: string): Promise<void> {
  const res = await fetch(`${BASE_URL}/api/hooks/session-end`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      session_id: sessionId,
      reason: "e2e-test",
    }),
  });
  expect(res.ok, `session-end hook failed: ${res.status}`).toBe(true);
}

test.describe("dashboard — ongoing sessions", () => {
  let sessionId: string;

  test.beforeEach(async () => {
    sessionId = randomUUID();
    await triggerSessionStart(sessionId);
  });

  test("shows ongoing sessions on /", async ({ page }) => {
    await page.goto("/");
    await waitForLiveViewReady(page, "dashboard-root");

    // At least the session we just created should appear
    const rows = page.getByTestId("dashboard-session-row");
    await expect(rows.first()).toBeVisible();

    // Our specific session should be in the table
    const ourRow = page.locator(
      `[data-testid="dashboard-session-row"][data-session-id="${sessionId}"]`,
    );
    await expect(ourRow).toBeVisible();

    // It should show "active" badge, not "finished"
    await expect(ourRow.locator(".session-status-active")).toBeVisible();
    await expect(ourRow.locator(".session-status-ended")).toHaveCount(0);
  });

  test("session start hook adds row live without refresh", async ({ page }) => {
    await page.goto("/");
    await waitForLiveViewReady(page, "dashboard-root");

    // Create a brand-new session while page is open
    const liveSessionId = randomUUID();
    await triggerSessionStart(liveSessionId);

    // The new row should appear via PubSub push — no page refresh needed
    const newRow = page.locator(
      `[data-testid="dashboard-session-row"][data-session-id="${liveSessionId}"]`,
    );
    await expect(newRow).toBeVisible({ timeout: 5000 });
    await expect(newRow.locator(".session-status-active")).toBeVisible();
  });

  test("session end marks row finished", async ({ page }) => {
    await page.goto("/");
    await waitForLiveViewReady(page, "dashboard-root");

    const ourRow = page.locator(
      `[data-testid="dashboard-session-row"][data-session-id="${sessionId}"]`,
    );
    await expect(ourRow).toBeVisible();
    await expect(ourRow.locator(".session-status-active")).toBeVisible();

    // End the session
    await triggerSessionEnd(sessionId);

    // Row should now show "finished" badge
    await expect(ourRow.locator(".session-status-ended")).toBeVisible({ timeout: 5000 });
    // Row should have the finished CSS class
    await expect(ourRow).toHaveClass(/dashboard-row-finished/);
  });

  test("refresh clears finished rows", async ({ page }) => {
    await page.goto("/");
    await waitForLiveViewReady(page, "dashboard-root");

    const ourRow = page.locator(
      `[data-testid="dashboard-session-row"][data-session-id="${sessionId}"]`,
    );
    await expect(ourRow).toBeVisible();

    // End the session — row stays visible but marked finished
    await triggerSessionEnd(sessionId);
    await expect(ourRow.locator(".session-status-ended")).toBeVisible({ timeout: 5000 });

    // Click Refresh — finished session should disappear (it's no longer ongoing)
    await page.getByRole("button", { name: "Refresh" }).click();

    // The row should be gone because the session now has session_ended_at set
    await expect(ourRow).toHaveCount(0, { timeout: 5000 });
  });

  test("hidden ongoing sessions are labeled", async ({ page }) => {
    // Navigate to sessions page and find the project filter for our session
    await page.goto("/sessions");
    await waitForLiveViewReady(page, "sessions-root");

    // Click the project filter button that contains our session's project
    // The cwd /tmp/e2e-dashboard-test creates a project named "e2e-dashboard-test"
    const projectButton = page.locator(".filter-btn", {
      hasText: "e2e-dashboard-test",
    });
    if (await projectButton.isVisible({ timeout: 3000 }).catch(() => false)) {
      await projectButton.click();
    }

    // Our session should appear in the visible list
    const sessionRow = page.locator(
      `[data-testid="session-row"][data-session-id="${sessionId}"]`,
    );
    await expect(sessionRow).toBeVisible({ timeout: 5000 });

    // Click the Hide button
    await sessionRow.getByRole("button", { name: "Hide" }).click();

    // Session should no longer be in visible rows
    await expect(sessionRow).toHaveCount(0, { timeout: 3000 });

    // Now check the dashboard — hidden ongoing session should still show with "hidden" badge
    await page.goto("/");
    await waitForLiveViewReady(page, "dashboard-root");

    const dashRow = page.locator(
      `[data-testid="dashboard-session-row"][data-session-id="${sessionId}"]`,
    );
    await expect(dashRow).toBeVisible();
    await expect(dashRow.locator(".session-status-inactive")).toBeVisible();
    await expect(dashRow.locator(".session-status-inactive")).toHaveText("hidden");
  });

  test("viewport snapshot", async ({ page }) => {
    await page.goto("/");
    await waitForLiveViewReady(page, "dashboard-root");

    await expect(
      page.getByTestId("dashboard-session-row").first(),
    ).toBeVisible();

    await prepareFullPageSnapshot(page);
    // Hide relative timestamps in the Started column to avoid snapshot drift
    await page.addStyleTag({
      content: `
        [data-testid="dashboard-root"] td:nth-child(4) {
          visibility: hidden !important;
        }
      `,
    });
    // Viewport-only snapshot (fixed 1440x900) avoids flakiness from
    // dynamic session count changing full-page height across runs.
    await expect(page).toHaveScreenshot("dashboard-smoke.png", {
      animations: "disabled",
      // Relaxed tolerance: other tests in this suite create sessions via hooks
      // which shift table content between runs. 2% covers row-count drift.
      maxDiffPixelRatio: 0.02,
    });
  });
});
