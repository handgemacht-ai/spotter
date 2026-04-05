defmodule Mix.Tasks.Spotter.Transcripts.Sequences do
  @moduledoc "Detect recurring tool call sequences across sessions."
  @shortdoc "Find tool call patterns and retries"
  use Mix.Task

  alias Spotter.Services.TranscriptAnalytics

  @switches [
    project: :string,
    since: :string,
    min_length: :integer,
    max_length: :integer,
    min_occurrences: :integer,
    recovery: :boolean,
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

    result =
      TranscriptAnalytics.sequence_analysis(%{
        project_id: opts[:project],
        since: opts[:since],
        min_length: opts[:min_length],
        max_length: opts[:max_length],
        min_occurrences: opts[:min_occurrences],
        recovery: opts[:recovery] || false
      })

    format = opts[:format] || "table"
    print_result(result, format)
  end

  defp print_result(result, "json") do
    Mix.shell().info(Jason.encode!(result, pretty: true))
  end

  defp print_result(result, _table) do
    Mix.shell().info("Sequence Analysis (#{result.session_count} sessions):\n")

    if result.frequent_sequences != [] do
      Mix.shell().info("Frequent Sequences:")

      Mix.shell().info("  #{pad("Pattern", 50)} #{pad("Count", 7)}")

      Mix.shell().info("  #{String.duplicate("-", 50)} #{String.duplicate("-", 7)}")

      Enum.each(result.frequent_sequences, fn s ->
        pattern_str = Enum.join(s.pattern, " -> ")
        Mix.shell().info("  #{pad(pattern_str, 50)} #{pad(s.count, 7)}")
      end)
    else
      Mix.shell().info("No frequent sequences found.")
    end

    if result.retry_patterns != [] do
      Mix.shell().info("\nRetry Patterns (tool retried after error):")

      Enum.each(result.retry_patterns, fn r ->
        Mix.shell().info("  #{r.pattern} — #{r.count} occurrences")
      end)
    end

    if recovery = result[:recovery_stats] do
      Mix.shell().info("\nRecovery Analysis:")

      Mix.shell().info(
        "  #{pad("Category", 28)} #{pad("Errors", 8)} #{pad("Retry%", 8)} #{pad("Recover%", 10)} #{pad("AvgRetries", 10)}"
      )

      Mix.shell().info(
        "  #{String.duplicate("-", 28)} #{String.duplicate("-", 8)} #{String.duplicate("-", 8)} #{String.duplicate("-", 10)} #{String.duplicate("-", 10)}"
      )

      Enum.each(recovery, fn r ->
        Mix.shell().info(
          "  #{pad(r.category, 28)} #{pad(r.total_errors, 8)} #{pad("#{r.retry_rate}%", 8)} #{pad("#{r.recovery_rate}%", 10)} #{pad(r.avg_retries, 10)}"
        )
      end)
    end
  end

  defp pad(val, width) when is_integer(val), do: pad(Integer.to_string(val), width)
  defp pad(val, width), do: String.pad_trailing(to_string(val), width)

  defp print_usage do
    Mix.shell().info("""
    Usage: mix spotter.transcripts.sequences [options]

    Detect recurring tool call sequences and retry patterns.

    Options:
      --project <id>           Filter by project ID
      --since <YYYY-MM-DD>     Only sessions after this date
      --min-length <n>         Minimum sequence length (default: 3)
      --max-length <n>         Maximum sequence length (default: 5)
      --min-occurrences <n>    Minimum occurrences to report (default: 3)
      --recovery               Include recovery analysis per error category
      --format <fmt>           table (default) or json
    """)
  end
end
