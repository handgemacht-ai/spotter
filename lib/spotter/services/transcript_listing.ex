defmodule Spotter.Services.TranscriptListing do
  @moduledoc "Paginated, sortable, searchable listing over discovered transcripts."

  alias Spotter.Services.TranscriptDiscovery

  require OpenTelemetry.Tracer

  @default_page 1
  @default_per_page 20

  @doc """
  Lists discovered transcripts with pagination, sorting, and text search.

  Options:
  - `:page` — page number (default 1)
  - `:per_page` — entries per page (default 20)
  - `:sort_by` — `:last_modified` (default), `:message_count`, or `:project_name`
  - `:sort_dir` — `:desc` (default) or `:asc`
  - `:project_filter` — exact project name match
  - `:search` — case-insensitive substring across title, prompt, project, summary
  - `:transcript_roots` — pass-through to TranscriptDiscovery
  """
  def list(opts \\ []) do
    page = Keyword.get(opts, :page, @default_page)
    per_page = Keyword.get(opts, :per_page, @default_per_page)
    sort_by = Keyword.get(opts, :sort_by, :last_modified)
    sort_dir = Keyword.get(opts, :sort_dir, :desc)
    project_filter = Keyword.get(opts, :project_filter)
    search = Keyword.get(opts, :search)

    discovery_opts =
      opts
      |> Keyword.take([:transcript_roots, :project_filter])

    OpenTelemetry.Tracer.with_span "spotter.transcript_listing.list",
                                   %{
                                     attributes: %{
                                       "page" => page,
                                       "per_page" => per_page,
                                       "sort_by" => to_string(sort_by),
                                       "project_filter" => project_filter || "none",
                                       "search_query" => search || "none"
                                     }
                                   } do
      filtered =
        discovery_opts
        |> TranscriptDiscovery.discover()
        |> apply_search(search)
        |> apply_sort(sort_by, sort_dir)

      total_count = length(filtered)
      entries = Enum.slice(filtered, (page - 1) * per_page, per_page)

      OpenTelemetry.Tracer.set_attribute("total_count", total_count)

      %{entries: entries, total_count: total_count, page: page, per_page: per_page}
    end
  end

  @doc """
  Returns a sorted list of unique project names from discovered transcripts.
  """
  def list_project_names(opts \\ []) do
    TranscriptDiscovery.list_project_names(opts)
  end

  defp apply_search(previews, nil), do: previews
  defp apply_search(previews, ""), do: previews

  defp apply_search(previews, query) do
    downcased = String.downcase(query)

    Enum.filter(previews, fn p ->
      matches?(p.custom_title, downcased) or
        matches?(p.first_prompt, downcased) or
        matches?(p.project_name, downcased) or
        matches?(p.summary, downcased)
    end)
  end

  defp matches?(nil, _query), do: false
  defp matches?(value, query), do: String.contains?(String.downcase(value), query)

  defp apply_sort(previews, sort_by, sort_dir) do
    sorter = sort_fn(sort_by)

    case sort_dir do
      :asc -> Enum.sort_by(previews, sorter, :asc)
      _ -> Enum.sort_by(previews, sorter, :desc)
    end
  end

  defp sort_fn(:last_modified), do: & &1.last_modified
  defp sort_fn(:message_count), do: & &1.message_count
  defp sort_fn(:project_name), do: & &1.project_name
  defp sort_fn(_), do: & &1.last_modified
end
