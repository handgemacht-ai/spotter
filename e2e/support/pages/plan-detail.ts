import { type Locator, type Page, expect } from "@playwright/test";
import { waitForLiveViewReady } from "../liveview";

/**
 * Page Object Model for the Plan Detail view (/plans/:project/:epic_id).
 *
 * Encapsulates selectors for epic header, parsed sections, mermaid diagrams,
 * acceptance table, child tasks with expand/collapse, and annotations.
 */
export class PlanDetailPage {
  readonly page: Page;
  readonly root: Locator;

  constructor(page: Page) {
    this.page = page;
    this.root = page.getByTestId("plan-detail-root");
  }

  /** Navigate to a specific epic detail and wait for LiveView. */
  async goto(project: string, epicId: string) {
    await this.page.goto(
      `/plans/${encodeURIComponent(project)}/${encodeURIComponent(epicId)}`,
    );
    await waitForLiveViewReady(this.page, "plan-detail-root");
  }

  // --- Navigation ---

  /** Back to plans link. */
  backLink(): Locator {
    return this.page.getByTestId("back-to-plans");
  }

  // --- Epic detail header ---

  /** The epic detail container. */
  epicDetail(): Locator {
    return this.page.getByTestId("epic-detail");
  }

  /** The epic detail header (title + badges). */
  epicHeader(): Locator {
    return this.page.getByTestId("epic-detail-header");
  }

  /** The epic title heading. */
  epicTitle(): Locator {
    return this.epicHeader().locator("h2");
  }

  /** Status badge within the header. */
  statusBadge(): Locator {
    return this.epicHeader().locator("[data-status]");
  }

  /** Priority badge within the header. */
  priorityBadge(): Locator {
    return this.epicHeader().locator("[data-priority]");
  }

  // --- Sections ---

  /** The sections container. */
  sectionsContainer(): Locator {
    return this.page.getByTestId("epic-sections");
  }

  /** All section headings. */
  allSectionHeadings(): Locator {
    return this.page.getByTestId("section-heading");
  }

  /** A specific section by its heading text. */
  section(heading: string): Locator {
    return this.root.locator(`.plan-section[data-plan-section="${heading}"]`);
  }

  // --- Mermaid ---

  /** All mermaid diagram blocks. */
  allMermaidBlocks(): Locator {
    return this.page.getByTestId("mermaid-block");
  }

  // --- Acceptance table ---

  /** The acceptance criteria table. */
  acceptanceTable(): Locator {
    return this.page.getByTestId("acceptance-table");
  }

  /** All acceptance table body rows. */
  acceptanceRows(): Locator {
    return this.acceptanceTable().locator("tbody tr");
  }

  // --- Child tasks ---

  /** The child tasks container. */
  childTasksContainer(): Locator {
    return this.page.getByTestId("child-tasks");
  }

  /** All child task rows. */
  allChildTaskRows(): Locator {
    return this.page.getByTestId("child-task-row");
  }

  /** A specific child task row by task ID. */
  childTaskRow(taskId: string): Locator {
    return this.root.locator(
      `[data-testid="child-task-row"][data-task-id="${taskId}"]`,
    );
  }

  /** Toggle button within a child task row. */
  taskToggle(taskId: string): Locator {
    return this.childTaskRow(taskId).locator(".plan-task-toggle");
  }

  /** Expanded description within a child task row. */
  taskDescription(taskId: string): Locator {
    return this.childTaskRow(taskId).getByTestId(
      "child-task-description-expanded",
    );
  }

  // --- Annotations ---

  /** The selection/annotation form area. */
  selectionActive(): Locator {
    return this.page.getByTestId("selection-active");
  }

  // --- Not found ---

  /** The "not found" empty state. */
  notFound(): Locator {
    return this.page.getByTestId("plan-not-found");
  }

  // --- Assertion helpers ---

  /** Assert the plan detail root is visible. */
  async expectVisible() {
    await expect(this.root).toBeVisible();
  }

  /** Assert the epic detail is rendered with expected title. */
  async expectEpicTitle(title: string) {
    await expect(this.epicTitle()).toHaveText(title);
  }

  /** Assert the status badge shows expected status. */
  async expectStatus(status: string) {
    await expect(this.statusBadge()).toHaveAttribute("data-status", status);
  }

  /** Assert the priority badge shows expected priority. */
  async expectPriority(priority: number) {
    await expect(this.priorityBadge()).toHaveAttribute(
      "data-priority",
      String(priority),
    );
  }

  /** Assert the expected number of section headings. */
  async expectSectionCount(count: number) {
    await expect(this.allSectionHeadings()).toHaveCount(count);
  }

  /** Assert a section heading exists with expected text. */
  async expectSectionHeading(text: string) {
    await expect(this.section(text)).toBeVisible();
  }

  /** Assert the expected number of mermaid blocks. */
  async expectMermaidBlockCount(count: number) {
    await expect(this.allMermaidBlocks()).toHaveCount(count);
  }

  /** Assert the acceptance table is visible with expected row count. */
  async expectAcceptanceRowCount(count: number) {
    await expect(this.acceptanceTable()).toBeVisible();
    await expect(this.acceptanceRows()).toHaveCount(count);
  }

  /** Assert the expected number of child task rows. */
  async expectChildTaskCount(count: number) {
    await expect(this.allChildTaskRows()).toHaveCount(count);
  }

  /** Assert a child task description is expanded (visible). */
  async expectTaskExpanded(taskId: string) {
    await expect(this.taskDescription(taskId)).toBeVisible();
  }

  /** Assert a child task description is collapsed (not visible). */
  async expectTaskCollapsed(taskId: string) {
    await expect(this.taskDescription(taskId)).toHaveCount(0);
  }

  /** Assert the not-found state is visible. */
  async expectNotFound() {
    await expect(this.notFound()).toBeVisible();
  }

  /** Assert the back link points to the right path. */
  async expectBackLinkTo(path: string) {
    await expect(this.backLink()).toHaveAttribute("href", path);
  }
}
