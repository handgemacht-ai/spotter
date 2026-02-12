defmodule Spotter.Transcripts.Jobs.SyncTranscripts do
  @moduledoc """
  Oban worker that scans and ingests Claude Code transcripts based on config.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Spotter.Transcripts.Config
  alias Spotter.Transcripts.Jobs.ComputeCoChange
  alias Spotter.Transcripts.Jobs.ComputeHeatmap
  alias Spotter.Transcripts.JsonlParser
  alias Spotter.Transcripts.SessionsIndex

  require Ash.Query

  @batch_size 500
  @max_sessions_per_sync 20

  @doc """
  Enqueues sync jobs for all configured projects.

  Returns `{:ok, %{run_id: String.t(), projects_total: integer()}}`.
  """
  def sync_all do
    config = Config.read!()
    run_id = Ash.UUID.generate()
    project_entries = Enum.to_list(config.projects)
    projects_total = length(project_entries)
    project_names = Enum.map(project_entries, fn {name, _} -> name end)

    broadcast(
      {:ingest_enqueued,
       %{run_id: run_id, projects_total: projects_total, projects: project_names}}
    )

    Enum.each(project_entries, fn {name, %{pattern: pattern}} ->
      %{
        project_name: name,
        pattern: Regex.source(pattern),
        transcripts_dir: config.transcripts_dir,
        run_id: run_id
      }
      |> __MODULE__.new()
      |> Oban.insert!()
    end)

    {:ok, %{run_id: run_id, projects_total: projects_total}}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "project_name" => name,
            "pattern" => pattern_str,
            "transcripts_dir" => transcripts_dir
          } = args
      }) do
    run_id = args["run_id"]
    start_time = System.monotonic_time(:millisecond)

    try do
      pattern = Regex.compile!(pattern_str)

      # Upsert project
      project = upsert_project!(name, pattern_str)

      # Find matching transcript directories
      dirs = list_matching_dirs(transcripts_dir, pattern)
      dirs_total = length(dirs)

      # Count total sessions across all dirs (capped per dir)
      sessions_total = count_sessions_total(dirs)

      Logger.info("Syncing project #{name}: found #{dirs_total} matching directories")

      broadcast(
        {:sync_started,
         %{
           run_id: run_id,
           project: name,
           dirs_total: dirs_total,
           sessions_total: sessions_total
         }}
      )

      {_dirs_done, sessions_synced} =
        Enum.reduce(dirs, {0, 0}, fn dir, {dirs_done, sessions_acc} ->
          synced = sync_directory(project, dir)
          new_dirs_done = dirs_done + 1
          new_sessions_done = sessions_acc + synced

          broadcast(
            {:sync_progress,
             %{
               run_id: run_id,
               project: name,
               dirs_done: new_dirs_done,
               dirs_total: dirs_total,
               sessions_done: new_sessions_done,
               sessions_total: sessions_total
             }}
          )

          {new_dirs_done, new_sessions_done}
        end)

      enqueue_heatmap(project)

      duration_ms = System.monotonic_time(:millisecond) - start_time

      broadcast(
        {:sync_completed,
         %{
           run_id: run_id,
           project: name,
           dirs_synced: dirs_total,
           sessions_synced: sessions_synced,
           duration_ms: duration_ms
         }}
      )

      :ok
    rescue
      e ->
        broadcast({:sync_error, %{run_id: run_id, project: name, error: Exception.message(e)}})
        reraise e, __STACKTRACE__
    end
  end

  defp enqueue_heatmap(project) do
    %{project_id: project.id}
    |> ComputeHeatmap.new()
    |> Oban.insert()

    %{project_id: project.id}
    |> ComputeCoChange.new()
    |> Oban.insert()
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Spotter.PubSub, "sync:progress", message)
  end

  defp upsert_project!(name, pattern) do
    case Spotter.Transcripts.Project |> Ash.Query.filter(name == ^name) |> Ash.read!() do
      [project] ->
        Ash.update!(project, %{pattern: pattern})

      [] ->
        Ash.create!(Spotter.Transcripts.Project, %{name: name, pattern: pattern})
    end
  end

  defp count_sessions_total(dirs) do
    Enum.reduce(dirs, 0, fn dir, acc ->
      count =
        dir
        |> Path.join("*.jsonl")
        |> Path.wildcard()
        |> length()

      acc + min(count, @max_sessions_per_sync)
    end)
  end

  defp list_matching_dirs(transcripts_dir, pattern) do
    case File.ls(transcripts_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&Regex.match?(pattern, &1))
        |> Enum.map(&Path.join(transcripts_dir, &1))
        |> Enum.filter(&File.dir?/1)

      {:error, reason} ->
        Logger.warning("Cannot list #{transcripts_dir}: #{reason}")
        []
    end
  end

  defp sync_directory(project, dir) do
    all_files =
      dir
      |> Path.join("*.jsonl")
      |> Path.wildcard()

    files =
      all_files
      |> Enum.sort_by(fn path -> File.stat!(path, time: :posix).mtime end, :desc)
      |> Enum.take(@max_sessions_per_sync)

    if length(all_files) > @max_sessions_per_sync do
      Logger.info(
        "Syncing #{length(files)} of #{length(all_files)} sessions in #{Path.basename(dir)} (limited to #{@max_sessions_per_sync} most recent)"
      )
    end

    # Load sessions-index once per directory
    index = SessionsIndex.read(dir)

    Enum.each(files, fn file ->
      sync_session_file(project, dir, file, index)
    end)

    length(files)
  end

  defp sync_session_file(project, dir, file, index) do
    transcript_dir = Path.basename(dir)

    case JsonlParser.parse_session_file(file) do
      {:ok, %{session_id: nil}} ->
        Logger.debug("Skipping file without session_id: #{file}")

      {:ok, parsed} ->
        index_meta = Map.get(index, parsed.session_id, %{})
        session = upsert_session!(project, transcript_dir, parsed, index_meta)
        create_messages!(session, parsed.messages)
        create_tool_calls!(session, parsed.messages)
        create_session_reworks!(session, parsed)
        sync_subagents(session, dir, parsed.session_id)

      {:error, reason} ->
        Logger.warning("Failed to parse #{file}: #{inspect(reason)}")
    end
  end

  defp upsert_session!(project, transcript_dir, parsed, index_meta) do
    base_attrs = %{
      slug: parsed.slug,
      cwd: parsed.cwd,
      git_branch: parsed.git_branch,
      version: parsed.version,
      started_at: parsed.started_at,
      ended_at: parsed.ended_at,
      schema_version: parsed.schema_version,
      message_count: length(parsed.messages),
      custom_title: index_meta[:custom_title],
      summary: index_meta[:summary],
      first_prompt: index_meta[:first_prompt],
      source_created_at: index_meta[:source_created_at],
      source_modified_at: index_meta[:source_modified_at]
    }

    case Spotter.Transcripts.Session
         |> Ash.Query.filter(session_id == ^parsed.session_id)
         |> Ash.read!() do
      [session] ->
        update_attrs = apply_timestamp_fallbacks(base_attrs, session)
        Ash.update!(session, update_attrs)

      [] ->
        # For new sessions, apply index timestamp fallbacks
        create_attrs =
          base_attrs
          |> Map.put(:started_at, base_attrs.started_at || index_meta[:source_created_at])
          |> Map.put(:ended_at, base_attrs.ended_at || index_meta[:source_modified_at])
          |> Map.merge(%{
            session_id: parsed.session_id,
            transcript_dir: transcript_dir,
            project_id: project.id
          })

        Ash.create!(Spotter.Transcripts.Session, create_attrs)
    end
  end

  # Never overwrite existing non-nil timestamps with nil
  defp apply_timestamp_fallbacks(attrs, existing_session) do
    attrs
    |> maybe_preserve(:started_at, existing_session, attrs[:source_created_at])
    |> maybe_preserve(:ended_at, existing_session, attrs[:source_modified_at])
  end

  defp maybe_preserve(attrs, field, existing_session, index_fallback) do
    new_value = attrs[field]
    existing_value = Map.get(existing_session, field)

    resolved = new_value || index_fallback || existing_value

    Map.put(attrs, field, resolved)
  end

  defp create_messages!(session, messages) do
    # Check if messages already exist for this session
    existing_count =
      Spotter.Transcripts.Message
      |> Ash.Query.filter(session_id == ^session.id)
      |> Ash.read!()
      |> length()

    if existing_count > 0 do
      Logger.debug(
        "Session #{session.session_id} already has #{existing_count} messages, skipping"
      )
    else
      messages
      |> Enum.filter(& &1[:timestamp])
      |> Enum.map(fn msg ->
        %{
          uuid: msg[:uuid] || Ash.UUID.generate(),
          parent_uuid: msg[:parent_uuid],
          message_id: msg[:message_id],
          type: msg[:type],
          role: msg[:role],
          content: msg[:content],
          timestamp: msg[:timestamp],
          is_sidechain: msg[:is_sidechain] || false,
          agent_id: msg[:agent_id],
          tool_use_id: msg[:tool_use_id],
          session_id: session.id
        }
      end)
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(fn batch ->
        Ash.bulk_create!(batch, Spotter.Transcripts.Message, :create)
      end)
    end
  end

  defp create_tool_calls!(session, messages) do
    tool_name_map = build_tool_name_map(messages)

    tool_calls =
      messages
      |> Enum.filter(&(&1[:type] in [:tool_result, :user]))
      |> Enum.flat_map(&extract_tool_results/1)
      |> Enum.map(&build_tool_call_attrs(&1, tool_name_map, session.id))
      |> Enum.reject(&is_nil(&1.tool_use_id))

    Enum.each(Enum.chunk_every(tool_calls, @batch_size), fn batch ->
      Ash.bulk_create!(batch, Spotter.Transcripts.ToolCall, :upsert)
    end)
  end

  defp build_tool_name_map(messages) do
    messages
    |> Enum.filter(&(&1[:type] in [:assistant, :tool_use]))
    |> Enum.flat_map(&extract_tool_use_names/1)
    |> Map.new()
  end

  defp extract_tool_use_names(%{content: content}) when is_list(content) do
    content
    |> Enum.filter(&(is_map(&1) && &1["type"] == "tool_use"))
    |> Enum.map(&{&1["id"], &1["name"]})
  end

  defp extract_tool_use_names(_), do: []

  defp extract_tool_results(msg) do
    case msg[:content] do
      content when is_list(content) ->
        Enum.filter(content, &(is_map(&1) && &1["type"] == "tool_result"))

      _ ->
        []
    end
  end

  defp build_tool_call_attrs(block, tool_name_map, session_id) do
    is_error = block["is_error"] == true

    error_content =
      if is_error,
        do: block["content"] |> extract_text_content() |> String.slice(0, 500),
        else: nil

    %{
      tool_use_id: block["tool_use_id"],
      tool_name: Map.get(tool_name_map, block["tool_use_id"], "Unknown"),
      is_error: is_error,
      error_content: error_content,
      session_id: session_id
    }
  end

  defp extract_text_content(content) when is_binary(content), do: content

  defp extract_text_content(content) when is_list(content) do
    Enum.map_join(content, "\n", fn
      %{"text" => text} -> text
      other when is_binary(other) -> other
      _ -> ""
    end)
  end

  defp extract_text_content(_), do: ""

  defp create_session_reworks!(session, parsed) do
    rework_records =
      JsonlParser.extract_session_rework_records(parsed.messages, session_cwd: parsed.cwd)

    rework_records
    |> Enum.map(&Map.put(&1, :session_id, session.id))
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      Ash.bulk_create!(batch, Spotter.Transcripts.SessionRework, :upsert)
    end)
  end

  defp sync_subagents(session, dir, session_id) when is_binary(session_id) do
    subagents_dir = Path.join([dir, session_id, "subagents"])

    if File.dir?(subagents_dir) do
      subagents_dir
      |> Path.join("*.jsonl")
      |> Path.wildcard()
      |> Enum.each(fn file ->
        sync_subagent_file(session, file)
      end)
    end
  end

  defp sync_subagents(_session, _dir, _session_id), do: :ok

  defp sync_subagent_file(session, file) do
    case JsonlParser.parse_subagent_file(file) do
      {:ok, parsed} ->
        subagent = upsert_subagent!(session, parsed)
        create_subagent_messages!(session, subagent, parsed.messages)

      {:error, reason} ->
        Logger.warning("Failed to parse subagent file #{file}: #{inspect(reason)}")
    end
  end

  defp create_subagent_messages!(session, subagent, messages) do
    existing_count =
      Spotter.Transcripts.Message
      |> Ash.Query.filter(subagent_id == ^subagent.id)
      |> Ash.read!()
      |> length()

    if existing_count > 0 do
      Logger.debug(
        "Subagent #{subagent.agent_id} already has #{existing_count} messages, skipping"
      )
    else
      messages
      |> Enum.filter(& &1[:timestamp])
      |> Enum.map(fn msg ->
        %{
          uuid: msg[:uuid] || Ash.UUID.generate(),
          parent_uuid: msg[:parent_uuid],
          message_id: msg[:message_id],
          type: msg[:type],
          role: msg[:role],
          content: msg[:content],
          timestamp: msg[:timestamp],
          is_sidechain: msg[:is_sidechain] || false,
          agent_id: subagent.agent_id,
          tool_use_id: msg[:tool_use_id],
          session_id: session.id,
          subagent_id: subagent.id
        }
      end)
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(fn batch ->
        Ash.bulk_create!(batch, Spotter.Transcripts.Message, :create)
      end)
    end
  end

  defp upsert_subagent!(session, parsed) do
    update_attrs = %{
      slug: parsed.slug,
      started_at: parsed.started_at,
      ended_at: parsed.ended_at,
      message_count: length(parsed.messages)
    }

    case Spotter.Transcripts.Subagent
         |> Ash.Query.filter(session_id == ^session.id and agent_id == ^parsed.agent_id)
         |> Ash.read!() do
      [subagent] ->
        Ash.update!(subagent, update_attrs)

      [] ->
        create_attrs =
          Map.merge(update_attrs, %{
            agent_id: parsed.agent_id,
            session_id: session.id
          })

        Ash.create!(Spotter.Transcripts.Subagent, create_attrs)
    end
  end
end
