import { type Locator, type Page, expect } from "@playwright/test";
import { waitForLiveViewReady } from "../liveview";

/**
 * Page Object Model for the /reviews LiveView.
 *
 * Encapsulates annotation card selectors, image thumbnail,
 * image modal, and source badge interactions.
 *
 * Selector contract from REFINE spec:
 *   - `.annotation-thumbnail` — clickable thumbnail (max-width 200px)
 *   - `.image-modal-overlay` — custom modal overlay (NOT Phoenix core .modal)
 *   - `.image-modal-content` — modal content area with full-size image
 *   - `.image-modal-meta` — metadata panel (css_selector, viewport, url)
 *   - `.image-modal-close` — X close button
 *   - GET /api/annotations/:id/image — raw PNG serving for <img src>
 */
export class ReviewsPage {
  readonly page: Page;
  readonly root: Locator;

  constructor(page: Page) {
    this.page = page;
    this.root = page.getByTestId("reviews-root");
  }

  async goto() {
    await this.page.goto("/reviews");
    await waitForLiveViewReady(this.page, "reviews-root");
  }

  // --- Annotation card selectors ---

  allAnnotationCards(): Locator {
    return this.root.locator(".annotation-card");
  }

  annotationCard(annotationId: string): Locator {
    return this.root.locator(
      `.annotation-card[data-annotation-id="${annotationId}"]`,
    );
  }

  // --- Source badge selectors ---

  sourceBadge(card: Locator): Locator {
    return card.locator("[class*='badge']").first();
  }

  // --- Image thumbnail selectors ---

  thumbnail(card: Locator): Locator {
    return card.locator(".annotation-thumbnail");
  }

  thumbnailImage(card: Locator): Locator {
    return this.thumbnail(card).locator("img");
  }

  // --- Image modal selectors ---

  imageModalOverlay(): Locator {
    return this.page.locator(".image-modal-overlay");
  }

  imageModalContent(): Locator {
    return this.page.locator(".image-modal-content");
  }

  imageModalFullImage(): Locator {
    return this.imageModalContent().locator("img");
  }

  imageModalCloseButton(): Locator {
    return this.page.locator(".image-modal-close");
  }

  imageModalMetadata(): Locator {
    return this.page.locator(".image-modal-meta");
  }

  imageModalCssSelector(): Locator {
    return this.imageModalMetadata().locator("[data-meta-key='css_selector']");
  }

  imageModalViewport(): Locator {
    return this.imageModalMetadata().locator("[data-meta-key='viewport']");
  }

  imageModalUrl(): Locator {
    return this.imageModalMetadata().locator("[data-meta-key='url']");
  }

  // --- Assertion helpers ---

  async expectVisible() {
    await expect(this.root).toBeVisible();
  }

  async expectAnnotationCount(count: number) {
    await expect(this.allAnnotationCards()).toHaveCount(count);
  }

  async expectThumbnailVisible(card: Locator) {
    await expect(this.thumbnail(card)).toBeVisible();
  }

  async expectThumbnailHidden(card: Locator) {
    await expect(this.thumbnail(card)).toHaveCount(0);
  }

  async expectModalVisible() {
    await expect(this.imageModalOverlay()).toBeVisible();
    await expect(this.imageModalContent()).toBeVisible();
  }

  async expectModalHidden() {
    await expect(this.imageModalOverlay()).toHaveCount(0);
  }

  async expectSourceBadgeText(card: Locator, text: string) {
    await expect(this.sourceBadge(card)).toContainText(text);
  }

  async expectSourceBadgeWarningStyle(card: Locator) {
    await expect(this.sourceBadge(card)).toHaveClass(/badge-warning/);
  }

  async clickThumbnail(card: Locator) {
    await this.thumbnail(card).click();
  }

  async closeModalViaButton() {
    await this.imageModalCloseButton().click();
  }

  async closeModalViaOverlay() {
    await this.imageModalOverlay().click({ position: { x: 10, y: 10 } });
  }

  async closeModalViaEscape() {
    await this.page.keyboard.press("Escape");
  }
}
