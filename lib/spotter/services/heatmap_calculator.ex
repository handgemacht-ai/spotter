defmodule Spotter.Services.HeatmapCalculator do
  @moduledoc "Computes file change frequency and heat scores from FileSnapshot data + git history."

  require Logger
  require Ash.Query
  require OpenTelemetry.Tracer

  alias Spotter.Services.GitLogReader
  alias Spotter.Transcripts.{FileHeatmap, FileSnapshot, ProjectIngestState, Session}

  @binary_extensions ~w(.png .jpg .jpeg .gif .bmp .ico .svg .webp .woff .woff2 .ttf .eot .otf
    .pdf .zip .tar .gz .bz2 .7z .exe .dll .so .dylib .o .beam .ez .pyc .class .jar)

  @doc """
  Compute heatmap data for a project.

  Automatically selects delta or full mode based on watermark state.

  Options:
    - :window_days - rolling window in days (default 30)
    - :reference_date - for deterministic tests (default DateTime.utc_now())
  """
  @spec compute(String.t(), keyword()) :: :ok | {:error, term()}
  def compute(project_id, opts \\ []) do
    window_days = Keyword.get(opts, :window_days, 30)
    reference_date = Keyword.get(opts, :reference_date, DateTime.utc_now())

    case load_ingest_state(project_id) do
      {:ok, state} when not is_nil(state.heatmap_last_run_at) ->
        maybe_delta(project_id, state, window_days, reference_date)

      _ ->
        compute_full(project_id, window_days, reference_date, :no_watermark)
    end
  end

  defp maybe_delta(project_id, state, window_days, reference_date) do
    prev_ref = state.heatmap_last_run_at
    age_seconds = DateTime.diff(reference_date, prev_ref, :second)
    window_changed = state.heatmap_window_days != window_days

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
    OpenTelemetry.Tracer.with_span "heatmap.compute_full" do
      OpenTelemetry.Tracer.set_attributes([
        {"spotter.project_id", project_id},
        {"spotter.window_days", window_days},
        {"spotter.heatmap.mode", "full"},
        {"spotter.heatmap.fallback_full", Atom.to_string(reason)}
      ])

      since = DateTime.add(reference_date, -window_days * 86_400, :second)

      snapshot_data = load_snapshot_data(project_id, since)
      git_data = load_git_data(project_id, since: since, until: reference_date)

      file_map = merge_data(snapshot_data, git_data)
      repo_path = resolve_repo_path(project_id)
      file_sizes = read_all_file_sizes(repo_path)

      upsert_heatmaps(project_id, file_map, reference_date, file_sizes)
      delete_stale_rows(project_id, file_map)
      persist_watermark(project_id, reference_date, window_days)

      :ok
    end
  end

  # --- Delta compute ---

  defp compute_delta(project_id, prev_ref, window_days, reference_date) do
    OpenTelemetry.Tracer.with_span "heatmap.compute_delta" do
      since = DateTime.add(reference_date, -window_days * 86_400, :second)
      prev_since = DateTime.add(prev_ref, -window_days * 86_400, :second)

      added_events = load_added_events(project_id, prev_ref, reference_date, since)
      removed_events = load_removed_events(project_id, prev_since, since)

      added_agg = aggregate_events(added_events)
      removed_agg = aggregate_events(removed_events)

      affected_paths =
        MapSet.union(
          MapSet.new(Map.keys(added_agg)),
          MapSet.new(Map.keys(removed_agg))
        )

      OpenTelemetry.Tracer.set_attributes([
        {"spotter.project_id", project_id},
        {"spotter.window_days", window_days},
        {"spotter.heatmap.mode", "delta"},
        {"spotter.heatmap.added_paths_count", map_size(added_agg)},
        {"spotter.heatmap.removed_paths_count", map_size(removed_agg)},
        {"spotter.heatmap.affected_paths_count", MapSet.size(affected_paths)}
      ])

      repo_path = resolve_repo_path(project_id)

      apply_delta(
        project_id,
        affected_paths,
        added_agg,
        removed_agg,
        reference_date,
        since,
        repo_path
      )

      persist_watermark(project_id, reference_date, window_days)
      :ok
    end
  end

  defp load_added_events(project_id, prev_ref, reference_date, _since) do
    snap_events = load_snapshot_events(project_id, prev_ref, reference_date)
    git_events = load_git_events(project_id, prev_ref, reference_date)
    snap_events ++ git_events
  end

  defp load_removed_events(project_id, prev_since, since) do
    snap_events = load_snapshot_events(project_id, prev_since, since)
    git_events = load_git_events(project_id, prev_since, since)
    snap_events ++ git_events
  end

  defp load_snapshot_events(project_id, from, to) do
    session_ids = load_session_ids(project_id)

    if session_ids == [] do
      []
    else
      FileSnapshot
      |> Ash.Query.filter(session_id in ^session_ids and timestamp > ^from and timestamp <= ^to)
      |> Ash.read!()
      |> Enum.map(fn snap ->
        path = snap.relative_path || snap.file_path
        {path, snap.timestamp}
      end)
      |> Enum.reject(fn {path, _} -> binary_file?(path) end)
    end
  end

  defp load_git_events(project_id, from, to) do
    case resolve_repo_path(project_id) do
      {:ok, repo_path} ->
        fetch_and_filter_git_events(repo_path, from, to)

      :skip ->
        []
    end
  end

  defp fetch_and_filter_git_events(repo_path, from, to) do
    case GitLogReader.changed_files_by_commit(repo_path, since: from, until: to) do
      {:ok, commits} ->
        commits
        |> commits_to_file_events()
        |> Enum.filter(fn {path, ts} ->
          not binary_file?(path) and
            DateTime.compare(ts, from) == :gt and DateTime.compare(ts, to) != :gt
        end)

      {:error, _} ->
        []
    end
  end

  defp commits_to_file_events(commits) do
    Enum.flat_map(commits, fn c ->
      Enum.map(c.files, fn f -> {f, c.timestamp} end)
    end)
  end

  defp aggregate_events(events) do
    events
    |> Enum.group_by(fn {path, _} -> path end, fn {_, ts} -> ts end)
    |> Map.new(fn {path, timestamps} ->
      {path, %{count: length(timestamps), max_ts: Enum.max(timestamps, DateTime)}}
    end)
  end

  defp apply_delta(project_id, affected_paths, added, removed, ref_date, since, repo_path) do
    existing_rows = load_existing_rows(project_id, affected_paths)
    ctx = %{project_id: project_id, repo_path: repo_path, since: since, ref_date: ref_date}

    Enum.each(affected_paths, fn path ->
      existing = Map.get(existing_rows, path)
      added_data = Map.get(added, path, %{count: 0, max_ts: nil})
      removed_data = Map.get(removed, path, %{count: 0, max_ts: nil})

      old_count = if existing, do: existing.change_count_30d, else: 0
      new_count = old_count + added_data.count - removed_data.count

      apply_delta_for_path(ctx, path, existing, new_count, added_data, removed_data)
    end)
  end

  defp apply_delta_for_path(_ctx, _path, existing, new_count, _, _) when new_count <= 0 do
    if existing, do: Ash.destroy!(existing)
  end

  defp apply_delta_for_path(ctx, path, existing, new_count, added_data, removed_data) do
    last_changed =
      resolve_last_changed(
        existing,
        added_data,
        removed_data,
        ctx.repo_path,
        path,
        ctx.since,
        ctx.ref_date
      )

    heat_score = calculate_heat_score(new_count, last_changed, ctx.ref_date)
    {size_bytes, loc} = read_file_metrics(ctx.repo_path, path)

    Ash.create!(FileHeatmap, %{
      project_id: ctx.project_id,
      relative_path: path,
      change_count_30d: new_count,
      heat_score: heat_score,
      last_changed_at: last_changed,
      size_bytes: size_bytes,
      loc: loc
    })
  end

  defp resolve_last_changed(existing, added_data, removed_data, repo_path, path, since, ref_date) do
    old_max = if existing, do: existing.last_changed_at
    added_max = added_data.max_ts
    removed_max = removed_data.max_ts

    candidates = Enum.reject([old_max, added_max], &is_nil/1)
    new_max = if candidates != [], do: Enum.max(candidates, DateTime)

    needs_recompute =
      removed_max != nil and old_max != nil and
        DateTime.compare(removed_max, old_max) != :lt

    if needs_recompute do
      recompute_last_changed(repo_path, path, since, ref_date, new_max)
    else
      new_max || old_max
    end
  end

  defp recompute_last_changed(repo_path, path, since, ref_date, fallback) do
    case repo_path do
      {:ok, rp} ->
        case GitLogReader.last_file_touch(rp, path, since: since, until: ref_date) do
          {:ok, ts} -> ts
          _ -> fallback
        end

      :skip ->
        fallback
    end
  end

  defp load_existing_rows(project_id, affected_paths) do
    path_list = MapSet.to_list(affected_paths)

    if path_list == [] do
      %{}
    else
      FileHeatmap
      |> Ash.Query.filter(project_id == ^project_id and relative_path in ^path_list)
      |> Ash.read!()
      |> Map.new(fn row -> {row.relative_path, row} end)
    end
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
      heatmap_last_run_at: reference_date,
      heatmap_window_days: window_days
    })
  end

  defp load_session_ids(project_id) do
    Session
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.read!()
    |> Enum.map(& &1.id)
  end

  defp load_snapshot_data(project_id, since) do
    session_ids = load_session_ids(project_id)

    if session_ids == [] do
      []
    else
      FileSnapshot
      |> Ash.Query.filter(session_id in ^session_ids and timestamp >= ^since)
      |> Ash.read!()
    end
  end

  defp load_git_data(project_id, opts) do
    case resolve_repo_path(project_id) do
      {:ok, repo_path} ->
        case GitLogReader.changed_files_by_commit(repo_path, opts) do
          {:ok, commits} -> commits
          {:error, _} -> []
        end

      :skip ->
        []
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
          Logger.warning("HeatmapCalculator: cwd #{session.cwd} not accessible, skipping git")
          :skip
        end

      [] ->
        Logger.warning("HeatmapCalculator: no sessions with cwd for project #{project_id}")
        :skip
    end
  end

  defp merge_data(snapshots, git_commits) do
    snapshot_entries =
      Enum.map(snapshots, fn snap ->
        path = snap.relative_path || snap.file_path
        {path, snap.timestamp}
      end)

    git_entries =
      Enum.flat_map(git_commits, fn commit ->
        Enum.map(commit.files, fn file -> {file, commit.timestamp} end)
      end)

    (snapshot_entries ++ git_entries)
    |> Enum.reject(fn {path, _} -> binary_file?(path) end)
    |> Enum.group_by(fn {path, _} -> path end, fn {_, ts} -> ts end)
    |> Map.new(fn {path, timestamps} ->
      {path,
       %{
         change_count: length(timestamps),
         last_changed_at: Enum.max(timestamps, DateTime)
       }}
    end)
  end

  defp binary_file?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in @binary_extensions
  end

  defp upsert_heatmaps(project_id, file_map, reference_date, file_sizes) do
    Enum.each(file_map, fn {path, data} ->
      heat_score = calculate_heat_score(data.change_count, data.last_changed_at, reference_date)
      {size_bytes, loc} = Map.get(file_sizes, path, {nil, nil})

      Ash.create!(FileHeatmap, %{
        project_id: project_id,
        relative_path: path,
        change_count_30d: data.change_count,
        heat_score: heat_score,
        last_changed_at: data.last_changed_at,
        size_bytes: size_bytes,
        loc: loc
      })
    end)
  end

  defp delete_stale_rows(project_id, file_map) do
    current_paths = Map.keys(file_map)

    existing =
      FileHeatmap
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.read!()

    stale = Enum.filter(existing, fn row -> row.relative_path not in current_paths end)
    Enum.each(stale, &Ash.destroy!/1)
  end

  @doc """
  Calculate heat score from change count and recency.

  Formula:
    frequency_norm = min(log1p(change_count) / log(21), 1.0)
    recency_norm = exp(-days_since / 14)
    heat_score = (0.65 * frequency_norm + 0.35 * recency_norm) * 100
  """
  @spec calculate_heat_score(non_neg_integer(), DateTime.t(), DateTime.t()) :: float()
  def calculate_heat_score(change_count, last_changed_at, reference_date) do
    days_since = max(DateTime.diff(reference_date, last_changed_at, :second) / 86_400, 0)
    frequency_norm = min(:math.log(1 + change_count) / :math.log(21), 1.0)
    recency_norm = :math.exp(-days_since / 14)

    Float.round((0.65 * frequency_norm + 0.35 * recency_norm) * 100, 2)
  end

  # --- File size helpers ---

  @doc false
  @spec read_all_file_sizes({:ok, String.t()} | :skip) :: %{String.t() => {integer(), integer()}}
  def read_all_file_sizes({:ok, repo_path}) do
    size_map = parse_ls_tree(repo_path)

    Map.new(size_map, fn {path, size_bytes} ->
      loc =
        if binary_file?(path) or size_bytes > 1_048_576 do
          nil
        else
          read_loc(repo_path, path)
        end

      {path, {size_bytes, loc}}
    end)
  end

  def read_all_file_sizes(:skip), do: %{}

  defp parse_ls_tree(repo_path) do
    case System.cmd("git", ["-C", repo_path, "ls-tree", "-r", "-l", "HEAD"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&parse_ls_tree_line/1)
        |> Map.new()

      _ ->
        %{}
    end
  end

  # Format: <mode> <type> <hash> <size>\t<path>
  defp parse_ls_tree_line(line) do
    case Regex.run(~r/^\S+\s+\S+\s+\S+\s+(\d+)\t(.+)$/, line) do
      [_, size_str, path] -> [{path, String.to_integer(size_str)}]
      _ -> []
    end
  end

  defp read_file_metrics({:ok, repo_path}, path) do
    case System.cmd("git", ["-C", repo_path, "show", "HEAD:#{path}"], stderr_to_stdout: true) do
      {content, 0} ->
        size = byte_size(content)

        loc =
          content
          |> String.split("\n")
          |> Enum.count(fn line -> String.trim(line) != "" end)

        {size, loc}

      _ ->
        {nil, nil}
    end
  end

  defp read_file_metrics(:skip, _path), do: {nil, nil}

  defp read_loc(repo_path, path) do
    case System.cmd("git", ["-C", repo_path, "show", "HEAD:#{path}"], stderr_to_stdout: true) do
      {content, 0} ->
        content
        |> String.split("\n")
        |> Enum.count(fn line -> String.trim(line) != "" end)

      _ ->
        nil
    end
  end
end
