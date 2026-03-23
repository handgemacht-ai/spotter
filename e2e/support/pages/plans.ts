import { type Locator, type Page, expect } from "@playwright/test";
import { waitForLiveViewReady } from "../liveview";

/**
 * Page Object Model for the Plans list view (/plans).
 *
 * Encapsulates selectors for search/filter/sort controls, epic table,
 * and provides assertion helpers.
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

  // --- Filter bar selectors ---

  /** The search text input. */
  searchInput(): Locator {
    return this.page.getByTestId("search-input");
  }

  /** The show/hide closed toggle button. */
  toggleClosedButton(): Locator {
    return this.page.getByTestId("toggle-closed");
  }

  /** A clickable sort column header. */
  columnHeader(col: string): Locator {
    return this.page.getByTestId(`sort-${col}`);
  }

  /** The filter bar container. */
  filterBar(): Locator {
    return this.page.getByTestId("filter-bar");
  }

  /** The error state message element. */
  errorState(): Locator {
    return this.page.getByTestId("plans-error");
  }

  /** The "Select a project" prompt. */
  selectProjectPrompt(): Locator {
    return this.page.getByTestId("select-project-prompt");
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

  /** Task count cell within a row. */
  taskCount(row: Locator): Locator {
    return row.getByTestId("task-count");
  }

  // --- Empty state ---

  /** The empty state message element. */
  emptyState(): Locator {
    return this.root.locator(".empty-state");
  }

  // --- Actions ---

  /** Type in the search input and wait for debounce + response. */
  async search(query: string) {
    await this.searchInput().fill(query);
    // Wait for 300ms debounce + LiveView response
    await this.page.waitForTimeout(500);
  }

  /** Click the toggle-closed button. */
  async toggleClosed() {
    await this.toggleClosedButton().click();
  }

  /** Click a sortable column header. */
  async sortBy(col: string) {
    await this.columnHeader(col).click();
  }

  // --- Assertion helpers ---

  /** Assert the plans root is visible. */
  async expectVisible() {
    await expect(this.root).toBeVisible();
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

  /** Assert error state is visible with expected text. */
  async expectErrorState(text: string) {
    const el = this.errorState();
    await expect(el).toBeVisible();
    await expect(el).toContainText(text);
  }

  /** Assert "Select a project" prompt is visible. */
  async expectSelectProjectPrompt() {
    await expect(this.selectProjectPrompt()).toBeVisible();
    await expect(this.selectProjectPrompt()).toContainText(
      "Select a project",
    );
  }

  /** Assert the search input has the given value. */
  async expectSearchValue(value: string) {
    await expect(this.searchInput()).toHaveValue(value);
  }
}
