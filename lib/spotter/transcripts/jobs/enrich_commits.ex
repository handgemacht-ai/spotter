defmodule Spotter.Transcripts.Jobs.EnrichCommits do
  @moduledoc "Oban worker that enriches commit metadata via git and triggers inference."

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Search.Jobs.ReindexProject
  alias Spotter.Services.SessionCommitLinker
  alias Spotter.Transcripts.{Commit, CommitFile, Session}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "commit_hashes" => hashes,
      "session_id" => session_id,
      "git_cwd" => git_cwd
    } = args

    Tracer.with_span "spotter.enrich_commits.perform" do
      set_span_attributes(hashes, session_id, args)
      do_perform(hashes, session_id, git_cwd)
    end
  end

  defp do_perform(hashes, session_id, git_cwd) do
    commits = enrich_commits(hashes, git_cwd)

    case find_session(session_id) do
      {:ok, session} ->
        SessionCommitLinker.link_inferred(session, commits)
        enqueue_reindex(session.project_id)

      _ ->
        Tracer.add_event("session_not_found", [{"spotter.session_id", session_id}])
        Logger.warning("EnrichCommits: session #{session_id} not found, skipping inference")
    end

    :ok
  end

  defp enqueue_reindex(project_id) when is_binary(project_id) do
    %{project_id: project_id} |> ReindexProject.new() |> Oban.insert()
  end

  defp enqueue_reindex(_), do: :ok

  defp set_span_attributes(hashes, session_id, args) do
    Tracer.set_attribute("spotter.commit_hash_count", length(hashes))
    Tracer.set_attribute("spotter.session_id", session_id)

    if is_binary(args["otel_trace_id"]) and args["otel_trace_id"] != "" do
      Tracer.set_attribute("spotter.parent_trace_id", args["otel_trace_id"])
    end

    if is_binary(args["otel_traceparent"]) and args["otel_traceparent"] != "" do
      Tracer.set_attribute("spotter.parent_traceparent", args["otel_traceparent"])
    end
  rescue
    _error -> :ok
  end

  defp enrich_commits(hashes, git_cwd) do
    Enum.flat_map(hashes, fn hash ->
      case enrich_one(hash, git_cwd) do
        {:ok, commit} -> [commit]
        :error -> []
      end
    end)
  end

  defp enrich_one(hash, git_cwd) do
    with {:ok, metadata} <- git_show(hash, git_cwd),
         {:ok, commit} <- update_commit(hash, metadata) do
      upsert_commit_files(commit, git_cwd)
      {:ok, commit}
    else
      _ ->
        Logger.debug("EnrichCommits: could not enrich #{hash}")
        set_enrich_error(hash)
        :error
    end
  end

  defp set_enrich_error(hash) do
    Tracer.add_event("enrich_commit_failed", [{"spotter.commit_hash", hash}])
  rescue
    _error -> :ok
  end

  defp git_show(hash, cwd) do
    format = "%P%n%s%n%b%n%an%n%ae%n%aI%n%cI"

    case System.cmd("git", ["show", "--no-patch", "--format=#{format}", hash],
           cd: cwd,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        parse_git_show(output, hash, cwd)

      _ ->
        :error
    end
  end

  defp parse_git_show(output, hash, cwd) do
    lines = String.split(output, "\n")

    if length(lines) >= 7 do
      parent_hashes = lines |> Enum.at(0, "") |> String.split(" ", trim: true)
      subject = Enum.at(lines, 1, "")
      body = Enum.at(lines, 2, "")
      author_name = Enum.at(lines, 3, "")
      author_email = Enum.at(lines, 4, "")
      authored_at = parse_datetime(Enum.at(lines, 5, ""))
      committed_at = parse_datetime(Enum.at(lines, 6, ""))

      changed_files = git_changed_files(hash, cwd)
      patch_id = git_patch_id(hash, cwd)

      {:ok,
       %{
         parent_hashes: parent_hashes,
         subject: subject,
         body: body,
         author_name: author_name,
         author_email: author_email,
         authored_at: authored_at,
         committed_at: committed_at,
         changed_files: changed_files,
         patch_id_stable: patch_id
       }}
    else
      :error
    end
  end

  defp git_changed_files(hash, cwd) do
    case git_changed_files_with_status(hash, cwd) do
      entries when is_list(entries) -> Enum.map(entries, fn {path, _status} -> path end)
      _ -> []
    end
  end

  defp git_changed_files_with_status(hash, cwd) do
    case System.cmd("git", ["diff-tree", "--no-commit-id", "-r", "--name-status", hash],
           cd: cwd,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&parse_name_status_line/1)

      _ ->
        []
    end
  end

  defp parse_name_status_line(line) do
    case String.split(line, "\t", parts: 2) do
      [status, path] -> [{path, parse_git_status(status)}]
      _ -> []
    end
  end

  defp parse_git_status("A"), do: :added
  defp parse_git_status("M"), do: :modified
  defp parse_git_status("D"), do: :deleted
  defp parse_git_status("R" <> _), do: :renamed
  defp parse_git_status(_), do: :modified

  defp upsert_commit_files(commit, cwd) do
    entries = git_changed_files_with_status(commit.commit_hash, cwd)

    Enum.each(entries, fn {path, change_type} ->
      Ash.create(CommitFile, %{
        commit_id: commit.id,
        relative_path: path,
        change_type: change_type
      })
    end)
  rescue
    error ->
      Logger.debug("EnrichCommits: failed to upsert commit files: #{inspect(error)}")
  end

  defp git_patch_id(hash, cwd) do
    case System.cmd("bash", ["-c", "git show #{hash} | git patch-id --stable"],
           cd: cwd,
           stderr_to_stdout: true
         ) do
      {output, 0} -> output |> String.split(" ") |> List.first()
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp update_commit(hash, metadata) do
    case Commit |> Ash.Query.filter(commit_hash == ^hash) |> Ash.read_one() do
      {:ok, nil} -> :error
      {:ok, commit} -> Ash.update(commit, metadata)
      _ -> :error
    end
  end

  defp find_session(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, nil} -> :error
      {:ok, session} -> {:ok, session}
      _ -> :error
    end
  end
end
