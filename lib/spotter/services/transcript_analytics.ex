defmodule Spotter.Services.TranscriptAnalytics do
  @moduledoc "Analytics service for querying, inspecting, and comparing tool call runs."

  require Ash.Query
  require OpenTelemetry.Tracer

  alias Spotter.Transcripts.{Message, ToolCallRun}

  @default_limit 50
  @batch_size 500

  @doc """
  Derives ToolCallRun records from a session's messages.

  Walks messages in ordinal order, pairs tool_use blocks with tool_result blocks,
  and upserts ToolCallRun records.
  """
  def derive_runs!(session) do
    OpenTelemetry.Tracer.with_span "spotter.transcript_analytics.derive_runs" do
      OpenTelemetry.Tracer.set_attribute("session_id", session.id)

      messages =
        Message
        |> Ash.Query.filter(session_id == ^session.id and is_nil(subagent_id))
        |> Ash.Query.sort(ordinal: :asc_nils_last, timestamp: :asc)
        |> Ash.read!()

      # Build tool_use_id → tool_use info map from assistant/tool_use messages
      tool_uses = extract_tool_uses(messages)

      # Build tool_use_id → tool_result info map
      tool_results = extract_tool_result_info(messages)

      # Create ToolCallRun records by pairing uses with results
      runs =
        Enum.map(tool_uses, fn {tool_use_id, use_info} ->
          result_info = Map.get(tool_results, tool_use_id, %{})
          build_run_attrs(tool_use_id, use_info, result_info, session)
        end)

      runs
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(fn batch ->
        Ash.bulk_create!(batch, ToolCallRun, :upsert, return_records?: false)
      end)

      length(runs)
    end
  end

  defp extract_tool_uses(messages) do
    messages
    |> Enum.flat_map(&tool_use_pairs_from_message/1)
    |> Map.new()
  end

  defp tool_use_pairs_from_message(msg) do
    msg.content
    |> content_blocks()
    |> Enum.filter(&(is_map(&1) && &1["type"] == "tool_use" && is_binary(&1["id"])))
    |> Enum.map(fn block ->
      {block["id"],
       %{
         tool_name: block["name"] || "Unknown",
         command: extract_command(block),
         input_summary: extract_input_summary(block),
         started_at: msg.timestamp,
         start_ordinal: msg.ordinal,
         source_scope: msg.source_scope,
         agent_id: msg.agent_id
       }}
    end)
  end

  defp extract_tool_result_info(messages) do
    messages
    |> Enum.flat_map(&tool_result_pairs_from_message/1)
    |> Map.new()
  end

  defp tool_result_pairs_from_message(msg) do
    msg.content
    |> content_blocks()
    |> Enum.filter(&(is_map(&1) && &1["type"] == "tool_result" && is_binary(&1["tool_use_id"])))
    |> Enum.map(fn block ->
      {block["tool_use_id"],
       %{
         is_error: block["is_error"] == true,
         finished_at: msg.timestamp,
         end_ordinal: msg.ordinal
       }}
    end)
  end

  defp content_blocks(%{"blocks" => blocks}) when is_list(blocks), do: blocks
  defp content_blocks(_), do: []

  defp build_run_attrs(tool_use_id, use_info, result_info, session) do
    status =
      cond do
        result_info[:is_error] == true -> :error
        result_info[:finished_at] != nil -> :completed
        use_info[:started_at] == nil -> :orphan
        true -> :ongoing
      end

    duration_ms =
      if use_info[:started_at] && result_info[:finished_at] do
        DateTime.diff(result_info[:finished_at], use_info[:started_at], :millisecond)
      end

    %{
      tool_use_id: tool_use_id,
      tool_name: use_info.tool_name,
      command: use_info[:command],
      command_fingerprint: normalize_fingerprint(use_info[:command]),
      input_summary: use_info[:input_summary],
      status: status,
      started_at: use_info[:started_at],
      finished_at: result_info[:finished_at],
      duration_ms: duration_ms,
      start_ordinal: use_info[:start_ordinal],
      end_ordinal: result_info[:end_ordinal],
      source_scope: use_info[:source_scope],
      agent_id: use_info[:agent_id],
      session_id: session.id,
      project_id: session.project_id,
      worktree_name: extract_worktree_name(session.cwd),
      canonical_cwd: session.cwd
    }
  end

  defp extract_command(block) do
    case get_in(block, ["input", "command"]) do
      cmd when is_binary(cmd) -> String.slice(cmd, 0, 500)
      _ -> nil
    end
  end

  defp extract_input_summary(block) do
    case block["input"] do
      input when is_map(input) ->
        input
        |> Map.take(["file_path", "pattern", "command", "description"])
        |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{String.slice(to_string(v), 0, 80)}" end)
        |> String.slice(0, 200)

      _ ->
        nil
    end
  end

  defp normalize_fingerprint(nil), do: nil

  defp normalize_fingerprint(cmd) do
    cmd
    |> String.replace(~r{/[^\s]+/}, "<path>/")
    |> String.replace(~r{\s+}, " ")
    |> String.trim()
    |> String.slice(0, 200)
  end

  defp extract_worktree_name(nil), do: nil

  defp extract_worktree_name(cwd) do
    cwd |> Path.basename()
  end

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
