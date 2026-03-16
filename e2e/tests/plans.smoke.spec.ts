import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";
import { PlansPage } from "../support/pages/plans";
import { SidebarHelper } from "../support/sidebar";
import { seedPlans, cleanupPlans } from "../support/seed-plans";

test.describe("plans list — /plans (sidebar project selector)", () => {
  let plans: PlansPage;
  let sidebar: SidebarHelper;

  test.beforeAll(async () => { await seedPlans(); });
  test.afterAll(async () => { await cleanupPlans(); });

  test.beforeEach(async ({ page }) => {
    plans = new PlansPage(page);
    sidebar = new SidebarHelper(page);
  });

  test("local project chip filters are removed", async () => {
    await test.step("GIVEN plans page is loaded", async () => {
      await plans.goto();
      await plans.expectVisible();
    });

    await test.step("THEN no local project filter chips exist", async () => {
      await plans.expectNoProjectChips();
    });

    await test.step("THEN sidebar project selector is visible instead", async () => {
      await sidebar.expectVisible();
    });
  });

  test("no sidebar project selection shows all projects grouped with headers", async ({ page }) => {
    await test.step("GIVEN plans page loads without project param", async () => {
      await page.goto("/plans");
      await waitForLiveViewReady(page, "plans-root");
      await plans.expectVisible();
    });

    await test.step("THEN epics are grouped by project with section headers", async () => {
      await plans.expectGroupedByProject();
    });

    await test.step("THEN at least one project group header is rendered", async () => {
      await plans.expectProjectGroupHeaders(1);
    });

    await test.step("THEN epic rows appear under the group headers", async () => {
      const rowCount = await plans.allEpicRows().count();
      expect(rowCount, "expected at least 1 epic row").toBeGreaterThanOrEqual(1);
    });
  });

  test("sidebar project selection filters plans to single project", async ({ page }) => {
    let projectId: string;

    await test.step("GIVEN sidebar has projects available", async () => {
      await plans.goto();
      await plans.expectVisible();
      await sidebar.expectVisible();
    });

    await test.step("WHEN user selects a project via sidebar dropdown", async () => {
      projectId = await sidebar.getFirstProjectId();
      expect(projectId).toBeTruthy();
      await sidebar.selectProject(projectId);
    });

    await test.step("THEN page reloads with ?project= param", async () => {
      await waitForLiveViewReady(page, "plans-root");
      await expect(page).toHaveURL(/project=/);
    });

    await test.step("THEN epic table shows filtered rows (no group headers)", async () => {
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });

      const firstRow = plans.allEpicRows().first();
      await expect(plans.epicTitle(firstRow)).toBeVisible();
      await expect(firstRow.locator("[data-status]")).toBeVisible();
      await expect(firstRow.locator("[data-priority]")).toBeVisible();
    });

    await test.step("THEN no project group headers are visible (flat list)", async () => {
      await expect(plans.allProjectGroupHeaders()).toHaveCount(0);
    });
  });

  test("epic row link navigates to plan detail", async ({ page }) => {
    await test.step("GIVEN plans page with epics visible via sidebar project", async () => {
      await plans.goto();
      await plans.expectVisible();

      // Ensure we have epics — either grouped or filtered
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
    await test.step("GIVEN plans page with epics visible", async () => {
      await plans.goto();
      await plans.expectVisible();
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
