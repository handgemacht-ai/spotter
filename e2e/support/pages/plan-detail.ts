import { type Locator, type Page, expect } from "@playwright/test";
import { waitForLiveViewReady } from "../liveview";

export class PlanDetailPage {
  readonly page: Page;
  readonly root: Locator;

  constructor(page: Page) {
    this.page = page;
    this.root = page.getByTestId("plan-detail-root");
  }

  async goto(project: string, beadId: string) {
    await this.page.goto(
      `/plans/${encodeURIComponent(project)}/${encodeURIComponent(beadId)}`,
    );
    await waitForLiveViewReady(this.page, "plan-detail-root");
  }

  // --- Navigation ---

  backLink(): Locator {
    return this.page.getByTestId("back-to-plans");
  }

  // --- Bead detail header ---

  beadDetail(): Locator {
    return this.page.getByTestId("bead-detail");
  }

  beadHeader(): Locator {
    return this.page.getByTestId("bead-detail-header");
  }

  beadTitle(): Locator {
    return this.beadHeader().locator(".bead-header-title");
  }

  beadTypeChip(): Locator {
    return this.page.getByTestId("bead-type-chip");
  }

  beadId(): Locator {
    return this.page.getByTestId("bead-id");
  }

  statusBadge(): Locator {
    return this.beadHeader().locator("[data-status]");
  }

  priorityBadge(): Locator {
    return this.beadHeader().locator("[data-priority]");
  }

  // --- Sections ---

  sectionsContainer(): Locator {
    return this.page.getByTestId("bead-sections");
  }

  allSectionHeadings(): Locator {
    return this.page.getByTestId("section-heading");
  }

  section(heading: string): Locator {
    return this.root.locator(`.plan-section[data-plan-section="${heading}"]`);
  }

  // --- Mermaid ---

  allMermaidBlocks(): Locator {
    return this.page.getByTestId("mermaid-block");
  }

  // --- Acceptance cards ---

  acceptanceCards(): Locator {
    return this.page.getByTestId("acceptance-cards");
  }

  allAcceptanceCardItems(): Locator {
    return this.acceptanceCards().locator(".acceptance-card");
  }

  // --- Classification chips ---

  classificationChips(): Locator {
    return this.page.getByTestId("bead-classification");
  }

  // --- Dependencies ---

  dependencyList(): Locator {
    return this.page.getByTestId("bead-dependencies");
  }

  allDependencyRows(): Locator {
    return this.page.getByTestId("dependency-row");
  }

  // --- Child tasks ---

  childTasksContainer(): Locator {
    return this.page.getByTestId("child-tasks");
  }

  allChildTaskRows(): Locator {
    return this.page.getByTestId("child-task-row");
  }

  childTaskRow(taskId: string): Locator {
    return this.root.locator(
      `[data-testid="child-task-row"][data-task-id="${taskId}"]`,
    );
  }

  taskLink(taskId: string): Locator {
    return this.childTaskRow(taskId).locator(".plan-task-link");
  }

  // --- Annotations ---

  annotationsSection(): Locator {
    return this.page.getByTestId("bead-annotations");
  }

  selectionActive(): Locator {
    return this.page.getByTestId("selection-active");
  }

  // --- Not found ---

  notFound(): Locator {
    return this.page.getByTestId("plan-not-found");
  }

  // --- Assertion helpers ---

  async expectVisible() {
    await expect(this.root).toBeVisible();
  }

  async expectBeadTitle(title: string) {
    await expect(this.beadTitle()).toHaveText(title);
  }

  async expectBeadType(type: string) {
    await expect(this.beadTypeChip()).toHaveText(type);
  }

  async expectBeadId(id: string) {
    await expect(this.beadId()).toHaveText(id);
  }

  async expectStatus(status: string) {
    await expect(this.statusBadge()).toHaveAttribute("data-status", status);
  }

  async expectPriority(priority: number) {
    await expect(this.priorityBadge()).toHaveAttribute(
      "data-priority",
      String(priority),
    );
  }

  async expectSectionCount(count: number) {
    await expect(this.allSectionHeadings()).toHaveCount(count);
  }

  async expectSectionHeading(text: string) {
    await expect(this.section(text)).toBeVisible();
  }

  async expectMermaidBlockCount(count: number) {
    await expect(this.allMermaidBlocks()).toHaveCount(count);
  }

  async expectAcceptanceCardCount(count: number) {
    await expect(this.acceptanceCards()).toBeVisible();
    await expect(this.allAcceptanceCardItems()).toHaveCount(count);
  }

  async expectChildTaskCount(count: number) {
    await expect(this.allChildTaskRows()).toHaveCount(count);
  }

  async expectDependencyCount(count: number) {
    await expect(this.dependencyList()).toBeVisible();
    await expect(this.allDependencyRows()).toHaveCount(count);
  }

  async expectNotFound() {
    await expect(this.notFound()).toBeVisible();
  }

  async expectBackLinkTo(path: string) {
    await expect(this.backLink()).toHaveAttribute("href", path);
  }
}
