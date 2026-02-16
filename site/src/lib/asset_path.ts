const rawBaseUrl = import.meta.env.BASE_URL ?? "/";

function normalizeBaseUrl(baseUrl: string): string {
  const trimmed = baseUrl.trim();

  if (trimmed === "" || trimmed === "/") {
    return "";
  }

  return `/${trimmed.replace(/^\/+|\/+$/g, "")}`;
}

export function assetPath(relativePath: string): string {
  const cleanRelativePath = relativePath.replace(/^\/+/, "");
  const baseUrl = normalizeBaseUrl(rawBaseUrl);
  return `${baseUrl}/${cleanRelativePath}`;
}

export function screenshotPath(name: string, extension: "png" | "webp"): string {
  return assetPath(`screenshots/${name}.${extension}`);
}
