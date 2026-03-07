defmodule Spotter.Services.TranscriptDiscovery do
  @moduledoc "Discovery service for Claude Code transcript files."

  alias Spotter.Transcripts.{Config, Session, SessionsIndex}

  require Ash.Query
  require OpenTelemetry.Tracer

  @max_results 500

  @doc """
  Scans transcript root directories for JSONL transcript files and returns
  lightweight preview metadata without full parsing.

  Accepts a transcript root path (string) or keyword options:
  - `:transcript_roots` — list of root paths to scan (overrides config)
  - `:project_filter` — filter results by project name
  """
  def discover(root_or_opts \\ [])

  def discover(root) when is_binary(root) do
    discover(transcript_roots: [root])
  end

  def discover(opts) when is_list(opts) do
    project_filter = Keyword.get(opts, :project_filter)

    roots =
      case Keyword.get(opts, :transcript_roots) do
        nil -> transcript_roots_from_config()
        roots -> roots
      end

    OpenTelemetry.Tracer.with_span "spotter.transcript_discovery.discover",
                                   %{
                                     attributes: %{
                                       "project_filter" => project_filter || "none"
                                     }
                                   } do
      try do
        previews =
          roots
          |> Enum.flat_map(&scan_root/1)
          |> dedupe_by_session_id()
          |> maybe_filter_project(project_filter)
          |> mark_already_imported()
          |> Enum.sort_by(& &1.last_modified, {:desc, DateTime})
          |> Enum.take(@max_results)

        OpenTelemetry.Tracer.set_attribute("transcripts_found", length(previews))
        OpenTelemetry.Tracer.set_attribute("dirs_scanned", length(roots))

        previews
      rescue
        e ->
          OpenTelemetry.Tracer.set_status(:error, Exception.message(e))
          reraise e, __STACKTRACE__
      end
    end
  end

  @doc """
  Returns a sorted list of unique project names from discovered transcripts.
  """
  def list_project_names(opts \\ []) do
    names =
      opts
      |> discover()
      |> Enum.map(& &1.project_name)
      |> Enum.uniq()
      |> Enum.sort()

    {:ok, names}
  end

  @doc """
  Groups discovered transcripts by team_name.

  Returns a map where keys are team names (strings) and values are lists of
  preview maps belonging to that team. Non-team sessions (team_name: nil)
  are excluded from the result.
  """
  @spec group_by_team([map()]) :: %{String.t() => [map()]}
  def group_by_team(previews) do
    previews
    |> Enum.filter(fn p -> is_binary(p.team_name) end)
    |> Enum.group_by(& &1.team_name)
  end

  # --- Private ---

  defp scan_root(root) do
    case File.ls(root) do
      {:ok, entries} ->
        dirs =
          entries
          |> Enum.map(&Path.join(root, &1))
          |> Enum.filter(&File.dir?/1)

        Enum.flat_map(dirs, &scan_directory/1)

      {:error, _} ->
        []
    end
  end

  defp scan_directory(dir) do
    dir_name = Path.basename(dir)

    OpenTelemetry.Tracer.with_span "spotter.transcript_discovery.scan_directory",
                                   %{attributes: %{"dir_name" => dir_name}} do
      index = SessionsIndex.read(dir)

      jsonl_files =
        case File.ls(dir) do
          {:ok, entries} ->
            entries
            |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
            |> Enum.map(&Path.join(dir, &1))

          {:error, _} ->
            []
        end

      OpenTelemetry.Tracer.set_attribute("files_found", length(jsonl_files))

      Enum.flat_map(jsonl_files, &build_preview(&1, dir_name, index))
    end
  end

  defp build_preview(file_path, project_name, index) do
    with {:ok, first_line} <- read_first_line(file_path),
         {:ok, parsed} <- Jason.decode(first_line),
         session_id when is_binary(session_id) <- parsed["sessionId"],
         {:ok, stat} <- File.stat(file_path, time: :posix) do
      index_meta = Map.get(index, session_id, %{})
      message_count = file_path |> File.stream!([], :line) |> Enum.count()
      team_name = parsed["teamName"] || Map.get(index_meta, :team_name)
      is_team = detect_team(parsed, index_meta)
      agent_name = parsed["agentName"] || Map.get(index_meta, :agent_name)
      last_modified = DateTime.from_unix!(stat.mtime)

      [
        %{
          session_id: session_id,
          project_name: project_name,
          project_dir: Path.dirname(file_path),
          file_path: file_path,
          message_count: message_count,
          is_team_session: is_team,
          is_team_member: is_team and is_binary(agent_name),
          team_name: team_name,
          agent_name: agent_name,
          last_modified: last_modified,
          file_size: stat.size,
          custom_title: Map.get(index_meta, :custom_title),
          summary: Map.get(index_meta, :summary),
          first_prompt: Map.get(index_meta, :first_prompt),
          already_imported: false
        }
      ]
    else
      _ -> []
    end
  end

  defp read_first_line(path) do
    path
    |> File.stream!([], :line)
    |> Enum.take(1)
    |> case do
      [line] -> {:ok, String.trim(line)}
      [] -> :error
    end
  rescue
    _ -> :error
  end

  defp detect_team(first_line_parsed, index_meta) do
    cond do
      is_binary(Map.get(index_meta, :team_name)) -> true
      is_binary(first_line_parsed["teamName"]) -> true
      true -> false
    end
  end

  defp dedupe_by_session_id(previews), do: Enum.uniq_by(previews, & &1.session_id)

  defp maybe_filter_project(previews, nil), do: previews

  defp maybe_filter_project(previews, filter) do
    Enum.filter(previews, &(&1.project_name == filter))
  end

  defp mark_already_imported(previews) do
    session_ids = Enum.map(previews, & &1.session_id)

    imported_ids =
      if session_ids == [] do
        MapSet.new()
      else
        Session
        |> Ash.Query.filter(session_id in ^session_ids)
        |> Ash.read!()
        |> Enum.filter(&ingested_session?/1)
        |> Enum.map(& &1.session_id)
        |> MapSet.new()
      end

    Enum.map(previews, fn preview ->
      %{preview | already_imported: MapSet.member?(imported_ids, preview.session_id)}
    end)
  end

  defp ingested_session?(session) do
    has_transcript_dir?(session) or has_ingested_messages?(session)
  end

  defp has_transcript_dir?(%{transcript_dir: transcript_dir}) when is_binary(transcript_dir) do
    transcript_dir != ""
  end

  defp has_transcript_dir?(_), do: false

  defp has_ingested_messages?(%{message_count: count}) when is_integer(count), do: count > 0
  defp has_ingested_messages?(_), do: false

  defp transcript_roots_from_config do
    config = Config.read!()
    config.transcript_roots
  end
end
