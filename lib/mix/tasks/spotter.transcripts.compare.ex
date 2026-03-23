defmodule Mix.Tasks.Spotter.Transcripts.Compare do
  @moduledoc "Compare tool call runs between two session cohorts."
  @shortdoc "Compare tool runs between session cohorts"
  use Mix.Task

  alias Spotter.Services.TranscriptAnalytics

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          left_session: [:string, :keep],
          right_session: [:string, :keep],
          tool: :string,
          command_contains: :string,
          group_by: :string,
          format: :string
        ]
      )

    left_sessions = Keyword.get_values(opts, :left_session)
    right_sessions = Keyword.get_values(opts, :right_session)
    format = opts[:format] || "table"

    cond do
      left_sessions == [] ->
        Mix.shell().info("Error: at least one --left-session is required")

      right_sessions == [] ->
        Mix.shell().info("Error: at least one --right-session is required")

      true ->
        compare_opts =
          %{
            left_sessions: left_sessions,
            right_sessions: right_sessions
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

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp put_if_atom(map, _key, nil), do: map
  defp put_if_atom(map, key, value), do: Map.put(map, key, String.to_atom(value))
end
