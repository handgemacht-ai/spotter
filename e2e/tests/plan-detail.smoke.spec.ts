import { expect, test } from "@playwright/test";
import { prepareFullPageSnapshot, waitForLiveViewReady } from "../support/liveview";
import { PlansPage } from "../support/pages/plans";
import { PlanDetailPage } from "../support/pages/plan-detail";
import { seedPlans, cleanupPlans } from "../support/seed-plans";

/**
 * Helper: navigate from plans list to the first epic's detail page.
 * Returns the project name for back-navigation assertions.
 */
async function navigateToFirstEpic(
  page: import("@playwright/test").Page,
  plans: PlansPage,
  detail: PlanDetailPage,
): Promise<string> {
  await plans.goto();
  const firstChip = plans.allProjectChips().first();
  const projectName = (await firstChip.getAttribute("data-project"))!;
  await firstChip.click();
  await expect(plans.allEpicRows().first()).toBeVisible({ timeout: 5000 });

  const epicLink = plans.epicLink(plans.allEpicRows().first());
  await epicLink.click();
  await waitForLiveViewReady(page, "plan-detail-root");

  return projectName;
}

test.describe("plan detail — /plans/:project/:epic_id", () => {
  let plans: PlansPage;
  let detail: PlanDetailPage;

  test.beforeAll(async () => { await seedPlans(); });
  test.afterAll(async () => { await cleanupPlans(); });

  test.beforeEach(async ({ page }) => {
    plans = new PlansPage(page);
    detail = new PlanDetailPage(page);
  });

  test("epic detail loads with rendered markdown sections", async ({ page }) => {
    await test.step("GIVEN an epic is clicked from plans list", async () => {
      await navigateToFirstEpic(page, plans, detail);
    });

    await test.step("THEN detail view shows epic header with title", async () => {
      await expect(detail.epicDetail()).toBeVisible();
      await expect(detail.epicTitle()).toBeVisible();
      const title = await detail.epicTitle().textContent();
      expect(title!.length).toBeGreaterThan(0);
    });

    await test.step("THEN status and priority badges are shown", async () => {
      await expect(detail.statusBadge()).toBeVisible();
      await expect(detail.priorityBadge()).toBeVisible();
    });

    await test.step("THEN parsed markdown sections are rendered", async () => {
      const sectionCount = await detail.allSectionHeadings().count();
      expect(
        sectionCount,
        "expected at least 1 section heading from parsed markdown",
      ).toBeGreaterThanOrEqual(1);
    });
  });

  test("mermaid diagram element present", async ({ page }) => {
    await test.step("GIVEN an epic with mermaid in its description", async () => {
      await navigateToFirstEpic(page, plans, detail);
    });

    await test.step("THEN mermaid block element is rendered", async () => {
      await detail.expectMermaidBlockCount(1);
    });

    await test.step("THEN mermaid block has data-mermaid-source attribute", async () => {
      const block = detail.allMermaidBlocks().first();
      const source = await block.getAttribute("data-mermaid-source");
      expect(source, "data-mermaid-source must be set").toBeTruthy();
      expect(source).toContain("graph");
    });
  });

  test("acceptance criteria table rendered", async ({ page }) => {
    await test.step("GIVEN an epic with acceptance tests", async () => {
      await navigateToFirstEpic(page, plans, detail);
    });

    await test.step("THEN GIVEN/WHEN/THEN table is visible", async () => {
      await expect(detail.acceptanceTable()).toBeVisible();
    });

    await test.step("THEN table has correct headers", async () => {
      const headers = detail.acceptanceTable().locator("thead th");
      await expect(headers).toHaveCount(3);
      await expect(headers.nth(0)).toHaveText("GIVEN");
      await expect(headers.nth(1)).toHaveText("WHEN");
      await expect(headers.nth(2)).toHaveText("THEN");
    });

    await test.step("THEN table has at least one criteria row", async () => {
      const rowCount = await detail.acceptanceRows().count();
      expect(rowCount).toBeGreaterThanOrEqual(1);
    });
  });

  test("child tasks listed and expandable", async ({ page }) => {
    await test.step("GIVEN an epic with children", async () => {
      await navigateToFirstEpic(page, plans, detail);
    });

    await test.step("THEN child tasks container is visible with task rows", async () => {
      await expect(detail.childTasksContainer()).toBeVisible();
      const taskCount = await detail.allChildTaskRows().count();
      expect(taskCount, "expected at least 1 child task").toBeGreaterThanOrEqual(1);
    });

    let taskId: string;

    await test.step("THEN each task row shows ID, title, status, priority", async () => {
      const firstTask = detail.allChildTaskRows().first();
      taskId = (await firstTask.getAttribute("data-task-id"))!;
      expect(taskId).toBeTruthy();

      await expect(firstTask.locator(".plan-task-id")).toBeVisible();
      await expect(firstTask.locator(".plan-task-title")).toBeVisible();
      await expect(firstTask.locator("[data-status]")).toBeVisible();
      await expect(firstTask.locator("[data-priority]")).toBeVisible();
    });

    await test.step("THEN task is collapsed by default", async () => {
      await detail.expectTaskCollapsed(taskId);
    });

    await test.step("WHEN user clicks toggle to expand", async () => {
      await detail.taskToggle(taskId).click();
    });

    await test.step("THEN task description is visible", async () => {
      await detail.expectTaskExpanded(taskId);
    });

    await test.step("WHEN user clicks toggle again to collapse", async () => {
      await detail.taskToggle(taskId).click();
    });

    await test.step("THEN task description is hidden", async () => {
      await detail.expectTaskCollapsed(taskId);
    });
  });

  test("text selection shows annotation form", async ({ page }) => {
    await test.step("GIVEN detail view with sections", async () => {
      await navigateToFirstEpic(page, plans, detail);
      await expect(detail.sectionsContainer()).toBeVisible();
    });

    await test.step("WHEN user selects text in a section", async () => {
      // Simulate text selection by selecting content in the first section body
      const firstSection = detail.sectionsContainer().locator(".plan-section").first();
      const sectionBody = firstSection.locator(".plan-section-body p").first();
      await expect(sectionBody).toBeVisible();

      // Use triple-click to select the paragraph text
      await sectionBody.click({ clickCount: 3 });

      // Dispatch the PlanHighlighter hook's expected event via the LiveSocket
      await page.evaluate(() => {
        const sections = document.getElementById("plan-sections");
        if (!sections) throw new Error("plan-sections not found");

        const liveSocket = (window as any).liveSocket;
        if (!liveSocket) throw new Error("liveSocket not found");

        // Find the PlanHighlighter hook
        let hook: any = null;
        for (const viewId of Object.keys(liveSocket.roots)) {
          const view = liveSocket.roots[viewId];
          for (const hookId of Object.keys(view.viewHooks || {})) {
            const h = view.viewHooks[hookId];
            if (h.el === sections) {
              hook = h;
              break;
            }
          }
          if (hook) break;
        }

        if (!hook || !hook.pushEvent) {
          throw new Error("PlanHighlighter hook not found");
        }

        hook.pushEvent("plan_text_selected", {
          selected_text: "Plans Navigation feature for Spotter",
          section: "Overview",
        });
      });
    });

    await test.step("THEN annotation creation form appears", async () => {
      await expect(detail.selectionActive()).toBeVisible({ timeout: 3000 });
      // Form should contain the selected text preview
      const preview = detail.selectionActive().locator(".plan-annotation-selected-text");
      await expect(preview).toBeVisible();
      // Should have a textarea and save button
      await expect(detail.selectionActive().locator("textarea")).toBeVisible();
      await expect(
        detail.selectionActive().locator('button[type="submit"]'),
      ).toBeVisible();
    });
  });

  test("back navigation returns to plans list", async ({ page }) => {
    let projectName: string;

    await test.step("GIVEN user is on detail view", async () => {
      projectName = await navigateToFirstEpic(page, plans, detail);
    });

    await test.step("THEN back link is visible", async () => {
      await expect(detail.backLink()).toBeVisible();
      await expect(detail.backLink()).toContainText("Back to Plans");
    });

    await test.step("WHEN user clicks back link", async () => {
      await detail.backLink().click();
    });

    await test.step("THEN plans list loads with project still selected", async () => {
      await waitForLiveViewReady(page, "plans-root");
      await plans.expectChipActive(projectName);
    });
  });

  test("not-found state for invalid epic", async ({ page }) => {
    await test.step("GIVEN user navigates to a non-existent epic", async () => {
      await page.goto("/plans/spotter/nonexistent-epic-xyz");
      await waitForLiveViewReady(page, "plan-detail-root");
    });

    await test.step("THEN not-found empty state is displayed", async () => {
      await detail.expectNotFound();
    });
  });

  test("viewport snapshot", async ({ page }) => {
    await test.step("GIVEN detail view is loaded", async () => {
      await navigateToFirstEpic(page, plans, detail);
      await expect(detail.epicDetail()).toBeVisible();
    });

    await test.step("THEN full-page snapshot matches", async () => {
      await prepareFullPageSnapshot(page);
      await expect(page).toHaveScreenshot("plan-detail-smoke.png", {
        animations: "disabled",
        maxDiffPixelRatio: 0.02,
      });
    });
  });
});
