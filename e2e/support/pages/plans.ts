import { type Locator, type Page, expect } from "@playwright/test";
import { waitForLiveViewReady } from "../liveview";

/**
 * Page Object Model for the Plans list view (/plans).
 *
 * Encapsulates all data-testid selectors and provides
 * assertion helpers for project chip filtering and epic table.
 */
export class PlansPage {
  readonly page: Page;
  readonly root: Locator;
  readonly epicTable: Locator;

  constructor(page: Page) {
    this.page = page;
    this.root = page.getByTestId("plans-root");
    this.epicTable = page.getByTestId("epic-table");
  }

  /** Navigate to /plans and wait for LiveView to connect. */
  async goto() {
    await this.page.goto("/plans");
    await waitForLiveViewReady(this.page, "plans-root");
  }

  /** Navigate to /plans with a project filter and wait for LiveView. */
  async gotoWithProject(project: string) {
    await this.page.goto(`/plans?project=${encodeURIComponent(project)}`);
    await waitForLiveViewReady(this.page, "plans-root");
  }

  // --- Project chip selectors ---

  /** All project filter chip buttons. */
  allProjectChips(): Locator {
    return this.page.locator(".filter-btn");
  }

  /** A specific project chip by project name (data-project attribute). */
  projectChip(project: string): Locator {
    return this.page.locator(`.filter-btn[data-project="${project}"]`);
  }

  /** Click a project chip to filter. */
  async selectProject(project: string) {
    await this.projectChip(project).click();
  }

  /** Get the epic count badge text from a project chip. */
  async chipEpicCount(project: string): Promise<string> {
    const chip = this.projectChip(project);
    const count = chip.locator(".plan-chip-count");
    return (await count.textContent()) ?? "";
  }

  // --- Epic table selectors ---

  /** All epic rows in the table. */
  allEpicRows(): Locator {
    return this.page.getByTestId("epic-row");
  }

  /** Epic link within a row (first column). */
  epicLink(row: Locator): Locator {
    return row.locator(".plan-epic-link");
  }

  /** Epic title within a row (second column). */
  epicTitle(row: Locator): Locator {
    return row.locator(".plan-epic-title");
  }

  // --- Project group headers (post-migration: grouped-by-project view) ---

  /** All project group header elements (visible when no project filter). */
  allProjectGroupHeaders(): Locator {
    return this.root.getByTestId("project-group-header");
  }

  /** A specific project group header by project name. */
  projectGroupHeader(project: string): Locator {
    return this.root.locator(
      `[data-testid="project-group-header"][data-project="${project}"]`,
    );
  }

  // --- Empty state ---

  /** The empty state message element. */
  emptyState(): Locator {
    return this.root.locator(".empty-state");
  }

  // --- Assertion helpers ---

  /** Assert the plans root is visible. */
  async expectVisible() {
    await expect(this.root).toBeVisible();
  }

  /** Assert the expected number of project chips. */
  async expectChipCount(count: number) {
    await expect(this.allProjectChips()).toHaveCount(count);
  }

  /** Assert a project chip is active (selected). */
  async expectChipActive(project: string) {
    await expect(this.projectChip(project)).toHaveClass(/is-active/);
  }

  /** Assert a project chip is not active. */
  async expectChipInactive(project: string) {
    const chip = this.projectChip(project);
    const cls = await chip.getAttribute("class");
    expect(cls).not.toContain("is-active");
  }

  /** Assert the expected number of epic rows. */
  async expectEpicRowCount(count: number) {
    await expect(this.allEpicRows()).toHaveCount(count);
  }

  /** Assert the empty state is visible with expected text. */
  async expectEmptyState(text: string) {
    const empty = this.emptyState();
    await expect(empty).toBeVisible();
    await expect(empty).toContainText(text);
  }

  /** Assert the epic table is visible. */
  async expectTableVisible() {
    await expect(this.epicTable).toBeVisible();
  }

  /** Assert that local project chip filters are NOT present (removed post-migration). */
  async expectNoProjectChips() {
    await expect(this.allProjectChips()).toHaveCount(0);
  }

  /** Assert project group headers are visible with at least the given count. */
  async expectProjectGroupHeaders(minCount: number) {
    const count = await this.allProjectGroupHeaders().count();
    expect(
      count,
      `expected at least ${minCount} project group headers`,
    ).toBeGreaterThanOrEqual(minCount);
  }

  /** Assert that epics are shown under project group headers (grouped view). */
  async expectGroupedByProject() {
    await expect(this.allProjectGroupHeaders().first()).toBeVisible({
      timeout: 5000,
    });
    await expect(this.allEpicRows().first()).toBeVisible({ timeout: 5000 });
  }
}
