defmodule Spotter.Services.FileMetrics do
  @moduledoc "Shared read layer for the unified File metrics page."

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Transcripts.{
    CoChangeGroup,
    Commit,
    CommitHotspot,
    FileHeatmap
  }

  @max_rows 100

  @doc "List heatmap entries ranked by `sort_by`, filtered by `min_score`."
  def list_heatmap(project_id, min_score \\ 0, sort_by \\ :heat_score, limit \\ @max_rows) do
    Tracer.with_span "spotter.file_metrics.list_heatmap" do
      Tracer.set_attribute("spotter.project_id", project_id || "all")
      Tracer.set_attribute("spotter.sort_by", Atom.to_string(sort_by))

      query =
        FileHeatmap
        |> Ash.Query.filter(heat_score >= ^min_score)
        |> Ash.Query.sort([{sort_by, :desc}])
        |> Ash.Query.limit(limit)

      query = maybe_filter_project(query, project_id)

      entries = Ash.read!(query)
      Tracer.set_attribute("spotter.row_count", length(entries))
      entries
    end
  rescue
    _ -> []
  end

  @doc "List hotspot entries enriched with commit data."
  def list_hotspots(project_id, min_score \\ 0, sort_by \\ :overall_score, limit \\ @max_rows) do
    Tracer.with_span "spotter.file_metrics.list_hotspots" do
      Tracer.set_attribute("spotter.project_id", project_id || "all")
      Tracer.set_attribute("spotter.sort_by", Atom.to_string(sort_by))

      query =
        CommitHotspot
        |> Ash.Query.filter(overall_score >= ^min_score)
        |> Ash.Query.sort([{sort_by, :desc}])
        |> Ash.Query.limit(limit)

      query = maybe_filter_project(query, project_id)

      hotspots = Ash.read!(query)
      entries = enrich_hotspots_with_commits(hotspots)
      Tracer.set_attribute("spotter.row_count", length(entries))
      entries
    end
  rescue
    _ -> []
  end

  @doc "List co-change rows for the given project and scope."
  def list_co_change_rows(project_id, scope \\ :file) do
    Tracer.with_span "spotter.file_metrics.list_co_change_rows" do
      Tracer.set_attribute("spotter.project_id", project_id || "all")
      Tracer.set_attribute("spotter.scope", Atom.to_string(scope))

      if is_nil(project_id) do
        Tracer.set_attribute("spotter.row_count", 0)
        []
      else
        groups =
          CoChangeGroup
          |> Ash.Query.filter(project_id == ^project_id and scope == ^scope)
          |> Ash.read!()

        rows = derive_co_change_rows(groups)
        Tracer.set_attribute("spotter.row_count", length(rows))
        rows
      end
    end
  rescue
    _ -> []
  end

  @doc """
  List file sizes ranked by `size_bytes` descending.

  Reads from `FileHeatmap` records that have `size_bytes` populated.
  """
  def list_file_sizes(project_id, limit \\ @max_rows) do
    Tracer.with_span "spotter.file_metrics.list_file_sizes" do
      Tracer.set_attribute("spotter.project_id", project_id || "all")

      query =
        FileHeatmap
        |> Ash.Query.filter(not is_nil(size_bytes))
        |> Ash.Query.sort(size_bytes: :desc)
        |> Ash.Query.limit(limit)

      query = maybe_filter_project(query, project_id)

      entries = Ash.read!(query)

      rows =
        Enum.map(entries, fn h ->
          %{
            project_id: h.project_id,
            member_path: h.relative_path,
            size_bytes: h.size_bytes,
            loc: h.loc,
            measured_at: h.updated_at
          }
        end)

      Tracer.set_attribute("spotter.row_count", length(rows))
      rows
    end
  rescue
    _ -> []
  end

  # --- private ---

  defp maybe_filter_project(query, nil), do: query

  defp maybe_filter_project(query, project_id),
    do: Ash.Query.filter(query, project_id == ^project_id)

  defp enrich_hotspots_with_commits([]), do: []

  defp enrich_hotspots_with_commits(hotspots) do
    commit_ids = hotspots |> Enum.map(& &1.commit_id) |> Enum.uniq()

    commits =
      Commit
      |> Ash.Query.filter(id in ^commit_ids)
      |> Ash.read!()
      |> Map.new(&{&1.id, &1})

    Enum.map(hotspots, fn h ->
      %{hotspot: h, commit: Map.get(commits, h.commit_id)}
    end)
  end

  defp derive_co_change_rows(groups) do
    groups
    |> Enum.flat_map(fn group ->
      Enum.map(group.members, fn member -> {member, group} end)
    end)
    |> Enum.group_by(fn {member, _} -> member end, fn {_, group} -> group end)
    |> Enum.map(fn {member, member_groups} ->
      max_freq = member_groups |> Enum.map(& &1.frequency_30d) |> Enum.max()

      last_seen =
        member_groups |> Enum.map(& &1.last_seen_at) |> Enum.max(DateTime, fn -> nil end)

      sorted_groups =
        Enum.sort_by(member_groups, fn g -> {-g.frequency_30d, g.group_key} end)

      %{
        member: member,
        max_frequency_30d: max_freq,
        last_seen_at: last_seen,
        groups: sorted_groups
      }
    end)
  end

end
