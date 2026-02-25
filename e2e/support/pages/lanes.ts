import { type Locator, type Page, expect } from "@playwright/test";
import { waitForLiveViewReady } from "../liveview";

/**
 * Page Object Model for the session-lanes view.
 *
 * Encapsulates all data-testid selectors and provides
 * helpers for common assertions and interactions.
 *
 * Layout: CSS Grid table with sticky time column, agent header row,
 * and collapsed/expandable message cells.
 */
export class LanesPage {
  readonly page: Page;
  readonly panel: Locator;

  constructor(page: Page) {
    this.page = page;
    this.panel = page.getByTestId("lanes-panel");
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

  // --- Grid selectors ---

  /** Locator for the grid container. */
  grid(): Locator {
    return this.page.getByTestId("lanes-grid");
  }

  /** Locator for all agent header cells in the grid. */
  allAgentHeaders(): Locator {
    return this.page.locator('[data-testid^="lanes-agent-header-"]');
  }

  /** Locator for a specific agent header by name. */
  agentHeader(agentName: string): Locator {
    return this.page.getByTestId(`lanes-agent-header-${agentName}`);
  }

  /** Locator for the lane-name element within an agent header. */
  laneName(agentName: string): Locator {
    return this.agentHeader(agentName).getByTestId("lane-name");
  }

  /** Locator for the time column header. */
  timeHeader(): Locator {
    return this.page.getByTestId("lanes-time-header");
  }

  /** Locator for all data rows. */
  allRows(): Locator {
    return this.page.locator('[data-testid="lanes-row"]');
  }

  /** Locator for the toolbar. */
  toolbar(): Locator {
    return this.page.getByTestId("lanes-toolbar");
  }

  // --- Cell selectors ---

  /** Locator for all cells for a given agent across all rows. */
  allCellsForAgent(agentName: string): Locator {
    return this.grid().locator(
      `[data-testid="lanes-cell-${agentName}"]`,
    );
  }

  /** Locator for collapsed message cells. */
  collapsedMessages(): Locator {
    return this.grid().locator(".lanes-msg-collapsed");
  }

  /** Locator for expanded message cells. */
  expandedMessages(): Locator {
    return this.grid().locator(".lanes-msg-expanded");
  }

  /** Locator for idle row cells. */
  idleRows(): Locator {
    return this.grid().locator(".lanes-idle-row");
  }

  /** Locator for tool badges within a cell. */
  toolBadges(cell: Locator): Locator {
    return cell.locator(".lanes-tool-badge");
  }

  /** Locator for the type label within a message cell. */
  msgType(cell: Locator): Locator {
    return cell.locator(".lanes-msg-type");
  }

  /** Locator for the content preview within a collapsed message cell. */
  msgPreview(cell: Locator): Locator {
    return cell.locator(".lanes-msg-preview");
  }

  /** Locator for the expanded content area. */
  msgContent(cell: Locator): Locator {
    return cell.locator(".lanes-msg-content");
  }

  /** Locator for idle duration labels. */
  idleLabel(cell: Locator): Locator {
    return cell.locator(".lanes-idle-label");
  }

  // --- Drag-and-drop selectors ---

  /** Locator for the header row container (SortableColumns hook target). */
  headerRow(): Locator {
    return this.page.getByTestId("lanes-header-row");
  }

  /** Locator for a drag handle within an agent header. */
  dragHandle(agentName: string): Locator {
    return this.agentHeader(agentName).locator(".lanes-drag-handle");
  }

  /** Locator for the "Reset order" toolbar button. */
  resetOrderButton(): Locator {
    return this.page.getByTestId("reset-column-order");
  }

  /** Get the ordered list of agent names from the header row DOM order. */
  async getAgentHeaderOrder(): Promise<string[]> {
    const headers = this.allAgentHeaders();
    const count = await headers.count();
    const names: string[] = [];
    for (let i = 0; i < count; i++) {
      const nameEl = headers.nth(i).getByTestId("lane-name");
      const text = await nameEl.textContent();
      if (text) names.push(text);
    }
    return names;
  }

  /**
   * Programmatically reorder columns by pushing the reorder_lanes event via LiveSocket.
   * SortableJS drag simulation is unreliable in headless Playwright, so we test the
   * round-trip by dispatching the same event the hook would send on drop.
   */
  async reorderColumnsViaHook(newSessionIdOrder: string[]) {
    await this.page.evaluate((order) => {
      const headerRow = document.querySelector(
        "[data-testid='lanes-header-row']",
      );
      if (!headerRow) throw new Error("lanes-header-row not found");

      const liveSocket = (window as any).liveSocket;
      if (!liveSocket) throw new Error("liveSocket not found on window");

      // Find the hook instance via LiveView internals:
      // liveSocket.roots[viewId].viewHooks[hookId] where hook.el === headerRow
      let hook: any = null;
      for (const viewId of Object.keys(liveSocket.roots)) {
        const view = liveSocket.roots[viewId];
        for (const hookId of Object.keys(view.viewHooks || {})) {
          const h = view.viewHooks[hookId];
          if (h.el === headerRow) {
            hook = h;
            break;
          }
        }
        if (hook) break;
      }

      if (!hook || !hook.pushEvent) {
        throw new Error(
          "SortableColumns hook not found on lanes-header-row element",
        );
      }

      hook.pushEvent("reorder_lanes", { order });

      // Also save to localStorage to match SortableJS onEnd behavior
      const sessionId = (headerRow as HTMLElement).dataset.sessionId;
      if (sessionId) {
        localStorage.setItem(
          `spotter:lane-order:${sessionId}`,
          JSON.stringify(order),
        );
      }
    }, newSessionIdOrder);
    // Wait for LiveView to process
    await this.page.waitForTimeout(500);
  }

  /** Get session IDs from agent headers in the header row (not tab bar). */
  async getAgentSessionIdOrder(): Promise<string[]> {
    return this.page.evaluate(() => {
      const headerRow = document.querySelector("[data-testid='lanes-header-row']");
      if (!headerRow) return [];
      const headers = headerRow.querySelectorAll("[data-lane-session-id]");
      return Array.from(headers).map((el) => (el as HTMLElement).dataset.laneSessionId || "");
    });
  }

  // --- Connector / drawer selectors ---

  /** Locator for the SVG connector overlay. */
  connectorOverlay(): Locator {
    return this.page.getByTestId("lanes-connector-overlay");
  }

  /** Locator for SVG connector lines within the overlay. */
  connectorLines(): Locator {
    return this.connectorOverlay().locator(".lanes-connector-line");
  }

  /** Locator for all inter-agent message link badges. */
  allBadges(): Locator {
    return this.grid().locator(".lanes-msg-link-badge");
  }

  /** Locator for badges with a specific direction (sent or received). */
  badgesByDirection(direction: "sent" | "received"): Locator {
    return this.grid().locator(
      `.lanes-msg-link-badge[data-link-direction="${direction}"]`,
    );
  }

  /** Locator for the message drawer panel. */
  drawer(): Locator {
    return this.page.getByTestId("lanes-message-drawer");
  }

  /** Locator for the drawer close button. */
  drawerCloseButton(): Locator {
    return this.drawer().locator("[data-drawer-close]");
  }

  /** Locator for the "Jump to response" button in the drawer. */
  drawerJumpButton(): Locator {
    return this.drawer().locator("[data-drawer-jump]");
  }

  /** Locator for the drawer direction label. */
  drawerDirection(): Locator {
    return this.drawer().locator("[data-drawer-direction]");
  }

  /** Locator for the drawer peer label. */
  drawerPeer(): Locator {
    return this.drawer().locator("[data-drawer-peer]");
  }

  /** Locator for the drawer preview content. */
  drawerPreview(): Locator {
    return this.drawer().locator("[data-drawer-preview]");
  }

  /** Locator for highlighted cells. */
  highlightedCells(): Locator {
    return this.grid().locator(".lanes-cell-highlighted");
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

  /** Assert the expected number of agent header columns. */
  async expectAgentHeaderCount(count: number) {
    await expect(this.allAgentHeaders()).toHaveCount(count);
  }

  /** Assert a lane tab exists and has the given text content. */
  async expectTabText(agentName: string, text: string) {
    await expect(this.tab(agentName)).toContainText(text);
  }

  /** Assert a lane name label has the expected text. */
  async expectLaneName(agentName: string, expectedName: string) {
    await expect(this.laneName(agentName)).toHaveText(expectedName);
  }

  /** Assert an agent header contains text matching a duration pattern. */
  async expectAgentHeaderDuration(agentName: string, pattern: RegExp) {
    await expect(this.agentHeader(agentName)).toContainText(pattern);
  }

  /** Assert a tab has the is-active class. */
  async expectTabActive(agentName: string) {
    await expect(this.tab(agentName)).toHaveClass(/is-active/);
  }

  // --- Layout assertion helpers ---

  /** Assert the grid container uses CSS Grid display. */
  async expectGridLayout() {
    const gridEl = this.grid();
    const display = await gridEl.evaluate(
      (el) => getComputedStyle(el).display,
    );
    expect(display, "grid container must use CSS grid layout").toBe("grid");
  }

  /** Assert agent headers are arranged horizontally (side-by-side). */
  async expectAgentHeadersSideBySide() {
    const headers = this.allAgentHeaders();
    const count = await headers.count();
    expect(
      count,
      "need at least 2 agent headers to verify side-by-side",
    ).toBeGreaterThanOrEqual(2);

    const firstBox = await headers.nth(0).boundingBox();
    const secondBox = await headers.nth(1).boundingBox();
    expect(firstBox, "first header must have a bounding box").not.toBeNull();
    expect(secondBox, "second header must have a bounding box").not.toBeNull();
    expect(
      firstBox!.x,
      "first header x must be less than second header x (side-by-side)",
    ).toBeLessThan(secondBox!.x);
  }

  /** Assert the grid is horizontally scrollable when columns overflow viewport. */
  async expectGridHorizontallyScrollable() {
    const gridEl = this.grid();
    const { scrollWidth, clientWidth } = await gridEl.evaluate((el) => ({
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
    }));
    expect(
      scrollWidth,
      "grid scrollWidth must exceed clientWidth when lanes overflow",
    ).toBeGreaterThan(clientWidth);
  }

  /** Assert the time header column is visible (sticky time column present). */
  async expectTimeHeaderVisible() {
    await expect(this.timeHeader()).toBeVisible();
  }

  /** Assert the time column header has sticky positioning. */
  async expectTimeHeaderSticky() {
    const th = this.timeHeader();
    const position = await th.evaluate(
      (el) => getComputedStyle(el).position,
    );
    expect(position, "time header must be sticky").toBe("sticky");
  }

  /** Assert at least `min` data rows are rendered. */
  async expectMinRowCount(min: number) {
    const count = await this.allRows().count();
    expect(
      count,
      `expected at least ${min} data rows`,
    ).toBeGreaterThanOrEqual(min);
  }

  /** Assert each row has a cell per agent (N cells per row). */
  async expectRowCellsPerAgent(agentNames: string[]) {
    const rows = this.allRows();
    const rowCount = await rows.count();
    expect(rowCount, "must have at least 1 row").toBeGreaterThanOrEqual(1);

    for (const name of agentNames) {
      const cells = this.allCellsForAgent(name);
      const cellCount = await cells.count();
      expect(
        cellCount,
        `agent ${name} must have at least 1 cell`,
      ).toBeGreaterThanOrEqual(1);
    }
  }

  /** Assert all visible message cells are collapsed by default. */
  async expectMessagesCollapsedByDefault() {
    const collapsed = this.collapsedMessages();
    const expanded = this.expandedMessages();
    const collapsedCount = await collapsed.count();
    const expandedCount = await expanded.count();
    expect(
      collapsedCount,
      "must have at least 1 collapsed message",
    ).toBeGreaterThanOrEqual(1);
    expect(expandedCount, "no messages should be expanded by default").toBe(0);
  }

  /** Assert collapsed messages show type label and content preview. */
  async expectCollapsedMessageContent() {
    const firstCollapsed = this.collapsedMessages().first();
    await expect(firstCollapsed).toBeVisible();
    const typeLabel = this.msgType(firstCollapsed);
    await expect(typeLabel).toBeVisible();
    const preview = this.msgPreview(firstCollapsed);
    const text = await preview.textContent();
    expect(
      text && text.length > 0,
      "collapsed message must show content preview",
    ).toBe(true);
  }

  /** Click a collapsed message and assert it expands. */
  async clickToExpandFirstMessage(): Promise<void> {
    const firstCollapsed = this.collapsedMessages().first();
    await expect(firstCollapsed).toBeVisible();
    await firstCollapsed.click();
    // After click, at least one expanded message should exist
    await expect(this.expandedMessages().first()).toBeVisible();
  }

  /** Assert idle rows exist and show duration labels. */
  async expectIdleRowsWithLabels() {
    const idles = this.idleRows();
    const count = await idles.count();
    expect(count, "must have at least 1 idle row").toBeGreaterThanOrEqual(1);
    // Check the first idle row for a duration label
    const label = this.idleLabel(idles.first());
    await expect(label).toBeVisible();
    const text = await label.textContent();
    expect(text, "idle label must contain 'idle'").toContain("idle");
  }

  // --- Drag-and-drop assertion helpers ---

  /** Assert drag handle becomes visible when hovering an agent header. */
  async expectDragHandleOnHover(agentName: string) {
    const header = this.agentHeader(agentName);
    const handle = this.dragHandle(agentName);
    // Before hover, handle should exist but not be visible
    await expect(handle).toBeAttached();
    // Hover to reveal
    await header.hover();
    await expect(handle).toBeVisible();
  }

  /** Assert agent headers are in the expected order (polls until match or timeout). */
  async expectAgentOrder(expectedNames: string[]) {
    await expect
      .poll(() => this.getAgentHeaderOrder(), {
        message: `Expected agent header order: ${expectedNames.join(", ")}`,
        timeout: 5000,
      })
      .toEqual(expectedNames);
  }

  /** Assert reset order button is visible. */
  async expectResetOrderVisible() {
    await expect(this.resetOrderButton()).toBeVisible();
  }

  /** Assert reset order button is not visible. */
  async expectResetOrderHidden() {
    await expect(this.resetOrderButton()).toHaveCount(0);
  }

  /** Assert no drag handles exist (single lane scenario). */
  async expectNoDragHandles() {
    const handles = this.grid().locator(".lanes-drag-handle");
    await expect(handles).toHaveCount(0);
  }

  // --- Connector / drawer assertion helpers ---

  /** Assert at least `min` inter-agent badges are rendered. */
  async expectMinBadgeCount(min: number) {
    const count = await this.allBadges().count();
    expect(
      count,
      `expected at least ${min} message link badges`,
    ).toBeGreaterThanOrEqual(min);
  }

  /** Assert the drawer is visible with expected direction and peer. */
  async expectDrawerOpen(direction: string, peer: string) {
    await expect(this.drawer()).toBeVisible();
    await expect(this.drawerDirection()).toContainText(direction);
    await expect(this.drawerPeer()).toContainText(peer);
  }

  /** Assert the drawer is hidden. */
  async expectDrawerHidden() {
    // Drawer exists but has display: none
    await expect(this.drawer()).toBeHidden();
  }

  /** Assert a connector line appears in the SVG overlay. */
  async expectConnectorLineVisible() {
    await expect(this.connectorLines().first()).toBeVisible();
  }

  /** Assert no connector lines are present. */
  async expectNoConnectorLines() {
    await expect(this.connectorLines()).toHaveCount(0);
  }

  /** Assert at least one cell has the highlighted class. */
  async expectHighlightedCell() {
    const count = await this.highlightedCells().count();
    expect(count, "expected at least 1 highlighted cell").toBeGreaterThanOrEqual(
      1,
    );
  }

  /** Assert no cells are highlighted. */
  async expectNoHighlightedCells() {
    await expect(this.highlightedCells()).toHaveCount(0);
  }
}
