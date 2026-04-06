defmodule Spotter.Services.TranscriptHealth do
  @moduledoc """
  Cache miss detection, token waste analysis, and session health metrics.
  Ported from touchstone doctor (Go).
  """

  require Ash.Query
  require OpenTelemetry.Tracer

  alias Spotter.Transcripts.{Message, Session}

  @cache_miss_min_context 200_000
  @cache_miss_drop_threshold 0.80
  @cache_miss_gap_seconds 300
  @jump_threshold 5_000
  @continued_cache_ratio 0.80

  @doc "Analyze session health: cache misses, token waste, and summary metrics."
  def analyze_session(session_id) do
    OpenTelemetry.Tracer.with_span "spotter.transcript_health.analyze_session" do
      session =
        Session
        |> Ash.Query.filter(session_id == ^session_id)
        |> Ash.read_one!()

      if session do
        messages = load_usage_messages(session)
        analyze_messages(messages, session)
      else
        {:error, :not_found}
      end
    end
  end

  @doc "Analyze health across sessions in a project."
  def analyze_project(opts) do
    OpenTelemetry.Tracer.with_span "spotter.transcript_health.analyze_project" do
      sessions = load_sessions(opts)

      results =
        Enum.map(sessions, fn session ->
          messages = load_usage_messages(session)
          {session, analyze_messages(messages, session)}
        end)

      aggregate_results(results)
    end
  end

  defp load_sessions(opts) do
    Session
    |> Ash.Query.new()
    |> maybe_filter_project(opts[:project_id])
    |> maybe_filter_since_session(opts[:since])
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.Query.limit(opts[:limit] || 50)
    |> Ash.read!()
  end

  defp load_usage_messages(session) do
    Message
    |> Ash.Query.filter(
      session_id == ^session.id and is_nil(subagent_id) and not is_nil(input_tokens)
    )
    |> Ash.Query.sort(ordinal: :asc_nils_last)
    |> Ash.read!()
  end

  defp analyze_messages([], _session) do
    %{
      message_count: 0,
      cache_misses: [],
      jumps: [],
      cache_window: default_cache_window(),
      summary: empty_summary()
    }
  end

  defp analyze_messages(messages, _session) do
    cache_window = detect_cache_window(messages)
    {jumps, summary} = analyze_token_flow(messages)
    cache_misses = detect_cache_misses(messages, cache_window)

    %{
      message_count: length(messages),
      cache_misses: cache_misses,
      jumps: jumps,
      cache_window: cache_window,
      summary: summary
    }
  end

  # --- Cache Window Detection ---
  # Scans newest-to-oldest to find which cache TTL tier is active.

  defp detect_cache_window(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg ->
      raw = msg.raw_payload || %{}
      cache_creation = get_in(raw, ["message", "usage", "cache_creation"]) || %{}
      c5m = cache_creation["ephemeral_5m_input_tokens"] || 0
      c1h = cache_creation["ephemeral_1h_input_tokens"] || 0

      cond do
        c5m > 0 -> %{tier: "5m cache", idle_window_seconds: 300}
        c1h > 0 -> %{tier: "1h cache", idle_window_seconds: 3600}
        true -> nil
      end
    end)
    |> Kernel.||(default_cache_window())
  end

  defp default_cache_window, do: %{tier: "legacy 5m fallback", idle_window_seconds: 300}

  # --- Cache Miss Detection ---
  # Flags when cache_read drops >80% with sufficient gap and context.

  defp detect_cache_misses(messages, cache_window) do
    messages
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [prev, curr] ->
      maybe_cache_miss(prev, curr, cache_window)
    end)
  end

  defp maybe_cache_miss(prev, curr, _cache_window) do
    prev_cache_read = prev.cache_read_input_tokens || 0
    curr_cache_read = curr.cache_read_input_tokens || 0
    curr_ctx = context_size(curr)
    prev_ctx = context_size(prev)
    gap = timestamp_gap_seconds(prev.timestamp, curr.timestamp)

    drop =
      if prev_cache_read > 0, do: (prev_cache_read - curr_cache_read) / prev_cache_read, else: 0.0

    if curr_ctx >= @cache_miss_min_context and
         prev_cache_read > 0 and
         prev_ctx != 0 and
         drop > @cache_miss_drop_threshold and
         gap >= @cache_miss_gap_seconds do
      [
        %{
          timestamp: curr.timestamp,
          gap_seconds: gap,
          context_size: curr_ctx,
          cache_read_before: prev_cache_read,
          cache_read_after: curr_cache_read,
          ordinal: curr.ordinal
        }
      ]
    else
      []
    end
  end

  # --- Token Flow Analysis ---
  # Detects context-size jumps and computes session summary.

  defp analyze_token_flow(messages) do
    initial = %{
      prev_ctx: 0,
      first?: true,
      jumps: [],
      peak_context: 0,
      total_output: 0,
      startup_context: 0,
      is_continued: false
    }

    state =
      Enum.reduce(messages, initial, fn msg, acc ->
        ctx = context_size(msg)
        delta = ctx - acc.prev_ctx
        output = msg.output_tokens || 0

        acc
        |> Map.merge(%{
          peak_context: max(acc.peak_context, ctx),
          total_output: acc.total_output + output
        })
        |> process_message_flow(msg, ctx, delta)
        |> Map.put(:prev_ctx, ctx)
      end)

    jumps = Enum.reverse(state.jumps)

    summary = %{
      total_input: state.prev_ctx,
      total_output: state.total_output,
      peak_context: state.peak_context,
      startup_context: state.startup_context,
      is_continued: state.is_continued,
      total_waste:
        jumps |> Enum.reject(& &1.is_post_compaction) |> Enum.map(& &1.delta) |> Enum.sum()
    }

    {jumps, summary}
  end

  defp process_message_flow(%{first?: true} = acc, msg, ctx, _delta) do
    cache_ratio = if ctx > 0, do: (msg.cache_read_input_tokens || 0) / ctx, else: 0.0

    %{
      acc
      | first?: false,
        startup_context: ctx,
        is_continued: cache_ratio >= @continued_cache_ratio
    }
  end

  defp process_message_flow(acc, msg, ctx, delta), do: maybe_add_jump(acc, msg, ctx, delta)

  defp maybe_add_jump(acc, msg, ctx, delta) when delta >= @jump_threshold do
    is_post_compaction = acc.prev_ctx == 0

    jump = %{
      timestamp: msg.timestamp,
      delta: delta,
      context_before: acc.prev_ctx,
      context_after: ctx,
      is_post_compaction: is_post_compaction,
      model: msg.model,
      ordinal: msg.ordinal
    }

    %{acc | jumps: [jump | acc.jumps]}
  end

  defp maybe_add_jump(acc, _msg, _ctx, _delta), do: acc

  defp empty_summary do
    %{
      total_input: 0,
      total_output: 0,
      peak_context: 0,
      startup_context: 0,
      is_continued: false,
      total_waste: 0
    }
  end

  # --- Helpers ---

  defp context_size(msg) do
    (msg.input_tokens || 0) + (msg.cache_creation_input_tokens || 0) +
      (msg.cache_read_input_tokens || 0)
  end

  defp timestamp_gap_seconds(nil, _), do: 0
  defp timestamp_gap_seconds(_, nil), do: 0

  defp timestamp_gap_seconds(t1, t2) do
    gap = DateTime.diff(t2, t1, :second)
    max(0, gap)
  end

  defp maybe_filter_project(query, nil), do: query
  defp maybe_filter_project(query, id), do: Ash.Query.filter(query, project_id == ^id)

  defp maybe_filter_since_session(query, nil), do: query

  defp maybe_filter_since_session(query, since) when is_binary(since) do
    case Date.from_iso8601(since) do
      {:ok, date} ->
        dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        Ash.Query.filter(query, started_at >= ^dt)

      _ ->
        query
    end
  end

  # --- Project-Level Aggregation ---

  defp aggregate_results(results) do
    sessions =
      Enum.map(results, fn {session, analysis} ->
        %{
          session_id: session.session_id,
          message_count: analysis.message_count,
          cache_misses: length(analysis.cache_misses),
          jumps: length(analysis.jumps),
          cache_window: analysis.cache_window,
          summary: analysis.summary
        }
      end)

    total_misses = sessions |> Enum.map(& &1.cache_misses) |> Enum.sum()
    total_jumps = sessions |> Enum.map(& &1.jumps) |> Enum.sum()
    total_waste = sessions |> Enum.map(&get_in(&1, [:summary, :total_waste])) |> Enum.sum()

    peak =
      sessions
      |> Enum.map(&get_in(&1, [:summary, :peak_context]))
      |> Enum.max(fn -> 0 end)

    %{
      session_count: length(sessions),
      total_cache_misses: total_misses,
      total_jumps: total_jumps,
      total_waste_tokens: total_waste,
      peak_context: peak,
      sessions: sessions
    }
  end
end
