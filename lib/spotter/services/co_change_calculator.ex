defmodule Spotter.Services.CoChangeCalculator do
  @moduledoc "Computes and persists co-change groups from git history for a project."

  require Logger
  require Ash.Query

  alias Spotter.Services.CoChangeIntersections
  alias Spotter.Services.GitLogReader
  alias Spotter.Transcripts.{CoChangeGroup, Session}

  @doc """
  Compute co-change groups for a project.

  Options:
    - :window_days - rolling window in days (default 30)
  """
  @spec compute(String.t(), keyword()) :: :ok
  def compute(project_id, opts \\ []) do
    window_days = Keyword.get(opts, :window_days, 30)

    with {:ok, repo_path} <- resolve_repo_path(project_id),
         {:ok, commits} <- read_commits(repo_path, project_id, window_days) do
      commit_maps =
        Enum.map(commits, fn c ->
          %{hash: c.hash, timestamp: c.timestamp, files: c.files}
        end)

      file_groups = CoChangeIntersections.compute(commit_maps, scope: :file)
      dir_groups = CoChangeIntersections.compute(commit_maps, scope: :directory)

      upsert_groups(project_id, :file, file_groups)
      upsert_groups(project_id, :directory, dir_groups)
      delete_stale(project_id, :file, file_groups)
      delete_stale(project_id, :directory, dir_groups)
    end

    :ok
  end

  defp read_commits(repo_path, project_id, window_days) do
    case GitLogReader.changed_files_by_commit(repo_path, since_days: window_days) do
      {:ok, commits} ->
        {:ok, commits}

      {:error, reason} ->
        Logger.warning(
          "CoChangeCalculator: git error for project #{project_id}: #{inspect(reason)}"
        )

        :skip
    end
  end

  defp resolve_repo_path(project_id) do
    case Session
         |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
         |> Ash.Query.sort(inserted_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read!() do
      [session] ->
        if File.dir?(session.cwd) do
          {:ok, session.cwd}
        else
          Logger.warning("CoChangeCalculator: cwd #{session.cwd} not accessible, skipping")

          :skip
        end

      [] ->
        Logger.warning("CoChangeCalculator: no sessions with cwd for project #{project_id}")

        :skip
    end
  end

  defp upsert_groups(project_id, scope, groups) do
    Enum.each(groups, fn group ->
      Ash.create!(CoChangeGroup, %{
        project_id: project_id,
        scope: scope,
        group_key: group.group_key,
        members: group.members,
        frequency_30d: group.frequency_30d,
        last_seen_at: group.last_seen_at
      })
    end)
  end

  defp delete_stale(project_id, scope, current_groups) do
    current_keys = MapSet.new(current_groups, & &1.group_key)

    existing =
      CoChangeGroup
      |> Ash.Query.filter(project_id == ^project_id and scope == ^scope)
      |> Ash.read!()

    existing
    |> Enum.reject(fn row -> MapSet.member?(current_keys, row.group_key) end)
    |> Enum.each(&Ash.destroy!/1)
  end
end
