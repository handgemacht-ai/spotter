import { type Locator, type Page, expect } from "@playwright/test";
import { waitForLiveViewReady } from "../liveview";

/**
 * Page Object Model for the Plan Detail view (/plans/:project/:bead_id).
 *
 * Encapsulates selectors for bead header, parsed sections, mermaid diagrams,
 * acceptance cards, classification chips, dependencies, child tasks,
 * and annotations.
 */
export class PlanDetailPage {
  readonly page: Page;
  readonly root: Locator;

  constructor(page: Page) {
    this.page = page;
    this.root = page.getByTestId("plan-detail-root");
  }

  /** Navigate to a specific bead detail and wait for LiveView. */
  async goto(project: string, beadId: string) {
    await this.page.goto(
      `/plans/${encodeURIComponent(project)}/${encodeURIComponent(beadId)}`,
    );
    await waitForLiveViewReady(this.page, "plan-detail-root");
  }

  // --- Navigation ---

  /** Back to plans link. */
  backLink(): Locator {
    return this.page.getByTestId("back-to-plans");
  }

  // --- Bead detail header ---

  /** The bead detail container. */
  beadDetail(): Locator {
    return this.page.getByTestId("bead-detail");
  }

  /** The bead detail header (type chip + id + title + badges). */
  beadHeader(): Locator {
    return this.page.getByTestId("bead-detail-header");
  }

  /** The bead title heading. */
  beadTitle(): Locator {
    return this.beadHeader().locator(".bead-header-title");
  }

  /** The bead type chip (epic, task, etc). */
  beadTypeChip(): Locator {
    return this.page.getByTestId("bead-type-chip");
  }

  /** The bead ID display. */
  beadId(): Locator {
    return this.page.getByTestId("bead-id");
  }

  /** Status badge within the header meta. */
  statusBadge(): Locator {
    return this.beadHeader().locator("[data-status]");
  }

  /** Priority badge within the header meta. */
  priorityBadge(): Locator {
    return this.beadHeader().locator("[data-priority]");
  }

  // --- Sections ---

  /** The sections container. */
  sectionsContainer(): Locator {
    return this.page.getByTestId("bead-sections");
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

  // --- Acceptance cards ---

  /** The acceptance cards container (was acceptance table). */
  acceptanceCards(): Locator {
    return this.page.getByTestId("acceptance-cards");
  }

  /** All individual acceptance card items. */
  allAcceptanceCardItems(): Locator {
    return this.acceptanceCards().locator(".acceptance-card");
  }

  // --- Classification chips ---

  /** The classification chips container. */
  classificationChips(): Locator {
    return this.page.getByTestId("bead-classification");
  }

  // --- Dependencies ---

  /** The dependencies container. */
  dependencyList(): Locator {
    return this.page.getByTestId("bead-dependencies");
  }

  /** All dependency rows. */
  allDependencyRows(): Locator {
    return this.page.getByTestId("dependency-row");
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

  /** The navigation link within a child task row. */
  taskLink(taskId: string): Locator {
    return this.childTaskRow(taskId).locator(".plan-task-link");
  }

  // --- Annotations ---

  /** The annotations section. */
  annotationsSection(): Locator {
    return this.page.getByTestId("bead-annotations");
  }

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

  /** Assert the bead detail is rendered with expected title. */
  async expectBeadTitle(title: string) {
    await expect(this.beadTitle()).toHaveText(title);
  }

  /** Assert the bead type chip shows expected type. */
  async expectBeadType(type: string) {
    await expect(this.beadTypeChip()).toHaveText(type);
  }

  /** Assert the bead ID displays expected value. */
  async expectBeadId(id: string) {
    await expect(this.beadId()).toHaveText(id);
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

  /** Assert acceptance cards visible with expected count. */
  async expectAcceptanceCardCount(count: number) {
    await expect(this.acceptanceCards()).toBeVisible();
    await expect(this.allAcceptanceCardItems()).toHaveCount(count);
  }

  /** Assert the expected number of child task rows. */
  async expectChildTaskCount(count: number) {
    await expect(this.allChildTaskRows()).toHaveCount(count);
  }

  /** Assert dependencies visible with expected count. */
  async expectDependencyCount(count: number) {
    await expect(this.dependencyList()).toBeVisible();
    await expect(this.allDependencyRows()).toHaveCount(count);
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
