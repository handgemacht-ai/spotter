defmodule Mix.Tasks.Spotter.Transcripts.Search do
  @moduledoc "Search tool call runs with filters."
  @shortdoc "Search tool call runs"
  use Mix.Task

  alias Spotter.Services.TranscriptAnalytics

  @impl true
  def run(args) do
    Mix.Tasks.Spotter.CliHelpers.start_app_without_server()

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          project: :string,
          worktree: :string,
          session: :string,
          tool: :string,
          command_contains: :string,
          min_duration: :integer,
          max_duration: :integer,
          status: :string,
          limit: :integer,
          format: :string
        ]
      )

    search_opts =
      %{}
      |> put_if(:project_id, opts[:project])
      |> put_if(:worktree_name, opts[:worktree])
      |> put_if(:session_id, opts[:session])
      |> put_if(:tool, opts[:tool])
      |> put_if(:command_contains, opts[:command_contains])
      |> put_if(:min_duration_ms, opts[:min_duration])
      |> put_if(:max_duration_ms, opts[:max_duration])
      |> put_if_atom(:status, opts[:status])
      |> put_if(:limit, opts[:limit])

    format = opts[:format] || "table"

    case TranscriptAnalytics.search(search_opts) do
      {:ok, results} ->
        output(results, format)

      {:error, reason} ->
        Mix.shell().info("Error: #{Kernel.inspect(reason)}")
    end
  end

  defp output(results, "json") do
    encoded =
      results
      |> Enum.map(&run_to_map/1)
      |> Jason.encode!(pretty: true)

    Mix.shell().info(encoded)
  end

  defp output(results, _table) do
    if results == [] do
      Mix.shell().info("No results found.")
    else
      header = "tool_use_id | tool_name | command | status | duration_ms"
      Mix.shell().info(header)
      Mix.shell().info(String.duplicate("-", String.length(header)))

      Enum.each(results, fn r ->
        Mix.shell().info(
          "#{r.tool_use_id} | #{r.tool_name} | #{truncate(r.command, 30)} | #{r.status} | #{r.duration_ms || "n/a"}"
        )
      end)
    end
  end

  defp run_to_map(run) do
    %{
      tool_use_id: run.tool_use_id,
      tool_name: run.tool_name,
      command: run.command,
      status: run.status,
      duration_ms: run.duration_ms,
      started_at: run.started_at && DateTime.to_iso8601(run.started_at),
      finished_at: run.finished_at && DateTime.to_iso8601(run.finished_at)
    }
  end

  defp truncate(nil, _max), do: ""
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max) <> "..."

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp put_if_atom(map, _key, nil), do: map
  defp put_if_atom(map, key, value), do: Map.put(map, key, String.to_atom(value))
end
