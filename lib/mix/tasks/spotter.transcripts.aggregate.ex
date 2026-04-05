defmodule Mix.Tasks.Spotter.Transcripts.Aggregate do
  @moduledoc "Cross-session aggregation of tool call runs."
  @shortdoc "Aggregate tool usage across sessions"
  use Mix.Task

  alias Spotter.Services.TranscriptAnalytics

  @switches [
    project: :string,
    since: :string,
    tool: :string,
    group_by: :string,
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
      TranscriptAnalytics.aggregate(%{
        project_id: opts[:project],
        since: opts[:since],
        tool: opts[:tool],
        group_by: opts[:group_by]
      })

    format = opts[:format] || "table"
    print_result(result, format)
  end

  defp print_result(result, "json") do
    Mix.shell().info(Jason.encode!(result, pretty: true))
  end

  defp print_result(result, _table) do
    Mix.shell().info(
      "Tool Usage Summary (#{result.session_count} sessions, #{result.total_runs} tool calls):\n"
    )

    header =
      "  #{pad("Group", 30)} #{pad("Calls", 7)} #{pad("Errors", 7)} #{pad("Err%", 7)} #{pad("Avg ms", 10)} #{pad("P95 ms", 10)}"

    Mix.shell().info(header)

    Mix.shell().info(
      "  #{String.duplicate("-", 30)} #{String.duplicate("-", 7)} #{String.duplicate("-", 7)} #{String.duplicate("-", 7)} #{String.duplicate("-", 10)} #{String.duplicate("-", 10)}"
    )

    Enum.each(result.groups, fn g ->
      key_str = g.key |> Map.values() |> Enum.map_join(", ", &to_string/1)

      Mix.shell().info(
        "  #{pad(key_str, 30)} #{pad(g.count, 7)} #{pad(g.errors, 7)} #{pad("#{g.error_pct}%", 7)} #{pad(g.avg_duration_ms || "-", 10)} #{pad(g.p95_duration_ms || "-", 10)}"
      )
    end)

    if result.top_errors != [] do
      Mix.shell().info("\nTop Errors:")

      Enum.each(result.top_errors, fn e ->
        Mix.shell().info("  #{e.tool_name} #{inspect(e.fingerprint)} — #{e.count} occurrences")
      end)
    end
  end

  defp pad(val, width) when is_integer(val), do: pad(Integer.to_string(val), width)
  defp pad(val, width), do: String.pad_trailing(to_string(val), width)

  defp print_usage do
    Mix.shell().info("""
    Usage: mix spotter.transcripts.aggregate [options]

    Cross-session aggregation of tool call runs.

    Options:
      --project <id>        Filter by project ID
      --since <YYYY-MM-DD>  Only sessions after this date
      --tool <name>         Filter by tool name
      --group-by <fields>   Comma-separated: tool_name, status (default: tool_name)
      --format <fmt>        table (default) or json
    """)
  end
end
