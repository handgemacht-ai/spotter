defmodule Spotter.Services.TranscriptAnalytics do
  @moduledoc "Analytics service for querying, inspecting, and comparing tool call runs."

  require Ash.Query
  require OpenTelemetry.Tracer

  alias Spotter.Transcripts.ToolCallRun

  @default_limit 50

  @doc "Search tool call runs with dynamic filters."
  def search(opts \\ %{}) do
    OpenTelemetry.Tracer.with_span "spotter.transcript_analytics.search" do
      query =
        ToolCallRun
        |> Ash.Query.new()
        |> maybe_filter(:project_id, opts[:project_id])
        |> maybe_filter(:session_id, opts[:session_id])
        |> maybe_filter_tool(opts[:tool])
        |> maybe_filter_command_contains(opts[:command_contains])
        |> maybe_filter_min_duration(opts[:min_duration_ms])
        |> maybe_filter_max_duration(opts[:max_duration_ms])
        |> maybe_filter_status(opts[:status])
        |> maybe_filter(:worktree_name, opts[:worktree_name])
        |> Ash.Query.limit(opts[:limit] || @default_limit)
        |> Ash.Query.load(:ingest_status)

      Ash.read(query)
    end
  end

  @doc "Inspect tool call runs for a session, optionally filtered by tool_use_id."
  def inspect(opts) do
    OpenTelemetry.Tracer.with_span "spotter.transcript_analytics.inspect" do
      session_id = opts[:session_id]

      query =
        ToolCallRun
        |> Ash.Query.new()
        |> Ash.Query.filter(session_id == ^session_id)
        |> maybe_filter_tool_use_id(opts[:tool_use_id])

      Ash.read(query)
    end
  end

  @doc "Compare tool runs between two session cohorts."
  def compare(opts) do
    OpenTelemetry.Tracer.with_span "spotter.transcript_analytics.compare" do
      left_sessions = opts[:left_sessions] || []
      right_sessions = opts[:right_sessions] || []

      cond do
        left_sessions == [] ->
          {:error, :empty_cohort}

        right_sessions == [] ->
          {:error, :empty_cohort}

        true ->
          group_by = opts[:group_by] || :tool_name

          with {:ok, left_runs} <- fetch_cohort_runs(left_sessions, opts),
               {:ok, right_runs} <- fetch_cohort_runs(right_sessions, opts) do
            left_groups = group_runs(left_runs, group_by)
            right_groups = group_runs(right_runs, group_by)

            {:ok, %{left: left_groups, right: right_groups}}
          end
      end
    end
  end

  defp fetch_cohort_runs(session_ids, opts) do
    query =
      ToolCallRun
      |> Ash.Query.new()
      |> Ash.Query.filter(session_id in ^session_ids)
      |> maybe_filter_tool(opts[:tool])
      |> maybe_filter_command_contains(opts[:command_contains])

    Ash.read(query)
  rescue
    _ -> {:ok, []}
  end

  defp group_runs(runs, group_key) do
    runs
    |> Enum.group_by(&Map.get(&1, group_key))
    |> Enum.map(fn {key, group_runs} ->
      durations = group_runs |> Enum.map(& &1.duration_ms) |> Enum.reject(&is_nil/1)

      avg =
        if durations != [] do
          Enum.sum(durations) |> div(length(durations))
        end

      %{
        key: key,
        count: length(group_runs),
        avg_duration_ms: avg
      }
    end)
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, :project_id, value),
    do: Ash.Query.filter(query, project_id == ^value)

  defp maybe_filter(query, :session_id, value),
    do: Ash.Query.filter(query, session_id == ^value)

  defp maybe_filter(query, :worktree_name, value),
    do: Ash.Query.filter(query, worktree_name == ^value)

  defp maybe_filter_tool(query, nil), do: query
  defp maybe_filter_tool(query, tool), do: Ash.Query.filter(query, tool_name == ^tool)

  defp maybe_filter_command_contains(query, nil), do: query

  defp maybe_filter_command_contains(query, text),
    do: Ash.Query.filter(query, contains(command, ^text))

  defp maybe_filter_min_duration(query, nil), do: query

  defp maybe_filter_min_duration(query, min),
    do: Ash.Query.filter(query, duration_ms >= ^min)

  defp maybe_filter_max_duration(query, nil), do: query

  defp maybe_filter_max_duration(query, max),
    do: Ash.Query.filter(query, duration_ms <= ^max)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: Ash.Query.filter(query, status == ^status)

  defp maybe_filter_tool_use_id(query, nil), do: query

  defp maybe_filter_tool_use_id(query, tool_use_id),
    do: Ash.Query.filter(query, tool_use_id == ^tool_use_id)
end
