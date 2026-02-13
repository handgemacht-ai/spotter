defmodule Spotter.Services.CommitHotspotFilters do
  @moduledoc "Deterministic path eligibility filter for commit hotspot analysis."

  @default_blocked_prefixes ~w(
    .beads/
    _build/
    deps/
    node_modules/
    .git/
    tmp/
    priv/static/
    test/fixtures/
  )

  @default_blocked_extensions ~w(
    .jsonl .db .db-wal .db-shm .lock .log
    .png .jpg .jpeg .gif .pdf
    .woff .woff2 .ttf .eot
    .zip .tar .gz
  )

  @doc """
  Returns `true` if the given relative path is eligible for commit hotspot analysis.

  A path is ineligible if it matches any blocked prefix or blocked extension.
  Blocklists can be overridden via environment variables:
  - `SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_PREFIXES` (comma-separated)
  - `SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_EXTENSIONS` (comma-separated)
  """
  @spec eligible_path?(String.t()) :: boolean()
  def eligible_path?(relative_path) do
    not blocked_by_prefix?(relative_path) and not blocked_by_extension?(relative_path)
  end

  defp blocked_by_prefix?(path) do
    Enum.any?(blocked_prefixes(), &String.starts_with?(path, &1))
  end

  defp blocked_by_extension?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext != "" and ext in blocked_extensions()
  end

  @doc false
  def blocked_prefixes do
    case System.get_env("SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_PREFIXES") do
      nil -> @default_blocked_prefixes
      "" -> @default_blocked_prefixes
      val -> parse_list(val)
    end
  end

  @doc false
  def blocked_extensions do
    case System.get_env("SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_EXTENSIONS") do
      nil -> @default_blocked_extensions
      "" -> @default_blocked_extensions
      val -> val |> parse_list() |> Enum.map(&normalize_extension/1)
    end
  end

  defp parse_list(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_extension("." <> _ = ext), do: String.downcase(ext)
  defp normalize_extension(ext), do: String.downcase("." <> ext)
end
