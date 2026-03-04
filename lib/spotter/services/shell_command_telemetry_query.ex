defmodule Spotter.Services.ShellCommandTelemetryQuery do
  @moduledoc false

  alias Spotter.Transcripts.ShellCommandEvent

  require Ash.Query

  @window_seconds %{
    last_24h: 86_400,
    last_7d: 604_800,
    last_30d: 2_592_000
  }

  @doc """
  Returns per-command telemetry statistics for a single project.
  """
  def snapshot(project_id, opts \\ []) do
    project_id
    |> load_events(opts)
    |> do_fold_runs()
    |> aggregate_by(& &1.command)
    |> sort_commands()
  end

  @doc """
  Returns per-command telemetry statistics across all projects.
  Each result includes the `project_id` it originated from.
  """
  def snapshot_all_projects(opts \\ []) do
    nil
    |> load_events(opts)
    |> do_fold_runs()
    |> aggregate_by(fn r -> {r.project_id, r.command} end, &unwrap_project_key/2)
    |> sort_commands()
  end

  @doc """
  Loads events for a project and folds them into runs.
  """
  def fold_runs(project_id, opts \\ []) do
    project_id
    |> load_events(Keyword.put(opts, :window, :all))
    |> do_fold_runs()
  end

  @doc """
  Computes percentile statistics from a list of durations.
  """
  def compute_percentiles(durations) do
    sorted = Enum.sort(durations)

    %{
      p50: percentile(sorted, 50),
      p90: percentile(sorted, 90),
      p95: percentile(sorted, 95),
      median_ms: median(sorted)
    }
  end

  # --- Data Loading ---

  defp load_events(project_id, opts) do
    window = Keyword.get(opts, :window, :last_7d)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    ShellCommandEvent
    |> maybe_filter_project(project_id)
    |> maybe_filter_window(window, now)
    |> Ash.Query.sort(captured_at: :asc, inserted_at: :asc, id: :asc)
    |> Ash.read!()
  end

  defp maybe_filter_project(query, nil), do: query

  defp maybe_filter_project(query, project_id) do
    Ash.Query.filter(query, project_id == ^project_id)
  end

  defp maybe_filter_window(query, :all, _now), do: query

  defp maybe_filter_window(query, window, now) do
    seconds = Map.fetch!(@window_seconds, window)
    cutoff = DateTime.add(now, -seconds, :second)
    Ash.Query.filter(query, captured_at >= ^cutoff)
  end

  # --- Run Folding ---

  defp do_fold_runs(events) do
    now = DateTime.utc_now()

    events
    |> Enum.reduce(%{}, &accumulate_event/2)
    |> Enum.map(fn {key, raw} -> build_run(key, raw, now) end)
  end

  defp accumulate_event(%{phase: :start} = event, acc) do
    key = {event.tool_use_id, event.command, event.command_path}

    Map.update(acc, key, %{start: event, finishes: []}, fn run ->
      %{run | start: event}
    end)
  end

  defp accumulate_event(%{phase: :finish} = event, acc) do
    key = {event.tool_use_id, event.command, event.command_path}

    Map.update(acc, key, %{start: nil, finishes: [event]}, fn run ->
      %{run | finishes: [event | run.finishes]}
    end)
  end

  defp accumulate_event(_event, acc), do: acc

  defp build_run({tool_use_id, command, command_path}, %{start: start, finishes: finishes}, now) do
    finish = finishes |> Enum.sort_by(& &1.captured_at, DateTime) |> List.last()
    project_id = (start || finish).project_id

    base = %{
      tool_use_id: tool_use_id,
      command: command,
      command_path: command_path,
      project_id: project_id,
      started_at: start && start.captured_at,
      finished_at: finish && finish.captured_at
    }

    cond do
      is_nil(start) ->
        Map.merge(base, %{status: :orphan, duration_ms: nil, elapsed_ms: nil})

      is_nil(finish) ->
        elapsed = max(DateTime.diff(now, start.captured_at, :millisecond), 0)
        Map.merge(base, %{status: :ongoing, duration_ms: nil, elapsed_ms: elapsed})

      true ->
        ms = max(DateTime.diff(finish.captured_at, start.captured_at, :millisecond), 0)
        status = if finish.finish_status == :error, do: :error, else: :completed
        Map.merge(base, %{status: status, duration_ms: ms, elapsed_ms: nil})
    end
  end

  # --- Aggregation ---

  defp aggregate_by(runs, group_fn, key_transform \\ &default_key_transform/2) do
    runs
    |> Enum.group_by(group_fn)
    |> Enum.map(fn {key, group} ->
      command = extract_command(key)
      key_transform.(compute_stats(command, group), key)
    end)
  end

  defp default_key_transform(stats, _key), do: stats

  defp unwrap_project_key(stats, {project_id, _command}) do
    Map.put(stats, :project_id, project_id)
  end

  defp extract_command({_project_id, command}), do: command
  defp extract_command(command) when is_binary(command), do: command

  defp compute_stats(command, runs) do
    {completed_count, ongoing_count, error_count, durations, last_seen_at} =
      Enum.reduce(runs, {0, 0, 0, [], nil}, fn run, {comp, ong, err, durs, latest} ->
        ts = run.finished_at || run.started_at
        latest = max_datetime(latest, ts)

        case run.status do
          :completed ->
            {comp + 1, ong, err, maybe_add_duration(durs, run.duration_ms), latest}

          :ongoing ->
            {comp, ong + 1, err, durs, latest}

          :error ->
            {comp, ong, err + 1, maybe_add_duration(durs, run.duration_ms), latest}

          _other ->
            {comp, ong, err, durs, latest}
        end
      end)

    count = length(runs)
    finished_count = completed_count + error_count
    error_rate = if finished_count > 0, do: error_count / finished_count, else: 0.0
    sorted_durations = Enum.sort(durations)
    pcts = percentile_map(sorted_durations)

    %{
      command: command,
      count: count,
      completed_count: completed_count,
      ongoing_count: ongoing_count,
      error_count: error_count,
      error_rate: error_rate,
      mean_ms: mean(sorted_durations),
      median_ms: pcts.median_ms,
      p50_ms: pcts.p50,
      p90_ms: pcts.p90,
      p95_ms: pcts.p95,
      last_seen_at: last_seen_at
    }
  end

  defp maybe_add_duration(durs, nil), do: durs
  defp maybe_add_duration(durs, ms), do: [ms | durs]

  defp max_datetime(nil, ts), do: ts
  defp max_datetime(a, nil), do: a

  defp max_datetime(a, b) do
    if DateTime.compare(a, b) == :lt, do: b, else: a
  end

  # Accepts pre-sorted durations, skips redundant sort.
  defp percentile_map(sorted) do
    %{
      p50: percentile(sorted, 50),
      p90: percentile(sorted, 90),
      p95: percentile(sorted, 95),
      median_ms: median(sorted)
    }
  end

  # --- Math ---

  defp mean([]), do: nil
  defp mean(values), do: Enum.sum(values) / length(values)

  @doc false
  def median([]), do: nil

  @doc false
  def median(sorted) do
    n = length(sorted)

    if rem(n, 2) == 1 do
      Enum.at(sorted, div(n, 2)) * 1.0
    else
      mid = div(n, 2)
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end

  defp percentile([], _p), do: nil

  defp percentile(sorted, p) when p >= 0 and p <= 100 do
    n = length(sorted)
    index = max(ceil(p / 100 * n) - 1, 0) |> min(n - 1)
    Enum.at(sorted, index)
  end

  # --- Sorting ---

  defp sort_commands(stats) do
    Enum.sort_by(stats, fn s -> {-(s.median_ms || 0), -(s.p95_ms || 0), -s.count} end)
  end
end
