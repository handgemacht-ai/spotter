import { expect, test } from "@playwright/test";
import { ImportModalPage } from "../support/pages/import-modal";
import { assertSpanEmitted } from "../support/telemetry";

test.describe("Transcript Import Modal", () => {
  let importPage: ImportModalPage;

  test.beforeEach(async ({ page }) => {
    importPage = new ImportModalPage(page);
    await importPage.gotoDashboard();
    await importPage.openModal();
  });

  test("Bug #1: checkbox stays checked after click (not cleared by re-render)", async () => {
    // Wait for transcript rows to load
    await expect(importPage.allRows().first()).toBeVisible();

    // Find first non-disabled checkbox
    const firstCheckbox = importPage.firstImportableCheckbox();
    await expect(firstCheckbox).toBeVisible();
    await expect(firstCheckbox).not.toBeDisabled();

    // Click to check it
    await firstCheckbox.click();
    await expect(firstCheckbox).toBeChecked();

    // Selection count should appear
    await importPage.expectSelectionCount("1 selected");

    // Wait for any potential LiveView re-render
    await importPage.page.waitForTimeout(500);

    // Checkbox should still be checked after re-render
    await expect(firstCheckbox).toBeChecked();
    await importPage.expectSelectionCount("1 selected");
  });

  test("Bug #4: project filter shows readable names without duplicates", async () => {
    // Wait for transcript rows to load
    await expect(importPage.allRows().first()).toBeVisible();

    const options = importPage.projectFilter.locator("option");
    const count = await options.count();

    // Collect display texts (skip "All Projects" at index 0)
    const displayTexts: string[] = [];
    for (let i = 1; i < count; i++) {
      const text = (await options.nth(i).textContent()) ?? "";
      displayTexts.push(text.trim());
    }

    // No display text should be a bare path segment like "home/marco"
    // or a bare single-word directory name that leaks from path parsing
    const knownPathSegments = new Set(["home", "marco", "projects", "usr", "var", "tmp", "opt"]);
    const nonsensical = displayTexts.filter(
      (t) =>
        t.startsWith("home/") ||
        t.startsWith("marco/") ||
        t.startsWith("projects/") ||
        knownPathSegments.has(t.toLowerCase()),
    );
    expect(
      nonsensical,
      `Filter should not show path segments as names: ${nonsensical.join(", ")}`,
    ).toHaveLength(0);

    // No duplicate display texts
    const seen = new Set<string>();
    const duplicates: string[] = [];
    for (const text of displayTexts) {
      if (seen.has(text)) duplicates.push(text);
      seen.add(text);
    }
    expect(
      duplicates,
      `Filter should not have duplicate entries: ${[...new Set(duplicates)].join(", ")}`,
    ).toHaveLength(0);
  });

  test("Bug #2: import completes without error and session appears on dashboard", async () => {
    // Wait for transcript rows to load
    await expect(importPage.allRows().first()).toBeVisible();

    // Select the first non-imported, non-disabled transcript
    const firstCheckbox = importPage.firstImportableCheckbox();
    await expect(firstCheckbox).toBeVisible();
    await expect(firstCheckbox).not.toBeDisabled();
    await firstCheckbox.click();
    await expect(firstCheckbox).toBeChecked();

    // Click import
    await importPage.expectImportEnabled();
    await importPage.importActionButton.click();

    // Import should succeed: modal closes, flash shows success
    // Currently fails: "Sync failed: error" / "No project matching cwd"
    await expect(importPage.modal).not.toBeVisible({ timeout: 30000 });

    // Flash should show success, not error
    const flash = importPage.page.locator("[role='alert']");
    await expect(flash).toContainText("Successfully imported");
  });

  test("s0p.1 telemetry: import_team emits spotter.import.team_bulk span", async () => {
    await expect(importPage.allRows().first()).toBeVisible();

    // Find a team badge and its "Import Team" button
    const teamBadge = importPage.firstTeamName();
    await expect(teamBadge).toBeVisible({ timeout: 5000 });
    const teamName = (await teamBadge.getAttribute("data-team-name")) ?? "";
    expect(teamName.length, "Team badge should have a team name").toBeGreaterThan(0);

    // Click "Import Team" to trigger the bulk selection
    const importTeamBtn = importPage.importTeamButton(teamName);
    await expect(importTeamBtn).toBeVisible();
    await importTeamBtn.click();

    // Verify the telemetry span was emitted with correct attributes (polls Jaeger with retry).
    // member_count is computed server-side across all pages, so we verify it exists and is positive
    // rather than matching a DOM count that only reflects the current page.
    const span = await assertSpanEmitted("spotter.import.team_bulk", {
      team_name: teamName,
    });

    const memberCount = span.tags.find((t) => t.key === "member_count");
    expect(memberCount, "Span must include member_count attribute").toBeDefined();
    expect(Number(memberCount!.value), "member_count must be positive").toBeGreaterThan(0);
    expect(span.duration, "Span should have a positive duration").toBeGreaterThan(0);
  });
});
