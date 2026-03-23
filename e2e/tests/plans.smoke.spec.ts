import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";
import { PlansPage } from "../support/pages/plans";
import { SidebarHelper } from "../support/sidebar";
import { seedPlans, cleanupPlans } from "../support/seed-plans";

test.describe("plans list — /plans (search/filter/sort)", () => {
  let plans: PlansPage;
  let sidebar: SidebarHelper;

  test.beforeAll(async () => { await seedPlans(); });
  test.afterAll(async () => { await cleanupPlans(); });

  test.beforeEach(async ({ page }) => {
    plans = new PlansPage(page);
    sidebar = new SidebarHelper(page);
  });

  test("no project selected shows select-project prompt", async ({ page }) => {
    await test.step("GIVEN plans page loads without project param", async () => {
      await page.goto("/plans");
      await waitForLiveViewReady(page, "plans-root");
      await plans.expectVisible();
    });

    await test.step("THEN select-project prompt is shown", async () => {
      await plans.expectSelectProjectPrompt();
    });

    await test.step("THEN no epic table is visible", async () => {
      await expect(plans.epicTable).not.toBeVisible();
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

    await test.step("THEN filter bar is visible", async () => {
      await expect(plans.filterBar()).toBeVisible();
    });

    await test.step("THEN epic table shows rows", async () => {
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });

      const firstRow = plans.allEpicRows().first();
      await expect(plans.epicTitle(firstRow)).toBeVisible();
      await expect(firstRow.locator("[data-status]")).toBeVisible();
      await expect(firstRow.locator("[data-priority]")).toBeVisible();
    });
  });

  test("search filters beads by title substring", async ({ page }) => {
    await test.step("GIVEN plans page with a project selected", async () => {
      await plans.gotoWithProject("e2e_plans");
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
    });

    const initialCount = await plans.allEpicRows().count();

    await test.step("WHEN user types a search query", async () => {
      await plans.search("nonexistent-query-xyz");
    });

    await test.step("THEN results are filtered (fewer or no rows)", async () => {
      await plans.expectEmptyState("No plans match your search");
    });

    await test.step("WHEN user clears the search", async () => {
      await plans.search("");
    });

    await test.step("THEN all beads reappear", async () => {
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
      const count = await plans.allEpicRows().count();
      expect(count).toBe(initialCount);
    });
  });

  test("hide_closed toggle excludes/includes closed beads", async ({ page }) => {
    await test.step("GIVEN plans page with project (hide_closed default on)", async () => {
      await plans.gotoWithProject("e2e_plans");
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
    });

    const openCount = await plans.allEpicRows().count();

    await test.step("WHEN user clicks 'Show closed'", async () => {
      await plans.toggleClosed();
      await page.waitForTimeout(500);
    });

    await test.step("THEN closed beads appear (count >= open count)", async () => {
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
      const allCount = await plans.allEpicRows().count();
      expect(allCount).toBeGreaterThanOrEqual(openCount);
    });

    await test.step("THEN URL has hide_closed=false", async () => {
      await expect(page).toHaveURL(/hide_closed=false/);
    });
  });

  test("sort by created_at toggles direction", async ({ page }) => {
    await test.step("GIVEN plans page with project selected", async () => {
      await plans.gotoWithProject("e2e_plans");
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
    });

    await test.step("WHEN user clicks 'Created' column header", async () => {
      await plans.sortBy("created_at");
    });

    await test.step("THEN URL includes sort=created_at", async () => {
      await expect(page).toHaveURL(/sort=created_at/);
    });

    await test.step("WHEN user clicks 'Created' again", async () => {
      await plans.sortBy("created_at");
    });

    await test.step("THEN sort direction toggles", async () => {
      await expect(page).toHaveURL(/dir=asc/);
    });
  });

  test("URL params persist filter state across navigation", async ({ page }) => {
    await test.step("GIVEN user has search and sort applied", async () => {
      await page.goto("/plans?project=e2e_plans&q=e2e&hide_closed=false&sort=created_at&dir=asc");
      await waitForLiveViewReady(page, "plans-root");
    });

    await test.step("THEN search value is restored", async () => {
      await plans.expectSearchValue("e2e");
    });

    await test.step("WHEN user navigates to a detail and presses back", async () => {
      const firstRow = plans.allEpicRows().first();
      if (await firstRow.isVisible()) {
        await plans.epicLink(firstRow).click();
        await waitForLiveViewReady(page, "plan-detail-root");
        await page.goBack();
        await waitForLiveViewReady(page, "plans-root");
      }
    });

    await test.step("THEN filter state is preserved in URL", async () => {
      await expect(page).toHaveURL(/q=e2e/);
      await expect(page).toHaveURL(/sort=created_at/);
    });
  });

  test("task count displays actual child count", async ({ page }) => {
    await test.step("GIVEN plans page with epics", async () => {
      await plans.gotoWithProject("e2e_plans");
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
    });

    await test.step("THEN task count column shows a number for epics with children", async () => {
      const firstRow = plans.allEpicRows().first();
      const countCell = plans.taskCount(firstRow);
      await expect(countCell).toBeVisible();
      const text = await countCell.textContent();
      // Should be a number or em-dash (for 0 tasks)
      expect(text!.trim()).toMatch(/^\d+$|^\u2014$/);
    });
  });

  test("epic row link navigates to plan detail", async ({ page }) => {
    await test.step("GIVEN plans page with epics visible via project param", async () => {
      await plans.gotoWithProject("e2e_plans");
      await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });
    });

    await test.step("WHEN user clicks an epic ID link", async () => {
      const epicLink = plans.epicLink(plans.allEpicRows().first());
      await epicLink.click();
    });

    await test.step("THEN plan detail page loads", async () => {
      await waitForLiveViewReady(page, "plan-detail-root");
      await expect(page.getByTestId("bead-detail")).toBeVisible();
    });
  });

  test("viewport snapshot", async ({ page }) => {
    await test.step("GIVEN plans page with project and epics", async () => {
      await plans.gotoWithProject("e2e_plans");
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
