defmodule Mix.Tasks.Spotter.Transcripts.Compare do
  @moduledoc "Compare tool call runs between two session cohorts."
  @shortdoc "Compare tool runs between session cohorts"
  use Mix.Task

  alias Spotter.Services.TranscriptAnalytics
  alias Spotter.Transcripts.Session

  require Ash.Query

  @switches [
    left_session: [:string, :keep],
    right_session: [:string, :keep],
    tool: :string,
    command_contains: :string,
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

    left_sessions = Keyword.get_values(opts, :left_session)
    right_sessions = Keyword.get_values(opts, :right_session)
    format = opts[:format] || "table"

    cond do
      left_sessions == [] ->
        Mix.shell().info("Error: at least one --left-session is required")

      right_sessions == [] ->
        Mix.shell().info("Error: at least one --right-session is required")

      true ->
        left_internal = Enum.map(left_sessions, &resolve_session_id/1)
        right_internal = Enum.map(right_sessions, &resolve_session_id/1)

        compare_opts =
          %{
            left_sessions: left_internal,
            right_sessions: right_internal
          }
          |> put_if(:tool, opts[:tool])
          |> put_if(:command_contains, opts[:command_contains])
          |> put_if_atom(:group_by, opts[:group_by])

        case TranscriptAnalytics.compare(compare_opts) do
          {:ok, result} ->
            output(result, format)

          {:error, reason} ->
            Mix.shell().info("Error: #{Kernel.inspect(reason)}")
        end
    end
  end

  defp print_usage do
    Mix.shell().info("""
    Usage: mix spotter.transcripts.compare --left-session <id> --right-session <id> [options]

    Compare tool call runs between two session cohorts.

    Options:
      --left-session <id>       Left cohort session ID (required, repeatable)
      --right-session <id>      Right cohort session ID (required, repeatable)
      --tool <name>             Filter by tool name
      --command-contains <text> Filter commands containing text
      --group-by <field>        Group by field (default: tool_name)
      --format <fmt>            Output format: table (default) or json
    """)
  end

  defp output(result, "json") do
    Mix.shell().info(Jason.encode!(result, pretty: true))
  end

  defp output(result, _table) do
    Mix.shell().info("Left cohort:")
    print_groups(result[:left] || [])
    Mix.shell().info("\nRight cohort:")
    print_groups(result[:right] || [])
  end

  defp print_groups([]) do
    Mix.shell().info("  (no data)")
  end

  defp print_groups(groups) do
    Enum.each(groups, fn g ->
      Mix.shell().info(
        "  #{g.key}: count=#{g.count}, avg_duration=#{g.avg_duration_ms || "n/a"}ms"
      )
    end)
  end

  defp resolve_session_id(external_id) do
    case Session |> Ash.Query.filter(session_id == ^external_id) |> Ash.read_one() do
      {:ok, %Session{id: id}} ->
        id

      _ ->
        Mix.shell().error("Session not found: #{external_id}")
        exit({:shutdown, 1})
    end
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp put_if_atom(map, _key, nil), do: map
  defp put_if_atom(map, key, value), do: Map.put(map, key, String.to_atom(value))
end
