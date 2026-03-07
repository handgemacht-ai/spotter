defmodule Spotter.Transcripts.Jobs.SyncTranscripts do
  @moduledoc """
  Oban worker that scans and ingests Claude Code transcripts based on config.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Config.Runtime
  alias Spotter.Observability.ErrorReport
  alias Spotter.Search.Jobs.ReindexProject
  alias Spotter.Transcripts.Config
  alias Spotter.Transcripts.Jobs.ComputeCoChange
  alias Spotter.Transcripts.Jobs.ComputeHeatmap
  alias Spotter.Transcripts.Jobs.ComputeLanes
  alias Spotter.Transcripts.JsonlParser
  alias Spotter.Transcripts.Session
  alias Spotter.Transcripts.Sessions
  alias Spotter.Transcripts.SessionsIndex
  alias Spotter.Transcripts.Team
  alias Spotter.Transcripts.TeamMember

  require Ash.Query

  @batch_size 500
  @max_sessions_per_sync 20

  @doc """
  Syncs a single session by its session_id.

  Locates the transcript JSONL file by scanning configured transcript directories,
  then ingests messages and metadata for that session only.

  Returns `%{session_id: ..., ingested_messages: n, status: :ok | :not_found | :error}`.
  """
  def sync_session_by_id(session_id, opts \\ []) do
    Tracer.with_span "spotter.sync_transcripts.sync_session_by_id" do
      Tracer.set_attribute("spotter.session_id", session_id)
      set_trace_context_attributes(Keyword.get(opts, :trace_context, %{}))

      transcript_path = Keyword.get(opts, :transcript_path)
      transcript_roots = Keyword.get(opts, :transcript_roots)

      case find_transcript_file(session_id, transcript_path, transcript_roots) do
        {:ok, file_path} ->
          source = if file_path == transcript_path, do: "direct", else: "root_search"
          Tracer.set_attribute("spotter.transcript_path.source", source)
          sync_session_file(file_path, opts)

        :not_found ->
          ErrorReport.set_trace_error(
            "transcript_not_found",
            "transcript_not_found",
            "transcripts.jobs.sync_transcripts"
          )

          %{session_id: session_id, ingested_messages: 0, status: :not_found}
      end
    end
  rescue
    error ->
      ErrorReport.set_trace_error(
        "unexpected_error",
        Exception.message(error),
        "transcripts.jobs.sync_transcripts"
      )

      reraise error, __STACKTRACE__
  end

  defp set_trace_context_attributes(trace_ctx) when is_map(trace_ctx) do
    trace_id = trace_ctx[:otel_trace_id] || trace_ctx["otel_trace_id"]
    traceparent = trace_ctx[:otel_traceparent] || trace_ctx["otel_traceparent"]

    if is_binary(trace_id) and trace_id != "" do
      Tracer.set_attribute("spotter.parent_trace_id", trace_id)
    end

    if is_binary(traceparent) and traceparent != "" do
      Tracer.set_attribute("spotter.parent_traceparent", traceparent)
    end
  rescue
    _error -> :ok
  end

  defp set_trace_context_attributes(_), do: :ok

  @doc """
  Syncs a single session from a specific JSONL file path.

  Parses the file, upserts the session record, and ingests messages idempotently.

  Returns `%{session_id: ..., ingested_messages: n, status: :ok | :not_found | :error}`.
  """
  def sync_session_file(file_path, _opts \\ []) do
    Tracer.with_span "spotter.sync_transcripts.sync_session_file" do
      case JsonlParser.parse_session_file(file_path) do
        {:ok, %{session_id: nil}} ->
          %{session_id: nil, ingested_messages: 0, status: :not_found}

        {:ok, parsed} ->
          dir = Path.dirname(file_path)
          transcript_dir = Path.basename(dir)
          index = SessionsIndex.read(dir)
          index_meta = Map.get(index, parsed.session_id, %{})

          # Ensure session and project exist
          session_record = find_or_create_session!(parsed)

          # Upsert session with full metadata + transcript_dir backfill
          session = upsert_existing_session!(session_record, transcript_dir, parsed, index_meta)
          link_team_membership!(session, parsed)
          subagent_type_by_agent_id = build_subagent_type_index(parsed.messages)

          ingested = upsert_messages!(session, parsed.messages)
          create_tool_calls!(session, parsed.messages)
          create_session_reworks!(session, parsed)
          sync_subagents(session, dir, parsed.session_id, subagent_type_by_agent_id)

          %{session_id: parsed.session_id, ingested_messages: ingested, status: :ok}

        {:error, reason} ->
          ErrorReport.set_trace_error(
            "parse_failed",
            "parse_failed",
            "transcripts.jobs.sync_transcripts"
          )

          Logger.warning("Failed to parse #{file_path}: #{inspect(reason)}")
          %{session_id: nil, ingested_messages: 0, status: :error}
      end
    end
  rescue
    e ->
      ErrorReport.set_trace_error(
        "unexpected_error",
        Exception.message(e),
        "transcripts.jobs.sync_transcripts"
      )

      Logger.warning("Error syncing #{file_path}: #{Exception.message(e)}")
      %{session_id: nil, ingested_messages: 0, status: :error}
  end

  @doc """
  Enqueues sync jobs for all configured projects.

  Returns `{:ok, %{run_id: String.t(), projects_total: integer()}}`.
  """
  @deprecated "Use hook-based or per-session sync instead of bulk sync_all"
  def sync_all do
    Logger.warning("SyncTranscripts.sync_all/0 is deprecated; use hook-based or per-session sync")
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
        transcript_roots: config.transcript_roots,
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
            "pattern" => pattern_str
          } = args
      }) do
    run_id = args["run_id"]
    start_time = System.monotonic_time(:millisecond)

    Tracer.with_span "spotter.sync_transcripts.perform" do
      Tracer.set_attribute("spotter.project_name", name)
      Tracer.set_attribute("spotter.run_id", run_id || "")
      set_trace_context_attributes(Map.take(args, ["otel_trace_id", "otel_traceparent"]))

      try do
        pattern = Regex.compile!(pattern_str)

        # Upsert project
        project = upsert_project!(name, pattern_str)

        # Find matching transcript directories
        transcript_dirs = transcript_dirs_from_args(args)

        dirs = list_matching_dirs(transcript_dirs, pattern)
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

        if Map.get(args, "enqueue_downstream_jobs", true) do
          enqueue_heatmap(project)
        end

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
          ErrorReport.set_trace_error(
            "unexpected_error",
            Exception.message(e),
            "transcripts.jobs.sync_transcripts"
          )

          broadcast({:sync_error, %{run_id: run_id, project: name, error: Exception.message(e)}})
          reraise e, __STACKTRACE__
      end
    end
  end

  defp enqueue_heatmap(project) do
    %{project_id: project.id}
    |> ComputeHeatmap.new()
    |> Oban.insert()

    %{project_id: project.id}
    |> ComputeCoChange.new()
    |> Oban.insert()

    %{project_id: project.id}
    |> ReindexProject.new()
    |> Oban.insert()

    enqueue_lanes(project)
  end

  defp enqueue_lanes(project) do
    Team
    |> Ash.Query.filter(project_id == ^project.id)
    |> Ash.read!()
    |> Enum.each(fn team ->
      %{team_id: team.id}
      |> ComputeLanes.new()
      |> Oban.insert()
    end)
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
    transcript_dir = List.wrap(transcripts_dir)

    transcript_dir
    |> Enum.flat_map(&list_matching_dirs_for_root(&1, pattern))
    |> Enum.uniq()
  end

  defp list_matching_dirs_for_root(transcripts_dir, pattern) do
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

  defp transcript_dirs_from_args(args) do
    case args do
      %{"transcript_roots" => dirs} when is_list(dirs) ->
        dirs |> Enum.filter(&is_binary/1) |> Enum.uniq()

      _ ->
        {roots, _source} = Runtime.transcript_roots()
        roots
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
        link_team_membership!(session, parsed)
        subagent_type_by_agent_id = build_subagent_type_index(parsed.messages)
        create_messages!(session, parsed.messages)
        create_tool_calls!(session, parsed.messages)
        create_session_reworks!(session, parsed)
        sync_subagents(session, dir, parsed.session_id, subagent_type_by_agent_id)

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
      source_modified_at: index_meta[:source_modified_at],
      team_name: parsed.team_name,
      agent_name: parsed.agent_name
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
          raw_payload: msg[:raw_payload],
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

  # Batch-upsert session rework records. All writes go through chunked bulk_create
  # to avoid per-item DB roundtrips under bursty transcript ingestion.
  defp create_session_reworks!(_session, %{messages: []}), do: :ok

  defp create_session_reworks!(session, parsed) do
    rework_records =
      JsonlParser.extract_session_rework_records(parsed.messages, session_cwd: parsed.cwd)

    if rework_records == [] do
      :ok
    else
      rework_records
      |> Enum.map(&Map.put(&1, :session_id, session.id))
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(fn batch ->
        Ash.bulk_create!(batch, Spotter.Transcripts.SessionRework, :upsert,
          return_records?: false
        )
      end)
    end
  end

  defp sync_subagents(session, dir, session_id, subagent_type_by_agent_id)
       when is_binary(session_id) do
    subagents_dir = Path.join([dir, session_id, "subagents"])

    if File.dir?(subagents_dir) do
      subagents_dir
      |> Path.join("*.jsonl")
      |> Path.wildcard()
      |> Enum.each(fn file ->
        sync_subagent_file(session, file, subagent_type_by_agent_id)
      end)
    end
  end

  defp sync_subagents(_session, _dir, _session_id, _subagent_type_by_agent_id), do: :ok

  defp sync_subagent_file(session, file, subagent_type_by_agent_id) do
    case JsonlParser.parse_subagent_file(file) do
      {:ok, parsed} ->
        subagent_type = Map.get(subagent_type_by_agent_id, parsed.agent_id)
        subagent = upsert_subagent!(session, parsed, subagent_type)
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
          raw_payload: msg[:raw_payload],
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

  defp find_transcript_file(session_id, transcript_path, transcript_roots_override) do
    case resolve_transcript_path(transcript_path) do
      {:ok, _} = found -> found
      :skip -> search_transcript_roots(session_id, transcript_roots_override)
    end
  end

  defp resolve_transcript_path(nil), do: :skip
  defp resolve_transcript_path(""), do: :skip

  defp resolve_transcript_path(path) when is_binary(path) do
    expanded = Path.expand(path)

    if File.exists?(expanded) do
      {:ok, expanded}
    else
      Logger.debug("transcript_path hint not found on disk: #{expanded}")
      :skip
    end
  end

  defp search_transcript_roots(session_id, roots_override) do
    roots =
      case roots_override do
        roots when is_list(roots) and roots != [] -> roots
        _ -> Config.read!().transcript_roots
      end

    Enum.find_value(roots, :not_found, fn root ->
      find_in_transcript_root(root, session_id)
    end)
  end

  defp find_in_transcript_root(root, session_id) do
    file = Path.join(root, "#{session_id}.jsonl")

    if File.exists?(file) do
      {:ok, file}
    else
      root
      |> list_subdirectories()
      |> Enum.map(&Path.join(&1, "#{session_id}.jsonl"))
      |> Enum.find(&File.exists?/1)
      |> then(fn
        nil -> nil
        path -> {:ok, path}
      end)
    end
  end

  defp list_subdirectories(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.filter(&File.dir?/1)

      {:error, _} ->
        []
    end
  end

  defp upsert_existing_session!(session_record, transcript_dir, parsed, index_meta) do
    base_attrs = %{
      slug: parsed.slug,
      cwd: parsed.cwd,
      git_branch: parsed.git_branch,
      version: parsed.version,
      started_at: parsed.started_at,
      ended_at: parsed.ended_at,
      schema_version: parsed.schema_version,
      message_count: length(parsed.messages),
      transcript_dir: transcript_dir,
      custom_title: index_meta[:custom_title],
      summary: index_meta[:summary],
      first_prompt: index_meta[:first_prompt],
      source_created_at: index_meta[:source_created_at],
      source_modified_at: index_meta[:source_modified_at],
      team_name: parsed.team_name,
      agent_name: parsed.agent_name
    }

    update_attrs = apply_timestamp_fallbacks(base_attrs, session_record)
    Ash.update!(session_record, update_attrs)
  end

  defp upsert_messages!(session, messages) do
    msg_attrs =
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
          raw_payload: msg[:raw_payload],
          timestamp: msg[:timestamp],
          is_sidechain: msg[:is_sidechain] || false,
          agent_id: msg[:agent_id],
          tool_use_id: msg[:tool_use_id],
          session_id: session.id
        }
      end)

    msg_attrs
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      Ash.bulk_create!(batch, Spotter.Transcripts.Message, :upsert)
    end)

    length(msg_attrs)
  end

  defp build_subagent_type_index(messages) do
    task_subagent_type_by_tool_use =
      messages
      |> Enum.flat_map(&extract_task_subagent_types/1)
      |> Map.new()

    messages
    |> Enum.flat_map(&extract_agent_progress_refs/1)
    |> Enum.reduce(%{}, fn {agent_id, parent_tool_use_id}, acc ->
      case Map.get(task_subagent_type_by_tool_use, parent_tool_use_id) do
        nil -> acc
        subagent_type -> Map.put_new(acc, agent_id, subagent_type)
      end
    end)
  end

  defp extract_task_subagent_types(%{content: %{"blocks" => blocks}}) when is_list(blocks) do
    blocks
    |> Enum.filter(fn block ->
      block["type"] == "tool_use" and block["name"] == "Task" and is_binary(block["id"]) and
        is_binary(get_in(block, ["input", "subagent_type"]))
    end)
    |> Enum.map(fn block ->
      {block["id"], get_in(block, ["input", "subagent_type"])}
    end)
  end

  defp extract_task_subagent_types(_), do: []

  defp extract_agent_progress_refs(%{type: :progress, raw_payload: %{} = payload}) do
    with %{"type" => "agent_progress", "agentId" => agent_id} <- payload["data"],
         parent_tool_use_id when is_binary(parent_tool_use_id) <-
           payload["parentToolUseID"] || payload["parentToolUseId"] || payload["toolUseID"] do
      [{agent_id, parent_tool_use_id}]
    else
      _ -> []
    end
  end

  defp extract_agent_progress_refs(_), do: []

  defp find_or_create_session!(parsed) do
    case Session |> Ash.Query.filter(session_id == ^parsed.session_id) |> Ash.read_one!() do
      %Session{} = existing ->
        existing

      nil ->
        case Sessions.find_or_create(parsed.session_id, cwd: parsed.cwd) do
          {:ok, stub} -> stub
          {:error, _} -> create_session_with_db_project!(parsed)
        end
    end
  end

  defp create_session_with_db_project!(parsed) do
    project = find_project_by_cwd!(parsed.cwd)

    Ash.create!(Session, %{
      session_id: parsed.session_id,
      project_id: project.id,
      cwd: parsed.cwd
    })
  end

  defp find_project_by_cwd!(cwd) when is_binary(cwd) do
    dir_name = String.replace(cwd, "/", "-")
    basename = Path.basename(cwd)

    Spotter.Transcripts.Project
    |> Ash.read!()
    |> Enum.find(fn project ->
      pattern = Regex.compile!(project.pattern)
      Regex.match?(pattern, dir_name) or Regex.match?(pattern, basename)
    end) || raise "No project matching cwd: #{cwd}"
  end

  defp link_team_membership!(session, parsed) do
    with team_name when is_binary(team_name) <- parsed[:team_name],
         project_id when is_binary(project_id) <- session.project_id do
      team = Ash.create!(Team, %{name: team_name, project_id: project_id})

      if is_binary(parsed[:agent_name]) do
        Ash.create!(TeamMember, %{
          agent_name: parsed[:agent_name],
          team_id: team.id,
          session_id: session.id
        })
      end
    else
      _ -> :ok
    end
  end

  defp upsert_subagent!(session, parsed, subagent_type) do
    parsed_message_count = length(parsed.messages)

    case Spotter.Transcripts.Subagent
         |> Ash.Query.filter(session_id == ^session.id and agent_id == ^parsed.agent_id)
         |> Ash.read!() do
      [existing] ->
        update_attrs = %{
          slug: first_non_empty(parsed.slug, existing.slug),
          subagent_type: first_non_empty(subagent_type, existing.subagent_type),
          started_at: earliest_non_nil(existing.started_at, parsed.started_at),
          ended_at: latest_non_nil(existing.ended_at, parsed.ended_at),
          message_count: max(existing.message_count || 0, parsed_message_count)
        }

        Ash.update!(existing, update_attrs)

      [] ->
        create_attrs = %{
          agent_id: parsed.agent_id,
          session_id: session.id,
          slug: parsed.slug,
          subagent_type: subagent_type,
          started_at: parsed.started_at,
          ended_at: parsed.ended_at,
          message_count: parsed_message_count
        }

        Ash.create!(Spotter.Transcripts.Subagent, create_attrs)
    end
  end

  defp first_non_empty(nil, existing), do: existing
  defp first_non_empty("", existing), do: existing
  defp first_non_empty(new, _existing), do: new

  defp earliest_non_nil(nil, b), do: b
  defp earliest_non_nil(a, nil), do: a
  defp earliest_non_nil(a, b), do: if(DateTime.compare(a, b) in [:lt, :eq], do: a, else: b)

  defp latest_non_nil(nil, b), do: b
  defp latest_non_nil(a, nil), do: a
  defp latest_non_nil(a, b), do: if(DateTime.compare(a, b) in [:gt, :eq], do: a, else: b)
end
