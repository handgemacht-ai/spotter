import { expect, test } from "@playwright/test";
import { LanesPage } from "../support/pages/lanes";

/**
 * Performance profiling for the lanes view.
 *
 * These tests measure and report performance characteristics
 * rather than enforcing hard thresholds (profiling, not gating).
 */
const TEAM_SESSION_ID = "00000000-0000-0000-0000-000000000001";

test.describe("session-lanes performance profiling", () => {
  let lanes: LanesPage;

  test.beforeEach(async ({ page }) => {
    lanes = new LanesPage(page);
    await lanes.goto(TEAM_SESSION_ID);
  });

  test("measure lanes view switch time and DOM size", async ({ page }) => {
    // 1. Measure time to switch to lanes view
    const switchStart = Date.now();
    await lanes.switchToLanesView();
    await lanes.expectAgentHeaderCount(3);
    const switchTime = Date.now() - switchStart;

    // 2. Count DOM elements in the grid
    const gridDomCount = await page.evaluate(() => {
      const grid = document.querySelector('[data-testid="lanes-grid"]');
      return grid ? grid.querySelectorAll("*").length : 0;
    });

    // 3. Count total page DOM elements
    const totalDomCount = await page.evaluate(() => {
      return document.querySelectorAll("*").length;
    });

    // 4. Count rows and cells
    const rowCount = await page.locator('[data-testid="lanes-row"]').count();
    const collapsedCount = await page.locator(".lanes-msg-collapsed").count();

    // 5. Get JS heap size if available
    const heapInfo = await page.evaluate(() => {
      const perf = (performance as any);
      if (perf.memory) {
        return {
          usedJSHeapSize: Math.round(perf.memory.usedJSHeapSize / 1024 / 1024),
          totalJSHeapSize: Math.round(perf.memory.totalJSHeapSize / 1024 / 1024),
        };
      }
      return null;
    });

    console.log("=== LANES VIEW PERFORMANCE PROFILE ===");
    console.log(`Switch to lanes view: ${switchTime}ms`);
    console.log(`Grid DOM elements: ${gridDomCount}`);
    console.log(`Total page DOM elements: ${totalDomCount}`);
    console.log(`Row count: ${rowCount}`);
    console.log(`Collapsed messages: ${collapsedCount}`);
    if (heapInfo) {
      console.log(`JS Heap: ${heapInfo.usedJSHeapSize}MB used / ${heapInfo.totalJSHeapSize}MB total`);
    }

    // Soft assertions — report but don't fail on thresholds
    // These establish baseline measurements
    expect(switchTime, "switch time should be under 5s").toBeLessThan(5000);
    expect(gridDomCount, "grid DOM should be under 10000 nodes").toBeLessThan(10000);
  });

  test("measure expand-all and collapse-all performance", async ({ page }) => {
    await lanes.switchToLanesView();
    await lanes.expectAgentHeaderCount(3);

    // Count collapsed messages before expand
    const collapsedBefore = await page.locator(".lanes-msg-collapsed").count();

    // Measure expand-all
    const expandStart = Date.now();
    await page.getByRole("button", { name: "Expand all" }).click();
    // Wait for expanded messages to appear
    await page.waitForTimeout(500);
    const expandTime = Date.now() - expandStart;

    const expandedCount = await page.locator(".lanes-msg-expanded").count();
    const domAfterExpand = await page.evaluate(() => {
      const grid = document.querySelector('[data-testid="lanes-grid"]');
      return grid ? grid.querySelectorAll("*").length : 0;
    });

    // Measure collapse-all
    const collapseStart = Date.now();
    await page.getByRole("button", { name: "Collapse all" }).click();
    await page.waitForTimeout(500);
    const collapseTime = Date.now() - collapseStart;

    const domAfterCollapse = await page.evaluate(() => {
      const grid = document.querySelector('[data-testid="lanes-grid"]');
      return grid ? grid.querySelectorAll("*").length : 0;
    });

    console.log("=== EXPAND/COLLAPSE PERFORMANCE ===");
    console.log(`Collapsed messages before expand: ${collapsedBefore}`);
    console.log(`Expanded messages after expand-all: ${expandedCount}`);
    console.log(`Expand-all time: ${expandTime}ms`);
    console.log(`Collapse-all time: ${collapseTime}ms`);
    console.log(`Grid DOM after expand: ${domAfterExpand}`);
    console.log(`Grid DOM after collapse: ${domAfterCollapse}`);
    console.log(`DOM delta (expand - collapse): ${domAfterExpand - domAfterCollapse}`);

    expect(expandTime, "expand-all should be under 3s").toBeLessThan(3000);
    expect(collapseTime, "collapse-all should be under 3s").toBeLessThan(3000);
  });

  test("measure long task count during lanes switch via PerformanceObserver", async ({ page }) => {
    // Set up PerformanceObserver to capture long tasks before switching
    await page.evaluate(() => {
      (window as any).__longTasks = [];
      const observer = new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
          (window as any).__longTasks.push({
            name: entry.name,
            duration: entry.duration,
            startTime: entry.startTime,
          });
        }
      });
      observer.observe({ type: "longtask", buffered: true });
      (window as any).__longTaskObserver = observer;
    });

    // Switch to lanes view
    await lanes.switchToLanesView();
    await lanes.expectAgentHeaderCount(3);

    // Give any async long tasks time to register
    await page.waitForTimeout(1000);

    // Collect long tasks
    const longTasks = await page.evaluate(() => {
      (window as any).__longTaskObserver?.disconnect();
      return (window as any).__longTasks || [];
    });

    console.log("=== LONG TASKS DURING LANES SWITCH ===");
    console.log(`Long task count: ${longTasks.length}`);
    for (const task of longTasks) {
      console.log(`  - ${task.name}: ${Math.round(task.duration)}ms at ${Math.round(task.startTime)}ms`);
    }

    const totalBlockingTime = longTasks.reduce(
      (sum: number, t: any) => sum + Math.max(0, t.duration - 50),
      0,
    );
    console.log(`Total Blocking Time (TBT): ${Math.round(totalBlockingTime)}ms`);

    // No long tasks > 200ms is ideal
    for (const task of longTasks) {
      expect(
        task.duration,
        `Long task should be under 500ms (was ${Math.round(task.duration)}ms)`,
      ).toBeLessThan(500);
    }
  });

  test("measure layout shift (CLS) during lanes view interactions", async ({ page }) => {
    // Set up CLS observer
    await page.evaluate(() => {
      (window as any).__layoutShifts = [];
      const observer = new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
          (window as any).__layoutShifts.push({
            value: (entry as any).value,
            hadRecentInput: (entry as any).hadRecentInput,
            startTime: entry.startTime,
          });
        }
      });
      observer.observe({ type: "layout-shift", buffered: true });
      (window as any).__clsObserver = observer;
    });

    // Switch to lanes
    await lanes.switchToLanesView();
    await lanes.expectAgentHeaderCount(3);

    // Expand all
    await page.getByRole("button", { name: "Expand all" }).click();
    await page.waitForTimeout(500);

    // Collapse all
    await page.getByRole("button", { name: "Collapse all" }).click();
    await page.waitForTimeout(500);

    const shifts = await page.evaluate(() => {
      (window as any).__clsObserver?.disconnect();
      return (window as any).__layoutShifts || [];
    });

    const unexpectedShifts = shifts.filter((s: any) => !s.hadRecentInput);
    const cls = unexpectedShifts.reduce((sum: number, s: any) => sum + s.value, 0);

    console.log("=== CUMULATIVE LAYOUT SHIFT ===");
    console.log(`Total layout shifts: ${shifts.length}`);
    console.log(`Unexpected shifts (no user input): ${unexpectedShifts.length}`);
    console.log(`CLS score: ${cls.toFixed(4)}`);

    expect(cls, "CLS should be under 0.1 (good threshold)").toBeLessThan(0.1);
  });
});
