import { type Locator, type Page, expect } from "@playwright/test";

/**
 * Helper for interacting with the global sidebar project selector.
 *
 * The sidebar project selector is rendered in root.html.heex and
 * uses vanilla JS (project_selector.js) — clicking an item triggers
 * a full-page navigation with ?project= query param.
 */
export class SidebarHelper {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  /** The #project-selector container. */
  container(): Locator {
    return this.page.locator("#project-selector");
  }

  /** The project selector button that opens the dropdown. */
  selectorButton(): Locator {
    return this.container().locator(".project-selector");
  }

  /** The dropdown listbox (hidden by default). */
  dropdown(): Locator {
    return this.container().locator(".project-selector-dropdown");
  }

  /** A specific project item by its data-project-id. */
  projectItem(projectId: string): Locator {
    return this.dropdown().locator(
      `.project-selector-item[data-project-id="${projectId}"]`,
    );
  }

  /** All project items in the dropdown. */
  allProjectItems(): Locator {
    return this.dropdown().locator(".project-selector-item");
  }

  /** The displayed project name in the selector button. */
  currentProjectName(): Locator {
    return this.selectorButton().locator(".project-name");
  }

  /** Open the dropdown, click a project item. Triggers full-page navigation. */
  async selectProject(projectId: string) {
    await this.selectorButton().click();
    await expect(this.dropdown()).toBeVisible();
    await this.projectItem(projectId).click();
  }

  /** Get the first available project ID from the dropdown. */
  async getFirstProjectId(): Promise<string> {
    await this.selectorButton().click();
    await expect(this.dropdown()).toBeVisible();
    const firstItem = this.allProjectItems().first();
    const id = await firstItem.getAttribute("data-project-id");
    await this.page.keyboard.press("Escape");
    return id!;
  }

  /** Assert the currently displayed project name. */
  async expectCurrentProject(name: string) {
    await expect(this.currentProjectName()).toHaveText(name);
  }

  /** Assert the selector button is visible. */
  async expectVisible() {
    await expect(this.selectorButton()).toBeVisible();
  }
}
