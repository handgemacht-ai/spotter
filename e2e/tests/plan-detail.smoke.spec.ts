import { expect, test } from "@playwright/test";
import {
  prepareFullPageSnapshot,
  waitForLiveViewReady,
} from "../support/liveview";
import { PlansPage } from "../support/pages/plans";
import { PlanDetailPage } from "../support/pages/plan-detail";
import { seedPlans, cleanupPlans } from "../support/seed-plans";

const E2E_PROJECT = "e2e_plans";
const E2E_BEAD_ID = "e2e-epic-001";

async function navigateToTestBead(
  page: import("@playwright/test").Page,
  detail: PlanDetailPage,
): Promise<void> {
  await detail.goto(E2E_PROJECT, E2E_BEAD_ID);
}

async function pushPlanTextSelected(
  page: import("@playwright/test").Page,
  params: { selected_text: string; section: string; comment?: string },
): Promise<void> {
  await page.evaluate((p) => {
    const sections = document.getElementById("plan-sections");
    if (!sections) throw new Error("plan-sections not found");

    const liveSocket = (window as any).liveSocket;
    if (!liveSocket) throw new Error("liveSocket not found");

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
      throw new Error("PlanContentHook not found");
    }

    hook.pushEvent("plan_text_selected", p);
  }, params);
}

