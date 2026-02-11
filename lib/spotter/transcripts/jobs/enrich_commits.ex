defmodule Spotter.Transcripts.Jobs.EnrichCommits do
  @moduledoc "Oban worker that enriches commit metadata via git and triggers inference."

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  require Ash.Query

  alias Spotter.Services.SessionCommitLinker
  alias Spotter.Transcripts.{Commit, Session}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "commit_hashes" => hashes,
          "session_id" => session_id,
          "git_cwd" => git_cwd
        }
      }) do
    commits = enrich_commits(hashes, git_cwd)

    case find_session(session_id) do
      {:ok, session} ->
        SessionCommitLinker.link_inferred(session, commits)

      _ ->
        Logger.warning("EnrichCommits: session #{session_id} not found, skipping inference")
    end

    :ok
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
      {:ok, commit}
    else
      _ ->
        Logger.debug("EnrichCommits: could not enrich #{hash}")
        :error
    end
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
    case System.cmd("git", ["diff-tree", "--no-commit-id", "-r", "--name-only", hash],
           cd: cwd,
           stderr_to_stdout: true
         ) do
      {output, 0} -> output |> String.split("\n", trim: true)
      _ -> []
    end
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
