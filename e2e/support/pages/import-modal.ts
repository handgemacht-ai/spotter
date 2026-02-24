import { type Locator, type Page, expect } from "@playwright/test";
import { waitForLiveViewReady } from "../liveview";

/**
 * Page Object Model for the transcript import modal.
 *
 * Encapsulates all data-testid selectors for the import flow
 * and provides assertion helpers for e2e tests.
 */
export class ImportModalPage {
  readonly page: Page;
  readonly importButton: Locator;
  readonly modal: Locator;
  readonly closeButton: Locator;
  readonly projectFilter: Locator;
  readonly sortSelect: Locator;
  readonly selectAll: Locator;
  readonly importActionButton: Locator;
  readonly importProgress: Locator;
  readonly selectionCount: Locator;
  readonly pagination: Locator;

  constructor(page: Page) {
    this.page = page;
    this.importButton = page.getByTestId("import-button");
    this.modal = page.getByTestId("import-modal");
    this.closeButton = page.getByTestId("import-modal-close");
    this.projectFilter = page.getByTestId("project-filter");
    this.sortSelect = page.getByTestId("sort-select");
    this.selectAll = page.getByTestId("select-all");
    this.importActionButton = page.getByTestId("import-action-button");
    this.importProgress = page.getByTestId("import-progress");
    this.selectionCount = page.getByTestId("selection-count");
    this.pagination = page.getByTestId("pagination");
  }

  /** Navigate to dashboard and wait for LiveView to connect. */
  async gotoDashboard() {
    await this.page.goto("/");
    await waitForLiveViewReady(this.page, "dashboard-root");
  }

  /** Open the import modal and wait for transcript rows to load. */
  async openModal() {
    await this.importButton.click();
    await expect(this.modal).toBeVisible();
    // Wait for async transcript listing to populate rows
    await expect(this.allRows().first().or(this.page.locator(".empty-state"))).toBeVisible();
  }

  /** Close the import modal. */
  async closeModal() {
    await this.closeButton.click();
    await expect(this.modal).not.toBeVisible();
  }

  // --- Row selectors ---

  /** All transcript rows in the import table. */
  allRows(): Locator {
    return this.page.getByTestId("transcript-row");
  }

  /** Get a specific row by index (0-based). */
  row(index: number): Locator {
    return this.allRows().nth(index);
  }

  /** Checkbox within a specific row. */
  rowCheckbox(index: number): Locator {
    return this.row(index).getByTestId("select-transcript");
  }

  /** First non-disabled (importable) checkbox in the table. */
  firstImportableCheckbox(): Locator {
    return this.page
      .locator('[data-testid="transcript-row"]:not(.already-imported)')
      .first()
      .getByTestId("select-transcript");
  }

  /** Page button by page number. */
  pageButton(pageNum: number): Locator {
    return this.page.getByTestId(`page-${pageNum}`);
  }

  /** "Import Team" button for a specific team name. */
  importTeamButton(teamName: string): Locator {
    return this.page.locator(`[data-testid="import-team-btn"][phx-value-team-name="${teamName}"]`);
  }

  /** First visible "Import Team" button in the modal. */
  firstImportTeamButton(): Locator {
    return this.page.getByTestId("import-team-btn").first();
  }

  /** Get the team name from a team badge element. */
  firstTeamName(): Locator {
    return this.page.getByTestId("team-badge").first();
  }

  // --- Dashboard selectors ---

  /** All session rows on the dashboard. */
  sessionRows(): Locator {
    return this.page.getByTestId("session-row");
  }

  // --- Assertion helpers ---

  /** Assert the import modal is visible. */
  async expectModalVisible() {
    await expect(this.modal).toBeVisible();
  }

  /** Assert the import modal is not visible. */
  async expectModalHidden() {
    await expect(this.modal).not.toBeVisible();
  }

  /** Assert the expected number of transcript rows. */
  async expectRowCount(count: number) {
    await expect(this.allRows()).toHaveCount(count);
  }

  /** Assert selection count text. */
  async expectSelectionCount(text: string) {
    await expect(this.selectionCount).toContainText(text);
  }

  /** Assert a row checkbox is checked. */
  async expectRowChecked(index: number) {
    await expect(this.rowCheckbox(index)).toBeChecked();
  }

  /** Assert a row checkbox is not checked. */
  async expectRowNotChecked(index: number) {
    await expect(this.rowCheckbox(index)).not.toBeChecked();
  }

  /** Assert the import action button is enabled. */
  async expectImportEnabled() {
    await expect(this.importActionButton).toBeEnabled();
  }

  /** Assert the import action button is disabled. */
  async expectImportDisabled() {
    await expect(this.importActionButton).toBeDisabled();
  }

  /** Assert project filter option does NOT contain raw path format. */
  async expectProjectNamesReadable() {
    const options = this.projectFilter.locator("option");
    const count = await options.count();
    for (let i = 1; i < count; i++) {
      // skip "All Projects" option
      const text = await options.nth(i).textContent();
      expect(text).not.toMatch(/^-home-/);
    }
  }
}
