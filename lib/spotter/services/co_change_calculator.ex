defmodule Spotter.Services.CoChangeCalculator do
  @moduledoc """
  Computes and persists co-change groups from git history for a project.

  Supports two modes:

  - **Full rebuild** — reads all commits in the rolling window, runs the full
    intersection/minimal-generator algorithm (via `CoChangeIntersections`), and
    rewrites all groups, provenance, and member stats.

  - **Delta mode** — processes only new and expired commits, maintaining
    **pair-level** (size-2) groups incrementally. Member stats are skipped in
    delta mode (the UI handles empty stats gracefully). A full rebuild is
    triggered automatically when the watermark is missing, stale, or the window
    size changed.

  Mode selection is automatic based on `ProjectIngestState` watermarks.
  """

  require Logger
  require Ash.Query
  require OpenTelemetry.Tracer

  alias Spotter.Observability.ErrorReport

  @provenance_batch_size 200
  @max_pair_members 100

  @binary_extensions ~w(.png .jpg .jpeg .gif .bmp .ico .svg .webp .woff .woff2 .ttf .eot .otf
    .pdf .zip .tar .gz .bz2 .7z .exe .dll .so .dylib .o .beam .ez .pyc .class .jar)

  alias Spotter.Services.CoChangeIntersections
  alias Spotter.Services.GitLogReader

  alias Spotter.Transcripts.{
    CoChangeGroup,
    CoChangeGroupCommit,
    CoChangeGroupMemberStat,
    ProjectIngestState,
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

  Automatically selects delta or full mode based on watermark state.

  Options:
    - :window_days - rolling window in days (default 30)
    - :reference_date - for deterministic tests (default DateTime.utc_now())
  """
  @spec compute(String.t(), keyword()) :: :ok
  def compute(project_id, opts \\ []) do
    window_days = Keyword.get(opts, :window_days, 30)
    reference_date = Keyword.get(opts, :reference_date, DateTime.utc_now())

    case load_ingest_state(project_id) do
      {:ok, state} when not is_nil(state.co_change_last_run_at) ->
        maybe_delta(project_id, state, window_days, reference_date)

      _ ->
        compute_full(project_id, window_days, reference_date, :no_watermark)
    end
  end

  defp maybe_delta(project_id, state, window_days, reference_date) do
    prev_ref = state.co_change_last_run_at
    age_seconds = DateTime.diff(reference_date, prev_ref, :second)
    window_changed = state.co_change_window_days != window_days

    cond do
      window_changed ->
        compute_full(project_id, window_days, reference_date, :window_changed)

      age_seconds > window_days * 86_400 ->
        compute_full(project_id, window_days, reference_date, :watermark_too_old)

      true ->
        compute_delta(project_id, prev_ref, window_days, reference_date)
    end
  end

  # --- Full compute ---

  defp compute_full(project_id, window_days, reference_date, reason) do
    OpenTelemetry.Tracer.with_span "co_change.compute_full" do
      OpenTelemetry.Tracer.set_attributes([
        {"spotter.project_id", project_id},
        {"spotter.window_days", window_days},
        {"spotter.co_change.mode", "full"},
        {"spotter.co_change.fallback_full", Atom.to_string(reason)}
      ])

      since = DateTime.add(reference_date, -window_days * 86_400, :second)

      with {:ok, repo_path} <- resolve_repo_path(project_id),
           {:ok, commits} <-
             read_commits_range(repo_path, project_id, since, reference_date) do
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

        # Seed ALL pair-level group commits so delta mode has a complete baseline.
        # The intersection algorithm only persists provenance for discovered groups
        # (freq >= 2), but delta needs every commit-pair mapping to count correctly.
        seed_pair_group_commits(project_id, commits)
      end

      persist_watermark(project_id, reference_date, window_days)
      :ok
    end
  end

  # --- Delta compute ---

  defp compute_delta(project_id, prev_ref, window_days, reference_date) do
    OpenTelemetry.Tracer.with_span "co_change.compute_delta" do
      since = DateTime.add(reference_date, -window_days * 86_400, :second)
      prev_since = DateTime.add(prev_ref, -window_days * 86_400, :second)

      with {:ok, repo_path} <- resolve_repo_path(project_id) do
        new_commits = load_new_commits(repo_path, project_id, prev_ref, reference_date)
        expired_commits = load_expired_commits(repo_path, project_id, prev_since, since)

        touched_groups = MapSet.new()

        touched_groups =
          Enum.reduce([:file, :directory], touched_groups, fn scope, acc ->
            added_pairs = commits_to_pairs(new_commits, scope)
            removed_pairs = commits_to_pairs(expired_commits, scope)

            upsert_delta_group_commits(project_id, scope, added_pairs)
            delete_delta_group_commits(project_id, scope, removed_pairs)

            touched_keys =
              MapSet.union(
                MapSet.new(Map.keys(added_pairs)),
                MapSet.new(Map.keys(removed_pairs))
              )

            recompute_touched_groups(project_id, scope, touched_keys)

            MapSet.union(acc, touched_keys)
          end)

        OpenTelemetry.Tracer.set_attributes([
          {"spotter.project_id", project_id},
          {"spotter.window_days", window_days},
          {"spotter.co_change.mode", "delta"},
          {"spotter.co_change.new_commits_count", length(new_commits)},
          {"spotter.co_change.expired_commits_count", length(expired_commits)},
          {"spotter.co_change.touched_groups_count", MapSet.size(touched_groups)}
        ])
      end

      persist_watermark(project_id, reference_date, window_days)
      :ok
    end
  end

  defp load_new_commits(repo_path, project_id, prev_ref, reference_date) do
    case GitLogReader.changed_files_by_commit(repo_path,
           since: prev_ref,
           until: reference_date,
           filter_spotterignore: true
         ) do
      {:ok, commits} ->
        # --since is inclusive, drop commits at or before prev_ref
        Enum.filter(commits, fn c ->
          DateTime.compare(c.timestamp, prev_ref) == :gt
        end)

      {:error, reason} ->
        Logger.warning(
          "CoChangeCalculator: git error loading new commits for #{project_id}: #{inspect(reason)}"
        )

        []
    end
  end

  defp load_expired_commits(repo_path, project_id, prev_since, since) do
    case GitLogReader.changed_files_by_commit(repo_path,
           since: prev_since,
           until: since,
           filter_spotterignore: true
         ) do
      {:ok, commits} ->
        # Keep only commits that truly aged out (timestamp < since)
        Enum.filter(commits, fn c ->
          DateTime.compare(c.timestamp, since) == :lt
        end)

      {:error, reason} ->
        Logger.warning(
          "CoChangeCalculator: git error loading expired commits for #{project_id}: #{inspect(reason)}"
        )

        []
    end
  end

  defp commits_to_pairs(commits, scope) do
    commits
    |> Enum.flat_map(&commit_to_pair_entries(&1, scope))
    |> Enum.group_by(fn {key, _} -> key end, fn {_, val} -> val end)
  end

  defp commit_to_pair_entries(commit, scope) do
    members = normalize_commit_members(commit.files, scope)

    if length(members) > @max_pair_members do
      Logger.warning(
        "CoChangeCalculator: skipping commit #{commit.hash} with #{length(members)} members (> #{@max_pair_members})"
      )

      OpenTelemetry.Tracer.set_attribute(
        "spotter.co_change.skipped_large_commit",
        commit.hash
      )

      []
    else
      pairs = generate_pairs(members)

      Enum.map(pairs, fn [a, b] ->
        sorted = Enum.sort([a, b])
        group_key = Enum.join(sorted, "|")
        {group_key, %{commit_hash: commit.hash, committed_at: commit.timestamp, members: sorted}}
      end)
    end
  end

  defp normalize_commit_members(files, :file) do
    files
    |> Enum.reject(&binary_file?/1)
    |> Enum.uniq()
  end

  defp normalize_commit_members(files, :directory) do
    files
    |> Enum.map(fn file ->
      case Path.dirname(file) do
        "." -> "."
        dir -> dir
      end
    end)
    |> Enum.uniq()
  end

  defp binary_file?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in @binary_extensions
  end

  defp generate_pairs(members) when length(members) < 2, do: []

  defp generate_pairs(members) do
    for {a, i} <- Enum.with_index(members),
        {b, j} <- Enum.with_index(members),
        i < j,
        do: [a, b]
  end

  defp seed_pair_group_commits(project_id, commits) do
    Enum.each([:file, :directory], fn scope ->
      pairs_by_key = commits_to_pairs(commits, scope)
      upsert_delta_group_commits(project_id, scope, pairs_by_key)
    end)
  end

  defp upsert_delta_group_commits(project_id, scope, pairs_by_key) do
    Enum.each(pairs_by_key, fn {group_key, commit_entries} ->
      attrs_list =
        Enum.map(commit_entries, fn entry ->
          %{
            project_id: project_id,
            scope: scope,
            group_key: group_key,
            commit_hash: entry.commit_hash,
            committed_at: entry.committed_at
          }
        end)

      Enum.chunk_every(attrs_list, @provenance_batch_size)
      |> Enum.each(fn batch ->
        Ash.bulk_create!(batch, CoChangeGroupCommit, :create)
      end)
    end)
  end

  defp delete_delta_group_commits(project_id, scope, pairs_by_key) do
    Enum.each(pairs_by_key, fn {group_key, commit_entries} ->
      hashes = MapSet.new(commit_entries, & &1.commit_hash)

      CoChangeGroupCommit
      |> Ash.Query.filter(
        project_id == ^project_id and scope == ^scope and group_key == ^group_key
      )
      |> Ash.read!()
      |> Enum.filter(fn row -> MapSet.member?(hashes, row.commit_hash) end)
      |> Enum.each(&Ash.destroy!/1)
    end)
  end

  defp recompute_touched_groups(project_id, scope, touched_keys) do
    Enum.each(touched_keys, fn group_key ->
      rows =
        CoChangeGroupCommit
        |> Ash.Query.filter(
          project_id == ^project_id and scope == ^scope and group_key == ^group_key
        )
        |> Ash.read!()

      freq = length(rows)

      if freq >= 2 do
        last_seen = rows |> Enum.map(& &1.committed_at) |> Enum.max(DateTime)
        members = String.split(group_key, "|")

        Ash.create!(CoChangeGroup, %{
          project_id: project_id,
          scope: scope,
          group_key: group_key,
          members: members,
          frequency_30d: freq,
          last_seen_at: last_seen
        })
      else
        # Delete group if frequency dropped below threshold
        CoChangeGroup
        |> Ash.Query.filter(
          project_id == ^project_id and scope == ^scope and group_key == ^group_key
        )
        |> Ash.read!()
        |> Enum.each(&Ash.destroy!/1)

        # Clean up stale member stats for deleted groups
        CoChangeGroupMemberStat
        |> Ash.Query.filter(
          project_id == ^project_id and scope == ^scope and group_key == ^group_key
        )
        |> Ash.read!()
        |> Enum.each(&Ash.destroy!/1)
      end
    end)
  end

  # --- Shared helpers ---

  defp load_ingest_state(project_id) do
    case ProjectIngestState
         |> Ash.Query.filter(project_id == ^project_id)
         |> Ash.read!() do
      [state] -> {:ok, state}
      [] -> :none
    end
  end

  defp persist_watermark(project_id, reference_date, window_days) do
    Ash.create!(ProjectIngestState, %{
      project_id: project_id,
      co_change_last_run_at: reference_date,
      co_change_window_days: window_days
    })
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

  defp read_commits_range(repo_path, project_id, since, until_dt) do
    case GitLogReader.changed_files_by_commit(repo_path,
           since: since,
           until: until_dt,
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

      ErrorReport.set_trace_error(
        "provenance_error",
        Exception.message(e),
        "services.co_change_calculator"
      )
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
