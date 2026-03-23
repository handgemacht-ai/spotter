import { expect, test } from "@playwright/test";
import { ReviewsPage } from "../support/pages/reviews";

const BASE_URL = process.env.SPOTTER_BASE_URL ?? "http://127.0.0.1:1100";

// 1x1 red PNG pixel (smallest valid PNG for testing)
const TINY_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==",
  "base64",
);

interface SeedResult {
  annotationId: string;
  projectId: string;
}

/**
 * Resolve a project ID by scraping the project selector from the homepage.
 * Uses the first available project.
 */
async function resolveFirstProjectId(): Promise<string> {
  const res = await fetch(`${BASE_URL}/`);
  const html = await res.text();
  const match = html.match(/data-project-id="([^"]+)"/);
  if (!match) throw new Error("No project found in sidebar — seed data first");
  return match[1];
}

/**
 * Seed a product_feedback annotation via REST API.
 * Metadata uses feedback.* keys per REFINE spec.
 */
async function seedAnnotation(opts: {
  projectId: string;
  withImage: boolean;
  metadata?: Record<string, string>;
}): Promise<SeedResult> {
  const createRes = await fetch(`${BASE_URL}/api/annotations`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      source: "product_feedback",
      comment: `E2E test annotation ${Date.now()}`,
      selected_text: "Screenshot of login page",
      project_id: opts.projectId,
      metadata: opts.metadata ?? {
        "feedback.css_selector": "#login-form .submit-btn",
        "feedback.viewport": "1440x900",
        "feedback.url": "http://localhost:3000/login",
      },
    }),
  });

  expect(createRes.ok, `annotation create failed: ${createRes.status}`).toBe(
    true,
  );
  const { id: annotationId } = (await createRes.json()) as { id: string };

  if (opts.withImage) {
    const imageRes = await fetch(
      `${BASE_URL}/api/annotations/${annotationId}/image`,
      {
        method: "POST",
        headers: { "Content-Type": "image/png" },
        body: TINY_PNG,
      },
    );
    expect(imageRes.ok, `image attach failed: ${imageRes.status}`).toBe(true);
  }

  return { annotationId, projectId: opts.projectId };
}

test.describe("reviews — image annotations", () => {
  let reviews: ReviewsPage;
  let withImageId: string;
  let withoutImageId: string;

  test.beforeEach(async ({ page }) => {
    const projectId = await resolveFirstProjectId();

    // GIVEN: a product_feedback annotation with an attached image
    const withImage = await seedAnnotation({
      projectId,
      withImage: true,
      metadata: {
        "feedback.css_selector": "#login-form .submit-btn",
        "feedback.viewport": "1440x900",
        "feedback.url": "http://localhost:3000/login",
      },
    });
    withImageId = withImage.annotationId;

    // GIVEN: a product_feedback annotation without an image
    const withoutImage = await seedAnnotation({ projectId, withImage: false });
    withoutImageId = withoutImage.annotationId;

    reviews = new ReviewsPage(page);
    await reviews.goto();
  });

  test("product feedback annotation with image displays thumbnail in annotation card", async () => {
    await test.step("GIVEN: reviews page is loaded with seeded annotations", async () => {
      await reviews.expectVisible();
    });

    await test.step("WHEN: viewing the annotation card with an image", async () => {
      const card = reviews.annotationCard(withImageId);
      await expect(card).toBeVisible();
    });

    await test.step("THEN: the annotation card shows a clickable thumbnail", async () => {
      const card = reviews.annotationCard(withImageId);
      await reviews.expectThumbnailVisible(card);
      const img = reviews.thumbnailImage(card);
      await expect(img).toBeVisible();
      // Image src should point to GET /api/annotations/:id/image
      await expect(img).toHaveAttribute("src", new RegExp(`/api/annotations/${withImageId}/image`));
    });
  });

  test("thumbnail click opens modal with full-size image", async () => {
    await test.step("GIVEN: an annotation card with a thumbnail is visible", async () => {
      const card = reviews.annotationCard(withImageId);
      await reviews.expectThumbnailVisible(card);
    });

    await test.step("WHEN: clicking the thumbnail", async () => {
      const card = reviews.annotationCard(withImageId);
      await reviews.clickThumbnail(card);
    });

    await test.step("THEN: a modal opens with the full-size image", async () => {
      await reviews.expectModalVisible();
      const fullImage = reviews.imageModalFullImage();
      await expect(fullImage).toBeVisible();
      await expect(fullImage).toHaveAttribute("src", new RegExp(`/api/annotations/${withImageId}/image`));
    });
  });

  test("modal shows visual metadata (CSS selector, viewport, URL)", async () => {
    await test.step("GIVEN: the image modal is open", async () => {
      const card = reviews.annotationCard(withImageId);
      await reviews.clickThumbnail(card);
      await reviews.expectModalVisible();
    });

    await test.step("THEN: the modal metadata panel shows CSS selector", async () => {
      await expect(reviews.imageModalCssSelector()).toContainText(
        "#login-form .submit-btn",
      );
    });

    await test.step("THEN: the modal metadata panel shows viewport", async () => {
      await expect(reviews.imageModalViewport()).toContainText("1440x900");
    });

    await test.step("THEN: the modal metadata panel shows page URL", async () => {
      await expect(reviews.imageModalUrl()).toContainText(
        "http://localhost:3000/login",
      );
    });
  });

  test("modal close button works", async () => {
    await test.step("GIVEN: the image modal is open", async () => {
      const card = reviews.annotationCard(withImageId);
      await reviews.clickThumbnail(card);
      await reviews.expectModalVisible();
    });

    await test.step("WHEN: clicking the X close button", async () => {
      await reviews.closeModalViaButton();
    });

    await test.step("THEN: the modal is closed", async () => {
      await reviews.expectModalHidden();
    });
  });

  test("annotations without images render normally (no thumbnail)", async () => {
    await test.step("GIVEN: an annotation without an attached image", async () => {
      const card = reviews.annotationCard(withoutImageId);
      await expect(card).toBeVisible();
    });

    await test.step("THEN: the annotation card does not show a thumbnail", async () => {
      const card = reviews.annotationCard(withoutImageId);
      await reviews.expectThumbnailHidden(card);
    });

    await test.step("THEN: the annotation card still shows its comment text", async () => {
      const card = reviews.annotationCard(withoutImageId);
      await expect(card.locator(".annotation-comment")).toBeVisible();
    });
  });

  test("product feedback badge shows 'Feedback' with warning styling", async () => {
    await test.step("GIVEN: a product_feedback annotation is visible", async () => {
      const card = reviews.annotationCard(withImageId);
      await expect(card).toBeVisible();
    });

    await test.step("THEN: the source badge shows 'Feedback'", async () => {
      const card = reviews.annotationCard(withImageId);
      await reviews.expectSourceBadgeText(card, "Feedback");
    });

    await test.step("THEN: the source badge has warning styling", async () => {
      const card = reviews.annotationCard(withImageId);
      await reviews.expectSourceBadgeWarningStyle(card);
    });
  });
});
