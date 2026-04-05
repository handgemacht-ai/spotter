defmodule Mix.Tasks.Spotter.Transcripts.Inspect do
  @moduledoc "Inspect tool call runs for a specific session."
  @shortdoc "Inspect tool call runs in a session"
  use Mix.Task

  alias Spotter.Services.TranscriptAnalytics
  alias Spotter.Transcripts.Session

  require Ash.Query

  @switches [
    session: :string,
    tool_use_id: :string,
    context: :integer,
    status: :string,
    with_messages: :boolean,
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

    session_id = opts[:session]

    unless session_id do
      Mix.shell().error("Error: --session is required")
      print_usage()
      exit({:shutdown, 1})
    end

    internal_id = resolve_session_id(session_id)

    status_filter =
      if opts[:status], do: String.to_atom(opts[:status])

    inspect_opts =
      %{session_id: internal_id}
      |> put_if(:tool_use_id, opts[:tool_use_id])
      |> put_if(:context, opts[:context])
      |> put_if(:status_filter, status_filter)
      |> put_if(:with_messages, opts[:with_messages])

    format = opts[:format] || "table"

    case TranscriptAnalytics.inspect(inspect_opts) do
      {:ok, results} ->
        results = Ash.load!(results, :session)
        output(results, format)

      {:error, reason} ->
        Mix.shell().info("Error: #{Kernel.inspect(reason)}")
    end
  end

  defp print_usage do
    Mix.shell().info("""
    Usage: mix spotter.transcripts.inspect --session <id> [options]

    Inspect tool call runs for a specific session.

    Options:
      --session <id>          Session ID (required)
      --tool-use-id <id>      Filter to a specific tool use ID
      --context <n>           Number of surrounding runs to include
      --status <status>       Filter runs by status (error, completed, ongoing, orphan)
      --with-messages         Include surrounding message content for context
      --format <fmt>          Output format: table (default) or json
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
    base = %{
      tool_use_id: run.tool_use_id,
      tool_name: run.tool_name,
      command: run.command,
      input_summary: run.input_summary,
      status: run.status,
      error_content: run.error_content,
      duration_ms: run.duration_ms,
      started_at: run.started_at && DateTime.to_iso8601(run.started_at),
      finished_at: run.finished_at && DateTime.to_iso8601(run.finished_at),
      session_id: run.session && run.session.session_id,
      project_id: run.project_id,
      worktree_name: run.worktree_name
    }

    case Map.get(run, :__messages__) do
      nil -> base
      messages -> Map.put(base, :messages, messages)
    end
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
end
