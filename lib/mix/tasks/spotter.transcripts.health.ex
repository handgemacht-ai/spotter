defmodule Mix.Tasks.Spotter.Transcripts.Health do
  @moduledoc "Cache miss detection, token waste analysis, and session health metrics."
  @shortdoc "Analyze transcript token health"
  use Mix.Task

  alias Spotter.Services.TranscriptHealth

  @switches [
    session: :string,
    project: :string,
    since: :string,
    limit: :integer,
    format: :string
  ]

  @impl true
  def run(args) do
    if "--help" in args do
      print_usage()
    else
      do_run(args)
    end
  end

  defp do_run(args) do
    Mix.Tasks.Spotter.CliHelpers.start_app_without_server()

    opts = Mix.Tasks.Spotter.CliHelpers.parse_args!(args, @switches, &print_usage/0)

    format = opts[:format] || "table"

    cond do
      opts[:session] ->
        print_session_health(opts[:session], format)

      opts[:project] ->
        print_project_health(opts, format)

      true ->
        print_usage()
    end
  end

  defp print_session_health(session_id, "json") do
    case TranscriptHealth.analyze_session(session_id) do
      {:error, :not_found} -> Mix.shell().error("Session not found: #{session_id}")
      result -> Mix.shell().info(Jason.encode!(result, pretty: true))
    end
  end

  defp print_session_health(session_id, _table) do
    case TranscriptHealth.analyze_session(session_id) do
      {:error, :not_found} ->
        Mix.shell().error("Session not found: #{session_id}")

      result ->
        print_session_report(session_id, result)
    end
  end

  defp print_project_health(opts, "json") do
    result =
      TranscriptHealth.analyze_project(%{
        project_id: opts[:project],
        since: opts[:since],
        limit: opts[:limit]
      })

    Mix.shell().info(Jason.encode!(result, pretty: true))
  end

  defp print_project_health(opts, _table) do
    result =
      TranscriptHealth.analyze_project(%{
        project_id: opts[:project],
        since: opts[:since],
        limit: opts[:limit]
      })

    Mix.shell().info("Health Summary (#{result.session_count} sessions):\n")
    Mix.shell().info("  Total cache misses:  #{result.total_cache_misses}")
    Mix.shell().info("  Total token jumps:   #{result.total_jumps}")
    Mix.shell().info("  Total waste tokens:  #{format_tokens(result.total_waste_tokens)}")
    Mix.shell().info("  Peak context:        #{format_tokens(result.peak_context)}")

    flagged =
      result.sessions
      |> Enum.filter(&(&1.cache_misses > 0 or &1.jumps > 0))
      |> Enum.sort_by(&(&1.cache_misses + &1.jumps), :desc)

    if flagged != [] do
      Mix.shell().info("\nSessions with issues:")

      Enum.each(flagged, fn s ->
        Mix.shell().info(
          "  #{String.slice(s.session_id, 0, 8)}.. misses=#{s.cache_misses} jumps=#{s.jumps} peak=#{format_tokens(s.summary.peak_context)} waste=#{format_tokens(s.summary.total_waste)}"
        )
      end)
    end
  end

  defp print_session_report(session_id, result) do
    s = result.summary

    Mix.shell().info("Health Report: #{session_id}\n")
    Mix.shell().info("  Messages with usage: #{result.message_count}")

    Mix.shell().info(
      "  Cache window:        #{result.cache_window.tier} (#{result.cache_window.idle_window_seconds}s)"
    )

    Mix.shell().info("  Continued session:   #{s.is_continued}")
    Mix.shell().info("  Startup context:     #{format_tokens(s.startup_context)}")
    Mix.shell().info("  Peak context:        #{format_tokens(s.peak_context)}")
    Mix.shell().info("  Total input:         #{format_tokens(s.total_input)}")
    Mix.shell().info("  Total output:        #{format_tokens(s.total_output)}")
    Mix.shell().info("  Total waste:         #{format_tokens(s.total_waste)}")

    print_cache_misses(result.cache_misses)
    print_jumps(result.jumps)
  end

  defp print_cache_misses([]), do: Mix.shell().info("\n  Cache misses: none ✓")

  defp print_cache_misses(misses) do
    Mix.shell().info("\n  Cache misses (#{length(misses)}):")

    Enum.each(misses, fn m ->
      Mix.shell().info(
        "    #{format_dt(m.timestamp)} gap=#{m.gap_seconds}s ctx=#{format_tokens(m.context_size)} cache_read: #{format_tokens(m.cache_read_before)} -> #{format_tokens(m.cache_read_after)}"
      )
    end)
  end

  defp print_jumps([]), do: Mix.shell().info("  Token jumps: none ✓")

  defp print_jumps(jumps) do
    Mix.shell().info("\n  Token jumps (#{length(jumps)}):")

    Enum.each(jumps, fn j ->
      label = if j.is_post_compaction, do: " [post-compaction]", else: ""

      Mix.shell().info(
        "    #{format_dt(j.timestamp)} delta=+#{format_tokens(j.delta)} (#{format_tokens(j.context_before)} -> #{format_tokens(j.context_after)})#{label}"
      )
    end)
  end

  defp format_tokens(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_tokens(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_tokens(n), do: "#{n}"

  defp format_dt(nil), do: "unknown"
  defp format_dt(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp print_usage do
    Mix.shell().info("""
    Usage: mix spotter.transcripts.health [options]

    Analyze cache misses, token waste, and session health.

    Options:
      --session <id>        Analyze a single session
      --project <id>        Analyze sessions in a project
      --since <YYYY-MM-DD>  Only sessions after this date
      --limit <n>           Max sessions (default: 50, with --project)
      --format <fmt>        table (default) or json
    """)
  end
end
