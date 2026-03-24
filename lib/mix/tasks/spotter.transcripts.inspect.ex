defmodule Mix.Tasks.Spotter.Transcripts.Inspect do
  @moduledoc "Inspect tool call runs for a specific session."
  @shortdoc "Inspect tool call runs in a session"
  use Mix.Task

  alias Spotter.Services.TranscriptAnalytics
  alias Spotter.Transcripts.Session

  require Ash.Query

  @impl true
  def run(args) do
    Mix.Tasks.Spotter.CliHelpers.start_app_without_server()

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          session: :string,
          tool_use_id: :string,
          context: :integer,
          format: :string
        ]
      )

    session_id = opts[:session]

    unless session_id do
      Mix.raise("--session is required")
    end

    internal_id = resolve_session_id(session_id)

    inspect_opts =
      %{session_id: internal_id}
      |> put_if(:tool_use_id, opts[:tool_use_id])
      |> put_if(:context, opts[:context])

    format = opts[:format] || "table"

    case TranscriptAnalytics.inspect(inspect_opts) do
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
      Mix.shell().info("No tool call runs found for this session.")
    else
      Enum.each(results, fn r ->
        Mix.shell().info(
          "[#{r.status}] #{r.tool_name} #{r.tool_use_id} — #{r.command || "(no command)"} (#{r.duration_ms || "?"}ms)"
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

  defp resolve_session_id(external_id) do
    case Session |> Ash.Query.filter(session_id == ^external_id) |> Ash.read_one() do
      {:ok, %Session{id: id}} -> id
      _ -> Mix.raise("Session not found: #{external_id}")
    end
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
