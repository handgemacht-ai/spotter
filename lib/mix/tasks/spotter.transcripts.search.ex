defmodule Mix.Tasks.Spotter.Transcripts.Search do
  @moduledoc "Search tool call runs with filters."
  @shortdoc "Search tool call runs"
  use Mix.Task

  alias Spotter.Services.TranscriptAnalytics
  alias Spotter.Transcripts.Session

  require Ash.Query

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
      |> put_if(:session_id, resolve_session_id(opts[:session]))
      |> put_if(:tool, opts[:tool])
      |> put_if(:command_contains, opts[:command_contains])
      |> put_if(:min_duration_ms, opts[:min_duration])
      |> put_if(:max_duration_ms, opts[:max_duration])
      |> put_if_atom(:status, opts[:status])
      |> put_if(:limit, opts[:limit])

    format = opts[:format] || "table"

    case TranscriptAnalytics.search(search_opts) do
      {:ok, results} ->
        results = Ash.load!(results, :session)
        output(results, format)

      {:error, reason} ->
        Mix.shell().info("Error: #{Kernel.inspect(reason)}")
    end
  end

  defp print_usage do
    Mix.shell().info("""
    Usage: mix spotter.transcripts.search [options]

    Search tool call runs across sessions with filters.

    Options:
      --project <id>            Filter by project ID
      --worktree <name>         Filter by worktree name
      --session <id>            Filter by session ID
      --tool <name>             Filter by tool name (e.g. Bash, Read, Grep)
      --command-contains <text> Filter commands containing text
      --min-duration <ms>       Minimum duration in milliseconds
      --max-duration <ms>       Maximum duration in milliseconds
      --status <status>         Filter by status (completed, error, ongoing, orphan)
      --limit <n>               Max results (default: 50)
      --format <fmt>            Output format: table (default) or json
    """)
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
      finished_at: run.finished_at && DateTime.to_iso8601(run.finished_at),
      session_id: run.session && run.session.session_id,
      project_id: run.project_id,
      worktree_name: run.worktree_name
    }
  end

  defp resolve_session_id(nil), do: nil

  defp resolve_session_id(external_id) do
    case Session |> Ash.Query.filter(session_id == ^external_id) |> Ash.read_one() do
      {:ok, %Session{id: id}} -> id
      _ -> nil
    end
  end

  defp truncate(nil, _max), do: ""
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max) <> "..."

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp put_if_atom(map, _key, nil), do: map
  defp put_if_atom(map, key, value), do: Map.put(map, key, String.to_atom(value))
end
