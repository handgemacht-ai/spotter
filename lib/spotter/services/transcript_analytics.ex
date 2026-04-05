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
      error_content =
        if block["is_error"] == true do
          block["content"] |> extract_error_text() |> String.slice(0, 2000)
        end

      {block["tool_use_id"],
       %{
         is_error: block["is_error"] == true,
         error_content: error_content,
         finished_at: msg.timestamp,
         end_ordinal: msg.ordinal
       }}
    end)
  end

  defp extract_error_text(content) when is_binary(content), do: content

  defp extract_error_text(content) when is_list(content) do
    Enum.map_join(content, "\n", fn
      %{"text" => text} -> text
      other when is_binary(other) -> other
      _ -> ""
    end)
  end

  defp extract_error_text(_), do: ""

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
      error_content: result_info[:error_content],
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
        |> maybe_filter_error_contains(opts[:error_contains])
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
      tool_use_id = opts[:tool_use_id]
      context = opts[:context]
      status_filter = opts[:status_filter]
      with_messages? = opts[:with_messages] == true

      with {:ok, all_runs} <-
             ToolCallRun
             |> Ash.Query.new()
             |> Ash.Query.filter(session_id == ^session_id)
             |> maybe_filter_tool_use_id(tool_use_id)
             |> Ash.Query.sort(start_ordinal: :asc_nils_last)
             |> Ash.read() do
        runs =
          cond do
            tool_use_id && context ->
              context_window(all_runs, tool_use_id, context)

            status_filter && context ->
              status_context_window(all_runs, status_filter, context)

            status_filter ->
              Enum.filter(all_runs, &(&1.status == status_filter))

            true ->
              all_runs
          end

        runs =
          if with_messages? do
            attach_messages(runs, session_id)
          else
            runs
          end

        {:ok, runs}
      end
    end
  end

  defp context_window(runs, tool_use_id, context) do
    case Enum.find_index(runs, &(&1.tool_use_id == tool_use_id)) do
      nil ->
        []

      idx ->
        start_idx = max(0, idx - context)
        end_idx = min(length(runs) - 1, idx + context)
        Enum.slice(runs, start_idx..end_idx)
    end
  end

  defp status_context_window(runs, status, context) do
    matching_indices =
      runs
      |> Enum.with_index()
      |> Enum.filter(fn {run, _idx} -> run.status == status end)
      |> Enum.map(&elem(&1, 1))

    included =
      matching_indices
      |> Enum.flat_map(fn idx ->
        max(0, idx - context)..min(length(runs) - 1, idx + context)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    Enum.map(included, &Enum.at(runs, &1))
  end

  defp attach_messages(runs, session_id) do
    ordinals =
      runs
      |> Enum.flat_map(fn run ->
        start_ord = run.start_ordinal || 0
        [max(0, start_ord - 1), start_ord, run.end_ordinal || start_ord]
      end)

    {min_ord, max_ord} = Enum.min_max(ordinals)

    messages =
      Message
      |> Ash.Query.filter(
        session_id == ^session_id and ordinal >= ^min_ord and ordinal <= ^max_ord
      )
      |> Ash.Query.sort(ordinal: :asc)
      |> Ash.read!()

    msg_by_ordinal = Enum.group_by(messages, & &1.ordinal)

    Enum.map(runs, fn run ->
      start_ord = run.start_ordinal || 0
      preceding_ord = max(0, start_ord - 1)

      preceding_msgs =
        Map.get(msg_by_ordinal, preceding_ord, [])
        |> Enum.map(&message_summary/1)

      result_msgs =
        if run.end_ordinal do
          Map.get(msg_by_ordinal, run.end_ordinal, [])
          |> Enum.map(&message_summary/1)
        else
          []
        end

      Map.put(run, :__messages__, %{
        preceding: preceding_msgs,
        result: result_msgs
      })
    end)
  end

  defp message_summary(msg) do
    text =
      msg.content
      |> content_blocks()
      |> Enum.map_join("\n", fn
        %{"type" => "text", "text" => text} -> String.slice(text, 0, 500)
        %{"type" => type} -> "[#{type}]"
        _ -> ""
      end)
      |> String.slice(0, 800)

    %{role: msg.role, type: msg.type, ordinal: msg.ordinal, text: text}
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

  defp maybe_filter_error_contains(query, nil), do: query

  defp maybe_filter_error_contains(query, text),
    do: Ash.Query.filter(query, contains(error_content, ^text))

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

  # --- Aggregate ---

  @doc "Cross-session aggregation of tool call runs."
  def aggregate(opts \\ %{}) do
    OpenTelemetry.Tracer.with_span "spotter.transcript_analytics.aggregate" do
      runs = fetch_all_runs(opts)
      group_keys = parse_group_keys(opts[:group_by])
      tool_groups = aggregate_groups(runs, group_keys)
      top_errors = aggregate_errors(runs, opts[:top_errors] || 10)
      session_count = runs |> Enum.map(& &1.session_id) |> Enum.uniq() |> length()

      %{
        session_count: session_count,
        total_runs: length(runs),
        groups: tool_groups,
        top_errors: top_errors
      }
    end
  end

  defp fetch_all_runs(opts) do
    ToolCallRun
    |> Ash.Query.new()
    |> maybe_filter(:project_id, opts[:project_id])
    |> maybe_filter_tool(opts[:tool])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_since(opts[:since])
    |> Ash.read!()
  end

  defp parse_group_keys(nil), do: [:tool_name]
  defp parse_group_keys(keys) when is_list(keys), do: keys
  defp parse_group_keys(key) when is_atom(key), do: [key]

  defp parse_group_keys(str) when is_binary(str) do
    str |> String.split(",") |> Enum.map(&String.to_existing_atom(String.trim(&1)))
  end

  defp aggregate_groups(runs, group_keys) do
    runs
    |> Enum.group_by(fn run -> Enum.map(group_keys, &Map.get(run, &1)) end)
    |> Enum.map(fn {key_values, group} ->
      durations = group |> Enum.map(& &1.duration_ms) |> Enum.reject(&is_nil/1)
      errors = Enum.count(group, &(&1.status == :error))

      total = length(group)

      %{
        key: Enum.zip(group_keys, key_values) |> Map.new(),
        count: total,
        errors: errors,
        error_pct: if(total > 0, do: Float.round(errors / total * 100, 1), else: 0.0),
        avg_duration_ms: percentile(durations, 50),
        p95_duration_ms: percentile(durations, 95)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp aggregate_errors(runs, top_n) do
    runs
    |> Enum.filter(&(&1.status == :error and is_binary(&1.error_content)))
    |> Enum.group_by(&normalize_error(&1.error_content))
    |> Enum.map(fn {fingerprint, group} ->
      %{
        fingerprint: fingerprint,
        count: length(group),
        tool_name: group |> hd() |> Map.get(:tool_name),
        sample: group |> hd() |> Map.get(:error_content) |> String.slice(0, 200)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(top_n)
  end

  defp normalize_error(content) do
    content
    |> String.replace(~r{/[^\s:]+/[^\s:]+}, "<path>")
    |> String.replace(~r{\d+}, "N")
    |> String.slice(0, 120)
  end

  defp percentile([], _), do: nil

  defp percentile(values, pct) do
    sorted = Enum.sort(values)
    idx = max(0, ceil(length(sorted) * pct / 100) - 1)
    Enum.at(sorted, idx)
  end

  defp maybe_filter_since(query, nil), do: query

  defp maybe_filter_since(query, since) when is_binary(since) do
    case Date.from_iso8601(since) do
      {:ok, date} ->
        dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        Ash.Query.filter(query, started_at >= ^dt)

      _ ->
        query
    end
  end

  # --- Error Analysis ---

  @doc "Focused error analysis with fingerprinting and context."
  def error_analysis(opts \\ %{}) do
    OpenTelemetry.Tracer.with_span "spotter.transcript_analytics.error_analysis" do
      top_n = opts[:top] || 20
      classify? = opts[:classify] == true

      error_runs =
        ToolCallRun
        |> Ash.Query.new()
        |> Ash.Query.filter(status == :error)
        |> maybe_filter(:project_id, opts[:project_id])
        |> maybe_filter(:session_id, opts[:session_id])
        |> maybe_filter_tool(opts[:tool])
        |> maybe_filter_since(opts[:since])
        |> Ash.Query.sort(started_at: :desc)
        |> Ash.read!()

      tool_totals =
        if classify? do
          fetch_tool_totals(opts)
        else
          %{}
        end

      error_runs
      |> Enum.group_by(&{&1.tool_name, normalize_error(&1.error_content || "")})
      |> Enum.map(fn {{tool, fingerprint}, group} ->
        sorted = Enum.sort_by(group, & &1.started_at, {:desc, DateTime})
        sample_content = sorted |> hd() |> Map.get(:error_content) |> to_string()

        base = %{
          tool_name: tool,
          fingerprint: fingerprint,
          count: length(group),
          first_seen: sorted |> List.last() |> Map.get(:started_at),
          last_seen: sorted |> hd() |> Map.get(:started_at),
          sample_error: String.slice(sample_content, 0, 300),
          sample_sessions: sorted |> Enum.map(& &1.session_id) |> Enum.uniq() |> Enum.take(3)
        }

        if classify? do
          category = classify_error(sample_content)
          total = Map.get(tool_totals, tool, 0)

          Map.merge(base, %{
            category: category,
            preventability: error_preventability(category),
            total_tool_calls: total,
            error_rate: if(total > 0, do: Float.round(length(group) / total * 100, 2), else: 0.0)
          })
        else
          base
        end
      end)
      |> Enum.sort_by(& &1.count, :desc)
      |> Enum.take(top_n)
    end
  end

  defp fetch_tool_totals(opts) do
    ToolCallRun
    |> Ash.Query.new()
    |> maybe_filter(:project_id, opts[:project_id])
    |> maybe_filter(:session_id, opts[:session_id])
    |> maybe_filter_tool(opts[:tool])
    |> maybe_filter_since(opts[:since])
    |> Ash.read!()
    |> Enum.frequencies_by(& &1.tool_name)
  end

  @error_patterns [
    {~r/doesn't want to proceed|was rejected/i, :user_rejected},
    {~r/Sibling tool call errored/, :sibling_errored},
    {~r/hook.*BLOCKED|Hook.*denied|hook error/i, :hook_blocked},
    {~r/has not been read yet/, :file_not_read_first},
    {~r/modified since read/, :file_modified_since_read},
    {~r/does not exist|No such file|ENOENT/, :file_not_found},
    {~r/EISDIR|Path does not exist/, :path_error},
    {~r/exceeds maximum allowed tokens/, :token_limit_exceeded},
    {~r/MCP error/, :mcp_error},
    {~r/Precommit failed|pre-commit|lefthook/i, :pre_commit_failed},
    {~r/Exit code/, :exit_code}
  ]

  @doc "Classify an error content string into a category atom."
  def classify_error(nil), do: :other
  def classify_error(""), do: :other

  def classify_error(content) do
    Enum.find_value(@error_patterns, :other, fn {pattern, category} ->
      if Regex.match?(pattern, content), do: category
    end)
  end

  @doc "Map error category to preventability classification."
  def error_preventability(:file_not_read_first), do: :preventable
  def error_preventability(:file_modified_since_read), do: :preventable
  def error_preventability(:file_not_found), do: :preventable
  def error_preventability(:path_error), do: :preventable
  def error_preventability(:token_limit_exceeded), do: :preventable
  def error_preventability(:user_rejected), do: :user_driven
  def error_preventability(:hook_blocked), do: :user_driven
  def error_preventability(:sibling_errored), do: :cascading
  def error_preventability(:exit_code), do: :systemic
  def error_preventability(:mcp_error), do: :systemic
  def error_preventability(:pre_commit_failed), do: :systemic
  def error_preventability(_), do: :other

  # --- Sequence Analysis ---

  @doc "Detect recurring tool call sequences across sessions."
  def sequence_analysis(opts \\ %{}) do
    OpenTelemetry.Tracer.with_span "spotter.transcript_analytics.sequence_analysis" do
      min_length = opts[:min_length] || 3
      min_occurrences = opts[:min_occurrences] || 3
      max_ngram = opts[:max_length] || 5

      runs =
        ToolCallRun
        |> Ash.Query.new()
        |> maybe_filter(:project_id, opts[:project_id])
        |> maybe_filter_since(opts[:since])
        |> Ash.Query.sort(start_ordinal: :asc_nils_last)
        |> Ash.read!()

      sessions = Enum.group_by(runs, & &1.session_id)

      ngram_counts = count_ngrams(sessions, min_length, max_ngram)
      retry_patterns = detect_retries(sessions)

      base = %{
        session_count: map_size(sessions),
        frequent_sequences:
          ngram_counts
          |> Enum.filter(fn {_ngram, count} -> count >= min_occurrences end)
          |> Enum.sort_by(&elem(&1, 1), :desc)
          |> Enum.take(20)
          |> Enum.map(fn {ngram, count} -> %{pattern: ngram, count: count} end),
        retry_patterns:
          retry_patterns
          |> Enum.filter(fn {_pattern, count} -> count >= min_occurrences end)
          |> Enum.sort_by(&elem(&1, 1), :desc)
          |> Enum.take(20)
          |> Enum.map(fn {pattern, count} -> %{pattern: pattern, count: count} end)
      }

      if opts[:recovery] do
        Map.put(base, :recovery_stats, recovery_analysis(sessions))
      else
        base
      end
    end
  end

  defp count_ngrams(sessions, min_n, max_n) do
    sessions
    |> Enum.flat_map(fn {_session_id, runs} ->
      tool_names = Enum.map(runs, & &1.tool_name)

      len = length(tool_names)

      for n <- min_n..max_n//1, n <= len, i <- 0..(len - n)//1 do
        Enum.slice(tool_names, i, n)
      end
    end)
    |> Enum.frequencies()
  end

  defp detect_retries(sessions) do
    sessions
    |> Enum.flat_map(fn {_session_id, runs} ->
      runs
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.filter(fn [a, b] -> a.status == :error and a.tool_name == b.tool_name end)
      |> Enum.map(fn [a, _b] ->
        error_hint = (a.error_content || "") |> normalize_error() |> String.slice(0, 60)
        "#{a.tool_name} (#{error_hint}) -> #{a.tool_name}"
      end)
    end)
    |> Enum.frequencies()
  end

  defp recovery_analysis(sessions) do
    all_chains =
      sessions
      |> Enum.flat_map(fn {_session_id, runs} ->
        runs
        |> Enum.with_index()
        |> Enum.filter(fn {run, _idx} -> run.status == :error end)
        |> Enum.map(fn {error_run, idx} ->
          category = classify_error(error_run.error_content || "")
          following = Enum.slice(runs, (idx + 1)..min(idx + 5, length(runs) - 1))

          retries =
            following
            |> Enum.take_while(&(&1.tool_name == error_run.tool_name))

          recovered? = Enum.any?(retries, &(&1.status == :completed))
          retried? = retries != []

          %{
            category: category,
            retried: retried?,
            recovered: recovered?,
            retry_count: length(retries)
          }
        end)
      end)

    all_chains
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, chains} ->
      total = length(chains)
      retried = Enum.count(chains, & &1.retried)
      recovered = Enum.count(chains, & &1.recovered)
      retry_counts = chains |> Enum.filter(& &1.retried) |> Enum.map(& &1.retry_count)

      avg_retries =
        if retry_counts != [] do
          Float.round(Enum.sum(retry_counts) / length(retry_counts), 1)
        else
          0.0
        end

      %{
        category: category,
        total_errors: total,
        retry_rate: if(total > 0, do: Float.round(retried / total * 100, 1), else: 0.0),
        recovery_rate: if(retried > 0, do: Float.round(recovered / retried * 100, 1), else: 0.0),
        avg_retries: avg_retries
      }
    end)
    |> Enum.sort_by(& &1.total_errors, :desc)
  end
end
