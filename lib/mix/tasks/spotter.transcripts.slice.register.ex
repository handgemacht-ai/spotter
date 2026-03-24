defmodule Mix.Tasks.Spotter.Transcripts.Slice.Register do
  @moduledoc "Register a saved session slice from CLI options."
  @shortdoc "Register a saved session slice"
  use Mix.Task

  require Ash.Query

  alias Spotter.Services.TranscriptAnalytics
  alias Spotter.Transcripts.{Session, SessionSlice}

  @impl true
  def run(args) do
    Mix.Tasks.Spotter.CliHelpers.start_app_without_server()

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          session: :string,
          tool_use_id: [:string, :keep],
          tool: :string,
          command_contains: :string,
          min_duration_ms: :integer,
          max_duration_ms: :integer,
          status: :string,
          title: :string,
          context_before: :integer,
          context_after: :integer,
          format: :string
        ]
      )

    session_id = opts[:session]
    format = opts[:format] || "text"

    unless session_id do
      Mix.shell().error("Error: --session is required")
      exit({:shutdown, 1})
    end

    case resolve_session(session_id) do
      {:ok, session} ->
        case resolve_tool_use_ids(session, opts) do
          {:ok, tool_use_ids} ->
            create_slice(session, tool_use_ids, opts, format)

          {:error, reason} ->
            Mix.shell().error("Error: #{reason}")
            exit({:shutdown, 1})
        end

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp resolve_session(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{} = session} -> {:ok, session}
      {:ok, nil} -> {:error, "Session not found: #{session_id}"}
      {:error, err} -> {:error, "Failed to look up session: #{inspect(err)}"}
    end
  end

  defp resolve_tool_use_ids(session, opts) do
    explicit_ids = Keyword.get_values(opts, :tool_use_id)

    if explicit_ids != [] do
      validate_tool_use_ids(session, explicit_ids)
    else
      search_for_tool_use_ids(session, opts)
    end
  end

  defp validate_tool_use_ids(session, tool_use_ids) do
    search_opts = %{session_id: session.id, limit: 10_000}

    case TranscriptAnalytics.search(search_opts) do
      {:ok, runs} ->
        valid_ids = MapSet.new(runs, & &1.tool_use_id)
        invalid = Enum.reject(tool_use_ids, &MapSet.member?(valid_ids, &1))

        if invalid == [] do
          {:ok, tool_use_ids}
        else
          {:error, "Tool use IDs not found in session: #{Enum.join(invalid, ", ")}"}
        end

      {:error, err} ->
        {:error, "Failed to validate tool use IDs: #{inspect(err)}"}
    end
  end

  defp search_for_tool_use_ids(session, opts) do
    search_opts =
      %{session_id: session.id, limit: 10_000}
      |> put_if(:tool, opts[:tool])
      |> put_if(:command_contains, opts[:command_contains])
      |> put_if(:min_duration_ms, opts[:min_duration_ms])
      |> put_if(:max_duration_ms, opts[:max_duration_ms])
      |> put_if_atom(:status, opts[:status])

    case TranscriptAnalytics.search(search_opts) do
      {:ok, []} ->
        {:error, "No matching tool runs found for the given filters"}

      {:ok, runs} ->
        {:ok, Enum.map(runs, & &1.tool_use_id)}

      {:error, err} ->
        {:error, "Search failed: #{inspect(err)}"}
    end
  end

  defp create_slice(session, tool_use_ids, opts, format) do
    title = opts[:title] || "Slice #{Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M")}"
    context_before = opts[:context_before] || 5
    context_after = opts[:context_after] || 5

    filters = build_filters(opts)

    attrs = %{
      session_id: session.id,
      project_id: session.project_id,
      title: title,
      filters: filters,
      highlight_tool_use_ids: tool_use_ids,
      context_before_lines: context_before,
      context_after_lines: context_after
    }

    case Ash.create(SessionSlice, attrs) do
      {:ok, slice} ->
        output_result(slice, session, format)

      {:error, err} ->
        Mix.shell().error("Failed to create slice: #{inspect(err)}")
        exit({:shutdown, 1})
    end
  end

  defp build_filters(opts) do
    %{}
    |> put_if(:tool, opts[:tool])
    |> put_if(:command_contains, opts[:command_contains])
    |> put_if(:min_duration_ms, opts[:min_duration_ms])
    |> put_if(:max_duration_ms, opts[:max_duration_ms])
    |> put_if(:status, opts[:status])
  end

  defp output_result(slice, session, "json") do
    data = %{
      id: slice.id,
      title: slice.title,
      session_id: session.session_id,
      project_id: slice.project_id,
      highlight_count: length(slice.highlight_tool_use_ids),
      url: "/sessions/#{session.session_id}?slice=#{slice.id}"
    }

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp output_result(slice, session, _text) do
    Mix.shell().info("Slice created: #{slice.id}")
    Mix.shell().info("Title: #{slice.title}")
    Mix.shell().info("Highlighted runs: #{length(slice.highlight_tool_use_ids)}")
    Mix.shell().info("URL: /sessions/#{session.session_id}?slice=#{slice.id}")
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp put_if_atom(map, _key, nil), do: map
  defp put_if_atom(map, key, value), do: Map.put(map, key, String.to_atom(value))
end
