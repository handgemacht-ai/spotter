defmodule Spotter.Services.CoChangeCalculator do
  @moduledoc "Computes and persists co-change groups from git history for a project."

  require Logger
  require Ash.Query
  require OpenTelemetry.Tracer

  @provenance_batch_size 200

  alias Spotter.Services.CoChangeIntersections
  alias Spotter.Services.GitLogReader

  alias Spotter.Transcripts.{
    CoChangeGroup,
    CoChangeGroupCommit,
    CoChangeGroupMemberStat,
    Session
  }

  @doc """
  Backfill provenance data for existing co-change groups.

  Re-reads git history and persists commit links and member stats without
  modifying frequency computation. Safe to run multiple times (idempotent).
  """
  @spec backfill_provenance(String.t(), keyword()) :: :ok
  def backfill_provenance(project_id, opts \\ []) do
    window_days = Keyword.get(opts, :window_days, 30)

    with {:ok, repo_path} <- resolve_repo_path(project_id),
         {:ok, commits} <- read_commits(repo_path, project_id, window_days) do
      commit_maps =
        Enum.map(commits, fn c ->
          %{hash: c.hash, timestamp: c.timestamp, files: c.files}
        end)

      file_groups = CoChangeIntersections.compute(commit_maps, scope: :file)
      dir_groups = CoChangeIntersections.compute(commit_maps, scope: :directory)

      persist_provenance(project_id, :file, file_groups, repo_path)
      persist_provenance(project_id, :directory, dir_groups, repo_path)
    end

    :ok
  end

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

      persist_provenance(project_id, :file, file_groups, repo_path)
      persist_provenance(project_id, :directory, dir_groups, repo_path)
    end

    :ok
  end

  defp read_commits(repo_path, project_id, window_days) do
    case GitLogReader.changed_files_by_commit(repo_path,
           since_days: window_days,
           filter_spotterignore: true
         ) do
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

  defp persist_provenance(project_id, scope, groups, repo_path) do
    OpenTelemetry.Tracer.with_span "co_change.persist_provenance",
      attributes: %{project_id: project_id, scope: to_string(scope)} do
      Enum.each(groups, fn group ->
        persist_group_provenance(project_id, scope, group, repo_path)
      end)
    end
  end

  defp persist_group_provenance(project_id, scope, group, repo_path) do
    OpenTelemetry.Tracer.with_span "co_change.persist_group_provenance",
      attributes: %{group_key: group.group_key} do
      upsert_group_commits(project_id, scope, group)
      delete_stale_group_commits(project_id, scope, group)
      persist_member_stats(project_id, scope, group, repo_path)
      delete_stale_member_stats(project_id, scope, group)
    end
  rescue
    e ->
      Logger.warning(
        "CoChangeCalculator: provenance persistence failed for group #{group.group_key}: #{Exception.message(e)}"
      )

      OpenTelemetry.Tracer.set_status(:error, Exception.message(e))
  end

  defp upsert_group_commits(project_id, scope, group) do
    attrs_list =
      Enum.map(group.matching_commits, fn mc ->
        %{
          project_id: project_id,
          scope: scope,
          group_key: group.group_key,
          commit_hash: mc.hash,
          committed_at: mc.timestamp
        }
      end)

    batches = Enum.chunk_every(attrs_list, @provenance_batch_size)

    OpenTelemetry.Tracer.set_attributes(%{
      matching_commit_count: length(attrs_list),
      commit_upsert_batches: length(batches),
      provenance_batch_size: @provenance_batch_size
    })

    Enum.each(batches, fn batch ->
      Ash.bulk_create!(batch, CoChangeGroupCommit, :create)
    end)
  end

  defp delete_stale_group_commits(project_id, scope, group) do
    current_hashes = MapSet.new(group.matching_commits, & &1.hash)

    CoChangeGroupCommit
    |> Ash.Query.filter(
      project_id == ^project_id and scope == ^scope and group_key == ^group.group_key
    )
    |> Ash.read!()
    |> Enum.reject(fn row -> MapSet.member?(current_hashes, row.commit_hash) end)
    |> Enum.each(&Ash.destroy!/1)
  end

  defp persist_member_stats(project_id, scope, group, repo_path) do
    # Use the commit corresponding to last_seen_at as the measurement point
    measured_commit =
      group.matching_commits
      |> Enum.max_by(& &1.timestamp, DateTime, fn -> nil end)

    if measured_commit do
      OpenTelemetry.Tracer.with_span "co_change.persist_member_stats",
        attributes: %{
          group_key: group.group_key,
          measured_commit_hash: measured_commit.hash
        } do
        attrs_list =
          group.members
          |> Enum.flat_map(fn member_path ->
            build_member_stat_attrs(
              project_id,
              scope,
              group.group_key,
              member_path,
              measured_commit,
              repo_path
            )
          end)

        batches = Enum.chunk_every(attrs_list, @provenance_batch_size)

        OpenTelemetry.Tracer.set_attributes(%{
          member_count: length(group.members),
          member_stat_upsert_batches: length(batches),
          provenance_batch_size: @provenance_batch_size
        })

        Enum.each(batches, fn batch ->
          Ash.bulk_create!(batch, CoChangeGroupMemberStat, :create)
        end)
      end
    end
  end

  defp build_member_stat_attrs(
         project_id,
         scope,
         group_key,
         member_path,
         measured_commit,
         repo_path
       ) do
    {size_bytes, loc} = read_file_metrics(repo_path, measured_commit.hash, member_path)

    [
      %{
        project_id: project_id,
        scope: scope,
        group_key: group_key,
        member_path: member_path,
        size_bytes: size_bytes,
        loc: loc,
        measured_commit_hash: measured_commit.hash,
        measured_at: measured_commit.timestamp
      }
    ]
  rescue
    e ->
      Logger.warning(
        "CoChangeCalculator: member stat failed for #{member_path} in group #{group_key}: #{Exception.message(e)}"
      )

      []
  end

  defp delete_stale_member_stats(project_id, scope, group) do
    current_members = MapSet.new(group.members)

    CoChangeGroupMemberStat
    |> Ash.Query.filter(
      project_id == ^project_id and scope == ^scope and group_key == ^group.group_key
    )
    |> Ash.read!()
    |> Enum.reject(fn row -> MapSet.member?(current_members, row.member_path) end)
    |> Enum.each(&Ash.destroy!/1)
  end

  @doc false
  def read_file_metrics(repo_path, commit_hash, file_path) do
    case System.cmd("git", ["-C", repo_path, "show", "#{commit_hash}:#{file_path}"],
           stderr_to_stdout: true
         ) do
      {content, 0} ->
        size = byte_size(content)

        loc =
          content
          |> String.split("\n")
          |> Enum.count(fn line -> String.trim(line) != "" end)

        {size, loc}

      {_error, _} ->
        {nil, nil}
    end
  end
end
