import { type Locator, type Page, expect } from "@playwright/test";
import { waitForLiveViewReady } from "../liveview";

/**
 * Page Object Model for the session-lanes view.
 *
 * Encapsulates all data-testid selectors from the design spec
 * (docs/design/session-lanes-test-selectors.md) and provides
 * helpers for common assertions and interactions.
 */
export class LanesPage {
  readonly page: Page;
  readonly panel: Locator;
  readonly timeAxis: Locator;

  constructor(page: Page) {
    this.page = page;
    this.panel = page.getByTestId("lanes-panel");
    this.timeAxis = page.getByTestId("lanes-time-axis");
  }

  /** Navigate to a session and wait for LiveView to connect. */
  async goto(sessionId: string) {
    await this.page.goto(`/sessions/${sessionId}`);
    await waitForLiveViewReady(this.page, "session-root");
  }

  /** Switch to lanes view by clicking the "Lanes" button in the view-mode toggle. */
  async switchToLanesView() {
    const toggle = this.page.getByTestId("view-mode-toggle");
    await expect(toggle).toBeVisible();
    await toggle.getByText("Lanes").click();
    await expect(this.panel).toBeVisible();
  }

  // --- Tab selectors ---

  /** Locator for all lane tab buttons. */
  allTabs(): Locator {
    return this.page.locator('[data-testid^="lane-tab-"]');
  }

  /** Locator for a specific lane tab by agent name. */
  tab(agentName: string): Locator {
    return this.page.getByTestId(`lane-tab-${agentName}`);
  }

  /** Click a lane tab to switch the active lane. */
  async clickTab(agentName: string) {
    await this.tab(agentName).click();
  }

  // --- Column selectors ---

  /** Locator for all lane columns. */
  allColumns(): Locator {
    return this.page.locator('[data-testid^="lane-column-"]');
  }

  /** Locator for a specific lane column by agent name. */
  column(agentName: string): Locator {
    return this.page.getByTestId(`lane-column-${agentName}`);
  }

  /** Locator for the lane-name element scoped within a column. */
  laneName(agentName: string): Locator {
    return this.column(agentName).getByTestId("lane-name");
  }

  /** Locator for the lane-duration element scoped within a column. */
  laneDuration(agentName: string): Locator {
    return this.column(agentName).getByTestId("lane-duration");
  }

  // --- Overlap selectors ---

  /** Locator for all overlap bars. */
  allOverlapBars(): Locator {
    return this.page.locator('[data-testid^="overlap-bar-"]');
  }

  /** Locator for a specific overlap bar by time (HH:MM format). */
  overlapBar(time: string): Locator {
    return this.page.getByTestId(`overlap-bar-${time}`);
  }

  /** Locator for a specific overlap time label by time (HH:MM format). */
  overlapTime(time: string): Locator {
    return this.page.getByTestId(`overlap-time-${time}`);
  }

  // --- Assertion helpers ---

  /** Assert the lanes panel is visible. */
  async expectVisible() {
    await expect(this.panel).toBeVisible();
  }

  /** Assert the expected number of lane tabs. */
  async expectTabCount(count: number) {
    await expect(this.allTabs()).toHaveCount(count);
  }

  /** Assert the expected number of lane columns. */
  async expectColumnCount(count: number) {
    await expect(this.allColumns()).toHaveCount(count);
  }

  /** Assert a lane tab exists and has the given text content. */
  async expectTabText(agentName: string, text: string) {
    await expect(this.tab(agentName)).toContainText(text);
  }

  /** Assert a lane name label has the expected text. */
  async expectLaneName(agentName: string, expectedName: string) {
    await expect(this.laneName(agentName)).toHaveText(expectedName);
  }

  /** Assert a lane duration label matches a pattern (e.g. /\d+[hms]/). */
  async expectLaneDuration(agentName: string, pattern: RegExp) {
    await expect(this.laneDuration(agentName)).toHaveText(pattern);
  }

  /** Assert at least one overlap bar is present. */
  async expectOverlapsPresent() {
    await expect(this.allOverlapBars().first()).toBeVisible();
  }

  /** Assert the expected number of overlap bars. */
  async expectOverlapCount(count: number) {
    await expect(this.allOverlapBars()).toHaveCount(count);
  }

  /** Assert a tab has the is-active class. */
  async expectTabActive(agentName: string) {
    await expect(this.tab(agentName)).toHaveClass(/is-active/);
  }
}
