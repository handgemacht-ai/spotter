defmodule Spotter.Transcripts.Jobs.SyncTranscripts do
  @moduledoc """
  Oban worker that scans and ingests Claude Code transcripts based on config.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Spotter.Transcripts.Config
  alias Spotter.Transcripts.JsonlParser

  require Ash.Query

  @batch_size 500

  @doc """
  Enqueues sync jobs for all configured projects.
  """
  def sync_all do
    config = Config.read!()

    Enum.each(config.projects, fn {name, %{pattern: pattern}} ->
      %{
        project_name: name,
        pattern: Regex.source(pattern),
        transcripts_dir: config.transcripts_dir
      }
      |> __MODULE__.new()
      |> Oban.insert!()
    end)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "project_name" => name,
          "pattern" => pattern_str,
          "transcripts_dir" => transcripts_dir
        }
      }) do
    pattern = Regex.compile!(pattern_str)

    # Upsert project
    project = upsert_project!(name, pattern_str)

    # Find matching transcript directories
    dirs = list_matching_dirs(transcripts_dir, pattern)
    Logger.info("Syncing project #{name}: found #{length(dirs)} matching directories")

    for dir <- dirs do
      sync_directory(project, dir)
    end

    :ok
  end

  defp upsert_project!(name, pattern) do
    case Spotter.Transcripts.Project |> Ash.Query.filter(name == ^name) |> Ash.read!() do
      [project] ->
        Ash.update!(project, %{pattern: pattern})

      [] ->
        Ash.create!(Spotter.Transcripts.Project, %{name: name, pattern: pattern})
    end
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
    # Sync session JSONL files
    dir
    |> Path.join("*.jsonl")
    |> Path.wildcard()
    |> Enum.each(fn file ->
      sync_session_file(project, dir, file)
    end)
  end

  defp sync_session_file(project, dir, file) do
    transcript_dir = Path.basename(dir)

    case JsonlParser.parse_session_file(file) do
      {:ok, %{session_id: nil}} ->
        Logger.debug("Skipping file without session_id: #{file}")

      {:ok, parsed} ->
        session = upsert_session!(project, transcript_dir, parsed)
        create_messages!(session, parsed.messages)
        sync_subagents(session, dir, parsed.session_id)

      {:error, reason} ->
        Logger.warning("Failed to parse #{file}: #{inspect(reason)}")
    end
  end

  defp upsert_session!(project, transcript_dir, parsed) do
    update_attrs = %{
      slug: parsed.slug,
      cwd: parsed.cwd,
      git_branch: parsed.git_branch,
      version: parsed.version,
      started_at: parsed.started_at,
      ended_at: parsed.ended_at,
      schema_version: parsed.schema_version,
      message_count: length(parsed.messages)
    }

    case Spotter.Transcripts.Session
         |> Ash.Query.filter(session_id == ^parsed.session_id)
         |> Ash.read!() do
      [session] ->
        Ash.update!(session, update_attrs)

      [] ->
        create_attrs =
          Map.merge(update_attrs, %{
            session_id: parsed.session_id,
            transcript_dir: transcript_dir,
            project_id: project.id
          })

        Ash.create!(Spotter.Transcripts.Session, create_attrs)
    end
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
        upsert_subagent!(session, parsed)

      {:error, reason} ->
        Logger.warning("Failed to parse subagent file #{file}: #{inspect(reason)}")
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
