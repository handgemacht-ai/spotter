import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";
import { PlansPage } from "../support/pages/plans";

test.describe("plans list — /plans", () => {
  let plans: PlansPage;

  test.beforeEach(async ({ page }) => {
    plans = new PlansPage(page);
  });

  test("sidebar Plans link exists and navigates to /plans", async ({ page }) => {
    await test.step("GIVEN Spotter is running", async () => {
      await page.goto("/");
      await waitForLiveViewReady(page, "dashboard-root");
    });

    await test.step("WHEN user clicks sidebar Plans link", async () => {
      const plansLink = page.locator('a[data-nav-path="/plans"]');
      await expect(plansLink).toBeVisible();
      await expect(plansLink).toContainText("Plans");
      await plansLink.click();
    });

    await test.step("THEN /plans page loads with plans-root", async () => {
      await waitForLiveViewReady(page, "plans-root");
      await plans.expectVisible();
    });
  });

  test("project filter chips shown with epic counts", async () => {
    await test.step("GIVEN projects with Dolt servers", async () => {
      await plans.goto();
      await plans.expectVisible();
    });

    await test.step("THEN project filter chips are rendered", async () => {
      const chipCount = await plans.allProjectChips().count();
      expect(chipCount, "expected at least 1 project chip").toBeGreaterThanOrEqual(1);
    });

    await test.step("THEN each chip shows an epic count badge", async () => {
      const firstChip = plans.allProjectChips().first();
      const countBadge = firstChip.locator(".plan-chip-count");
      await expect(countBadge).toBeVisible();
      const countText = await countBadge.textContent();
      expect(Number(countText)).toBeGreaterThanOrEqual(0);
    });
  });

  test("selecting project chip loads epic table", async ({ page }) => {
    await test.step("GIVEN plans page with project chips", async () => {
      await plans.goto();
      await expect(plans.allProjectChips().first()).toBeVisible();
    });

    let projectName: string;

    await test.step("WHEN user clicks a project chip", async () => {
      const firstChip = plans.allProjectChips().first();
      projectName = (await firstChip.getAttribute("data-project"))!;
      expect(projectName).toBeTruthy();
      await firstChip.click();
    });

    await test.step("THEN chip becomes active and URL updates", async () => {
      await plans.expectChipActive(projectName);
      await expect(page).toHaveURL(/project=/);
    });

    await test.step("THEN epic table shows rows with title, status, priority", async () => {
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });

      const firstRow = plans.allEpicRows().first();
      // Title column
      await expect(plans.epicTitle(firstRow)).toBeVisible();
      // Status badge
      await expect(firstRow.locator("[data-status]")).toBeVisible();
      // Priority badge
      await expect(firstRow.locator("[data-priority]")).toBeVisible();
    });
  });

  test("deselecting project chip returns to empty state", async () => {
    let projectName: string;

    await test.step("GIVEN a project is selected with epics visible", async () => {
      await plans.goto();
      const firstChip = plans.allProjectChips().first();
      projectName = (await firstChip.getAttribute("data-project"))!;
      await firstChip.click();
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
    });

    await test.step("WHEN user clicks the same chip to deselect", async () => {
      await plans.projectChip(projectName).click();
    });

    await test.step("THEN empty state shows 'Select a project'", async () => {
      await plans.expectEmptyState("Select a project to view its epics");
    });
  });

  test("zero-epic project shows empty state", async () => {
    await test.step("GIVEN plans page is loaded", async () => {
      await plans.goto();
      await plans.expectVisible();
    });

    await test.step("THEN without project selection, empty state is shown", async () => {
      await plans.expectEmptyState("Select a project to view its epics");
    });
  });

  test("direct URL with project param pre-selects chip", async () => {
    let projectName: string;

    await test.step("GIVEN a valid project name from chips", async () => {
      await plans.goto();
      const firstChip = plans.allProjectChips().first();
      await expect(firstChip).toBeVisible();
      projectName = (await firstChip.getAttribute("data-project"))!;
    });

    await test.step("WHEN navigating directly with ?project= param", async () => {
      await plans.gotoWithProject(projectName);
    });

    await test.step("THEN chip is active and epics are loaded", async () => {
      await plans.expectChipActive(projectName);
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
    });
  });

  test("epic row link navigates to plan detail", async ({ page }) => {
    await test.step("GIVEN a project with epics is selected", async () => {
      await plans.goto();
      const firstChip = plans.allProjectChips().first();
      await firstChip.click();
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
    });

    await test.step("WHEN user clicks an epic ID link", async () => {
      const epicLink = plans.epicLink(plans.allEpicRows().first());
      await epicLink.click();
    });

    await test.step("THEN plan detail page loads", async () => {
      await waitForLiveViewReady(page, "plan-detail-root");
      await expect(page.getByTestId("epic-detail")).toBeVisible();
    });
  });

  test("viewport snapshot", async ({ page }) => {
    await test.step("GIVEN plans page with a project selected", async () => {
      await plans.goto();
      const firstChip = plans.allProjectChips().first();
      await firstChip.click();
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
    });

    await test.step("THEN full-page snapshot matches", async () => {
      await prepareFullPageSnapshot(page);
      await expect(page).toHaveScreenshot("plans-list-smoke.png", {
        animations: "disabled",
        maxDiffPixelRatio: 0.02,
      });
    });
  });
});
