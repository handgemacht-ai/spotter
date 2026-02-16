#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const SCREENSHOT_DIR = path.resolve(process.cwd(), "public/screenshots");

const CROPS = {
  "dashboard.png": { left: 0, top: 0, width: 1905, height: 1460 },
  "session-transcript.png": { left: 0, top: 0, width: 1905, height: 1880 },
  "reviews.png": { left: 0, top: 0, width: 1905, height: 1260 },
  "history.png": { left: 0, top: 0, width: 1905, height: 1320 },
  "commit-detail.png": { left: 0, top: 0, width: 1905, height: 1980 },
  "file-metrics.png": { left: 0, top: 0, width: 1905, height: 1500 },
  "flows.png": { left: 100, top: 0, width: 1700, height: 1200 },
  "file-detail.png": { left: 100, top: 0, width: 1700, height: 1250 },
  "specs.png": { left: 0, top: 0, width: 1905, height: 1220 }
};

function commandExists(command) {
  const result = spawnSync("sh", ["-c", `command -v ${command}`], { stdio: "ignore" });

  return result.status === 0;
}

async function cropPng(fileName, crop) {
  const filePath = path.join(SCREENSHOT_DIR, fileName);
  const metadata = await sharp(filePath).metadata();

  if (!metadata.width || !metadata.height) {
    throw new Error(`could not read dimensions for ${fileName}`);
  }

  // If the screenshot is already at the target output dimensions, skip extract.
  if (metadata.width === crop.width && metadata.height === crop.height) {
    return;
  }

  if (crop.left + crop.width > metadata.width || crop.top + crop.height > metadata.height) {
    throw new Error(
      `crop for ${fileName} (${crop.width}x${crop.height} @ ${crop.left},${crop.top}) exceeds source ${metadata.width}x${metadata.height}`
    );
  }

  const tmpPath = `${filePath}.tmp`;

  await sharp(filePath)
    .extract(crop)
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toFile(tmpPath);

  await fs.rename(tmpPath, filePath);
}

function runPngquant(filePaths) {
  if (!commandExists("pngquant")) {
    console.warn("pngquant not found; skipping pngquant optimization");
    return;
  }

  const result = spawnSync(
    "pngquant",
    ["--quality=85-98", "--speed", "1", "--strip", "--ext", ".png", "--force", ...filePaths],
    { stdio: "inherit" }
  );

  if (result.status !== 0) {
    throw new Error("pngquant failed");
  }
}

async function buildWebp(fileName) {
  const pngPath = path.join(SCREENSHOT_DIR, fileName);
  const webpPath = pngPath.replace(/\.png$/u, ".webp");

  await sharp(pngPath).webp({ quality: 86, effort: 6 }).toFile(webpPath);
}

async function printStats() {
  const files = await fs.readdir(SCREENSHOT_DIR);
  let pngBytes = 0;
  let webpBytes = 0;

  for (const fileName of files) {
    const filePath = path.join(SCREENSHOT_DIR, fileName);
    const stats = await fs.stat(filePath);

    if (fileName.endsWith(".png")) {
      pngBytes += stats.size;
    }

    if (fileName.endsWith(".webp")) {
      webpBytes += stats.size;
    }
  }

  const mb = (bytes) => (bytes / 1024 / 1024).toFixed(2);
  console.log(`PNG total: ${mb(pngBytes)} MB`);
  console.log(`WebP total: ${mb(webpBytes)} MB`);
}

async function main() {
  const fileNames = Object.keys(CROPS);

  for (const fileName of fileNames) {
    await cropPng(fileName, CROPS[fileName]);
    console.log(`cropped ${fileName}`);
  }

  runPngquant(fileNames.map((fileName) => path.join(SCREENSHOT_DIR, fileName)));

  for (const fileName of fileNames) {
    await buildWebp(fileName);
    console.log(`generated ${fileName.replace(/\.png$/u, ".webp")}`);
  }

  await printStats();
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
