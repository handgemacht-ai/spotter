import { expect, type Page } from "@playwright/test";

export async function waitForLiveViewReady(page: Page, rootTestId: string): Promise<void> {
  await expect(page.getByTestId(rootTestId)).toBeVisible();

  await page.waitForFunction(() => {
    const body = document.body;
    const html = document.documentElement;

    const connected =
      body.classList.contains("phx-connected") ||
      html.classList.contains("phx-connected") ||
      document.querySelector(".phx-connected") !== null;

    const loading =
      body.classList.contains("phx-loading") ||
      html.classList.contains("phx-loading") ||
      document.querySelector(".phx-loading") !== null;

    return connected && !loading;
  });

  await page.evaluate(async () => {
    if ("fonts" in document && "ready" in document.fonts) {
      await document.fonts.ready;
    }
  });
}

export async function prepareFullPageSnapshot(page: Page): Promise<void> {
  await page.addStyleTag({
    content: `
      * {
        animation: none !important;
        transition: none !important;
        caret-color: transparent !important;
      }

      [data-testid="dashboard-root"] .project-section td:nth-child(6) > div:first-child {
        visibility: hidden !important;
      }

      [data-testid="history-root"] .history-commit-time,
      [data-testid="reviews-root"] .annotation-time {
        visibility: hidden !important;
      }
    `,
  });
}
