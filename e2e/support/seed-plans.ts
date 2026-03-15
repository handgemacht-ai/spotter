import { request } from "@playwright/test";

const BASE_URL = process.env.SPOTTER_BASE_URL ?? "http://127.0.0.1:1100";

/**
 * Seed deterministic Plans Navigation test data via the E2E seed API.
 * Call in test.beforeAll to ensure Dolt data exists before tests run.
 */
export async function seedPlans(): Promise<void> {
  const ctx = await request.newContext({ baseURL: BASE_URL });
  const res = await ctx.post("/api/e2e/seed-plans", {
    data: { scenario: "plans-navigation" },
  });
  if (!res.ok()) {
    throw new Error(`seed-plans failed: ${res.status()} ${await res.text()}`);
  }
  await ctx.dispose();
}

/**
 * Clean up Plans Navigation test data.
 * Call in test.afterAll to remove the e2e_plans Dolt database.
 */
export async function cleanupPlans(): Promise<void> {
  const ctx = await request.newContext({ baseURL: BASE_URL });
  const res = await ctx.delete("/api/e2e/seed-plans");
  if (!res.ok()) {
    throw new Error(
      `cleanup-plans failed: ${res.status()} ${await res.text()}`,
    );
  }
  await ctx.dispose();
}