test.describe("plan detail — /plans/:project/:bead_id", () => {
  let plans: PlansPage;
  let detail: PlanDetailPage;

  test.beforeAll(async () => {
    await seedPlans();
  });
  test.afterAll(async () => {
    await cleanupPlans();
  });

  test.beforeEach(async ({ page }) => {
    plans = new PlansPage(page);
    detail = new PlanDetailPage(page);
  });

  test("bead detail loads with header and rendered markdown sections", async ({
    page,
  }) => {
    await test.step("GIVEN a bead detail page is loaded", async () => {
      await navigateToTestBead(page, detail);
    });

    await test.step("THEN bead detail container is visible", async () => {
      await expect(detail.beadDetail()).toBeVisible();
    });

    await test.step("THEN bead header shows type chip, ID, and title", async () => {
      await expect(detail.beadHeader()).toBeVisible();
      await detail.expectBeadType("epic");
      await detail.expectBeadId(E2E_BEAD_ID);
      const title = await detail.beadTitle().textContent();
      expect(title!.length).toBeGreaterThan(0);
    });

    await test.step("THEN status and priority badges are shown", async () => {
      await expect(detail.statusBadge()).toBeVisible();
      await expect(detail.priorityBadge()).toBeVisible();
    });

    await test.step("THEN parsed markdown sections are rendered with headings", async () => {
      await expect(detail.sectionsContainer()).toBeVisible();
      const sectionCount = await detail.allSectionHeadings().count();
      expect(
        sectionCount,
        "expected at least 1 section heading from parsed markdown",
      ).toBeGreaterThanOrEqual(1);
    });

    await test.step("THEN code blocks have syntax highlighting via hljs", async () => {
      const codeBlocks = detail.sectionsContainer().locator("pre code.hljs");
      const count = await codeBlocks.count();
      // Seed data may or may not have code blocks; if present, they should be highlighted
      if (count > 0) {
        await expect(codeBlocks.first()).toBeVisible();
      }
    });
  });

  test("acceptance cards with GIVEN/WHEN/THEN", async ({ page }) => {
    await test.step("GIVEN a bead with acceptance criteria", async () => {
      await navigateToTestBead(page, detail);
    });

    await test.step("THEN acceptance cards container is visible", async () => {
      await expect(detail.acceptanceCards()).toBeVisible();
    });

    await test.step("THEN at least one acceptance card is rendered", async () => {
      const cardCount = await detail.allAcceptanceCardItems().count();
      expect(
        cardCount,
        "expected at least 1 acceptance card",
      ).toBeGreaterThanOrEqual(1);
    });

    await test.step("THEN each card has GIVEN, WHEN, THEN labels", async () => {
      const firstCard = detail.allAcceptanceCardItems().first();
      await expect(firstCard.locator(".acceptance-given")).toBeVisible();
      await expect(firstCard.locator(".acceptance-when")).toBeVisible();
      await expect(firstCard.locator(".acceptance-then")).toBeVisible();
    });

    await test.step("THEN each card has values next to labels", async () => {
      const firstCard = detail.allAcceptanceCardItems().first();
      const values = firstCard.locator(".acceptance-value");
      await expect(values).toHaveCount(3);
      for (let i = 0; i < 3; i++) {
        const text = await values.nth(i).textContent();
        expect(
          text!.trim().length,
          `acceptance value ${i} should not be empty`,
        ).toBeGreaterThan(0);
      }
    });
  });

  test("classification chips displayed", async ({ page }) => {
    await test.step("GIVEN a bead with classification data in its description", async () => {
      // Seed epic description must include a ## Classification section with - Key: Value lines.
      // The seed controller needs to add this section for this test to pass.
      await navigateToTestBead(page, detail);
    });

    await test.step("THEN classification chips section is visible", async () => {
      await expect(detail.classificationChips()).toBeVisible();
    });

    await test.step("THEN chips have labels and badge values", async () => {
      const labels = detail
        .classificationChips()
        .locator(".bead-classification-label");
      const labelCount = await labels.count();
      expect(
        labelCount,
        "expected at least 1 classification label",
      ).toBeGreaterThanOrEqual(1);

      const badges = detail.classificationChips().locator(".badge");
      const badgeCount = await badges.count();
      expect(
        badgeCount,
        "expected at least 1 classification badge",
      ).toBeGreaterThanOrEqual(1);
    });
  });

  test("dependencies display with links on task bead", async ({ page }) => {
    const taskBeadId = "e2e-task-001";

    await test.step("GIVEN a task bead that depends on the epic", async () => {
      // Seed data: each task has depends_on_id=e2e-epic-001 (type: blocks)
      // So viewing a task bead should show the epic as a dependency
      await detail.goto(E2E_PROJECT, taskBeadId);
    });

    await test.step("THEN dependencies section is visible", async () => {
      await expect(detail.dependencyList()).toBeVisible();
    });

    await test.step("THEN dependency row shows the epic dependency", async () => {
      const rowCount = await detail.allDependencyRows().count();
      expect(
        rowCount,
        "expected at least 1 dependency row",
      ).toBeGreaterThanOrEqual(1);
    });

    await test.step("THEN dependency row has a navigable link with bead ID and title", async () => {
      const firstRow = detail.allDependencyRows().first();
      const link = firstRow.locator(".bead-dep-link");
      await expect(link).toBeVisible();
      const depId = firstRow.locator(".bead-dep-id");
      await expect(depId).toBeVisible();
      await expect(depId).toHaveText(E2E_BEAD_ID);
    });

    await test.step("THEN dependency row shows status badge and type", async () => {
      const firstRow = detail.allDependencyRows().first();
      await expect(firstRow.locator("[data-status]")).toBeVisible();
      await expect(firstRow.locator(".badge").last()).toBeVisible();
    });

    await test.step("WHEN user clicks the dependency link", async () => {
      const firstRow = detail.allDependencyRows().first();
      await firstRow.locator(".bead-dep-link").click();
    });

    await test.step("THEN navigates to the dependency bead detail", async () => {
      await waitForLiveViewReady(page, "plan-detail-root");
      await expect(detail.beadDetail()).toBeVisible();
      await detail.expectBeadId(E2E_BEAD_ID);
    });
  });

  test("child task navigation to bead detail", async ({ page }) => {
    await test.step("GIVEN an epic with child tasks", async () => {
      await navigateToTestBead(page, detail);
    });

    await test.step("THEN child tasks container is visible", async () => {
      await expect(detail.childTasksContainer()).toBeVisible();
    });

    await test.step("THEN child task rows are listed", async () => {
      const taskCount = await detail.allChildTaskRows().count();
      expect(
        taskCount,
        "expected at least 1 child task",
      ).toBeGreaterThanOrEqual(1);
    });

    await test.step("THEN each task row shows ID, title, status, priority", async () => {
      const firstTask = detail.allChildTaskRows().first();
      await expect(firstTask.locator(".plan-task-id")).toBeVisible();
      await expect(firstTask.locator(".plan-task-title")).toBeVisible();
      await expect(firstTask.locator("[data-status]")).toBeVisible();
      await expect(firstTask.locator("[data-priority]")).toBeVisible();
    });

    await test.step("WHEN user clicks a task link", async () => {
      const firstTaskId = await detail
        .allChildTaskRows()
        .first()
        .getAttribute("data-task-id");
      expect(firstTaskId).toBeTruthy();
      await detail.taskLink(firstTaskId!).click();
    });

    await test.step("THEN navigates to that task's bead detail page", async () => {
      await waitForLiveViewReady(page, "plan-detail-root");
      await expect(detail.beadDetail()).toBeVisible();
      // Should now be on a different bead (the task, not the epic)
      await expect(page).not.toHaveURL(new RegExp(E2E_BEAD_ID));
    });
  });

  test("any-bead navigation — non-epic bead loads detail", async ({ page }) => {
    const taskBeadId = "e2e-task-001";

    await test.step("GIVEN user navigates directly to a task bead", async () => {
      await detail.goto(E2E_PROJECT, taskBeadId);
    });

    await test.step("THEN bead detail loads for the task", async () => {
      await expect(detail.beadDetail()).toBeVisible();
      await detail.expectBeadId(taskBeadId);
      await detail.expectBeadType("task");
    });

    await test.step("THEN header shows task-specific data", async () => {
      await expect(detail.beadTitle()).toBeVisible();
      await expect(detail.statusBadge()).toBeVisible();
      await expect(detail.priorityBadge()).toBeVisible();
    });
  });

  test("annotation display section", async ({ page }) => {
    await test.step("GIVEN a bead detail page is loaded", async () => {
      await navigateToTestBead(page, detail);
    });

    await test.step("WHEN user creates an annotation via text selection", async () => {
      await expect(detail.sectionsContainer()).toBeVisible();

      await pushPlanTextSelected(page, {
        selected_text: "Plans Navigation feature for Spotter",
        section: "Overview",
        comment: "E2E test annotation",
      });
    });

    await test.step("THEN annotation section appears with the annotation", async () => {
      await expect(detail.annotationsSection()).toBeVisible({ timeout: 5000 });
    });
  });

  test("text selection shows annotation form", async ({ page }) => {
    await test.step("GIVEN detail view with sections", async () => {
      await navigateToTestBead(page, detail);
      await expect(detail.sectionsContainer()).toBeVisible();
    });

    await test.step("WHEN user selects text in a section", async () => {
      await pushPlanTextSelected(page, {
        selected_text: "Plans Navigation feature for Spotter",
        section: "Overview",
      });
    });

    await test.step("THEN annotation creation form appears", async () => {
      await expect(detail.selectionActive()).toBeVisible({ timeout: 3000 });
      const preview = detail
        .selectionActive()
        .locator(".plan-annotation-selected-text");
      await expect(preview).toBeVisible();
      await expect(detail.selectionActive().locator("textarea")).toBeVisible();
      await expect(
        detail.selectionActive().locator('button[type="submit"]'),
      ).toBeVisible();
    });
  });

  test("mermaid diagram element present", async ({ page }) => {
    await test.step("GIVEN a bead with mermaid in its description", async () => {
      await navigateToTestBead(page, detail);
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

  test("back navigation returns to plans list", async ({ page }) => {
    await test.step("GIVEN user is on detail view", async () => {
      await navigateToTestBead(page, detail);
    });

    await test.step("THEN back link is visible", async () => {
      await expect(detail.backLink()).toBeVisible();
      await expect(detail.backLink()).toContainText("Back to Plans");
    });

    await test.step("WHEN user clicks back link", async () => {
      await detail.backLink().click();
    });

    await test.step("THEN plans list loads", async () => {
      await waitForLiveViewReady(page, "plans-root");
      await plans.expectVisible();
    });
  });

  test("not-found state for invalid bead", async ({ page }) => {
    await test.step("GIVEN user navigates to a non-existent bead", async () => {
      await page.goto("/plans/e2e_plans/nonexistent-bead-xyz");
      await waitForLiveViewReady(page, "plan-detail-root");
    });

    await test.step("THEN not-found empty state is displayed", async () => {
      await detail.expectNotFound();
    });
  });

  test("viewport snapshot", async ({ page }) => {
    await test.step("GIVEN detail view is loaded", async () => {
      await navigateToTestBead(page, detail);
      await expect(detail.beadDetail()).toBeVisible();
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
