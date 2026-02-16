defmodule Spotter.TestSpec do
  @moduledoc """
  Public read API for the versioned test specification stored in Dolt.
  """

  alias Ecto.Adapters.SQL
  alias Spotter.Agents.TestTools
  alias Spotter.TestSpec.{Repo, SpecDiff}
  alias Spotter.Transcripts.CommitTestRun

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @doc "Returns true when the Dolt-backed TestSpec.Repo is running."
  @spec dolt_available?() :: boolean()
  def dolt_available?, do: Process.whereis(Repo) != nil

  @doc """
  Returns the full test tree at a specific Dolt commit hash using time-travel queries.

  Returns `{:ok, [file_node]}` where each file_node has `:relative_path` and `:tests`.
  """
  @spec tree_at(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def tree_at(project_id, dolt_commit_hash) do
    Tracer.with_span "spotter.test_spec.tree_at" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.dolt_commit_hash", dolt_commit_hash)

      case query_tests_at(project_id, dolt_commit_hash) do
        {:ok, rows} ->
          {:ok, build_file_tree(rows)}

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          {:error, reason}
      end
    end
  end

  @doc """
  Resolves the effective test tree for a Git commit.

  If the commit's test run has no Dolt changes (dolt_commit_hash is nil),
  falls back to the previous run's snapshot.
  """
  @spec tree_for_commit(String.t(), String.t()) ::
          {:ok, %{tree: [map()], effective_dolt_commit_hash: String.t() | nil}}
          | {:error, :no_test_run | term()}
  def tree_for_commit(project_id, git_commit_hash) do
    Tracer.with_span "spotter.test_spec.tree_for_commit" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_hash", git_commit_hash)

      case load_test_run(project_id, git_commit_hash) do
        nil ->
          Tracer.set_status(:error, "no_test_run")
          {:error, :no_test_run}

        run ->
          effective_hash = run.dolt_commit_hash || find_previous_dolt_hash(project_id, run)
          Tracer.set_attribute("spotter.effective_dolt_hash", effective_hash || "none")
          resolve_tree(project_id, effective_hash)
      end
    end
  end

  @doc """
  Computes a semantic test diff for a Git commit vs its previous test state.
  """
  @spec diff_for_commit(String.t(), String.t()) ::
          {:ok, map()} | {:error, :no_test_run | term()}
  def diff_for_commit(project_id, git_commit_hash) do
    Tracer.with_span "spotter.test_spec.diff_for_commit" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_hash", git_commit_hash)

      case load_test_run(project_id, git_commit_hash) do
        nil ->
          Tracer.set_status(:error, "no_test_run")
          {:error, :no_test_run}

        %{dolt_commit_hash: nil} ->
          {:ok, %{kind: :no_changes, added: [], removed: [], changed: []}}

        run ->
          base_hash = find_previous_dolt_hash(project_id, run)
          compute_diff(project_id, base_hash, run.dolt_commit_hash)
      end
    end
  end

  # -- Tree building --

  defp build_file_tree(rows) do
    rows
    |> Enum.group_by(& &1.relative_path)
    |> Enum.sort_by(fn {path, _} -> path end)
    |> Enum.map(fn {path, tests} ->
      %{
        relative_path: path,
        tests: Enum.sort_by(tests, &{&1.describe_path, &1.test_name})
      }
    end)
  end

  # -- Dolt time-travel queries --

  defp query_tests_at(project_id, dolt_commit_hash) do
    sql = """
    SELECT id, project_id, test_key, relative_path, framework,
           describe_path_json, test_name, line_start, line_end,
           given_json, when_json, then_json, confidence,
           metadata_json, source_commit_hash, updated_by_git_commit
    FROM `test_specs` AS OF '#{sanitize_hash(dolt_commit_hash)}'
    WHERE project_id = ?
    ORDER BY relative_path, describe_path_json, test_name
    """

    case SQL.query(Repo, sql, [project_id]) do
      {:ok, result} ->
        rows =
          result
          |> rows_to_maps()
          |> Enum.map(&TestTools.deserialize_row/1)

        {:ok, rows}

      {:error, error} ->
        {:error, {:dolt_query_failed, inspect(error)}}
    end
  rescue
    e -> {:error, {:dolt_query_failed, Exception.message(e)}}
  end

  defp sanitize_hash(hash) do
    if is_binary(hash) and String.match?(hash, ~r/\A[0-9a-zA-Z]{6,64}\z/) do
      hash
    else
      raise "invalid Dolt commit hash: #{inspect(hash)}"
    end
  end

  defp rows_to_maps(%{columns: columns, rows: rows}) do
    Enum.map(rows, fn row ->
      columns |> Enum.zip(row) |> Map.new()
    end)
  end

  # -- Tree resolution --

  defp resolve_tree(_project_id, nil),
    do: {:ok, %{tree: [], effective_dolt_commit_hash: nil}}

  defp resolve_tree(project_id, effective_hash) do
    case tree_at(project_id, effective_hash) do
      {:ok, tree} -> {:ok, %{tree: tree, effective_dolt_commit_hash: effective_hash}}
      {:error, reason} -> {:error, reason}
    end
  end

  # -- Diff computation --

  defp compute_diff(project_id, base_hash, target_hash) do
    base_result = if base_hash, do: query_tests_at(project_id, base_hash), else: {:ok, []}

    case {base_result, query_tests_at(project_id, target_hash)} do
      {{:ok, from_tests}, {:ok, to_tests}} ->
        {:ok, SpecDiff.diff(from_tests, to_tests)}

      {{:error, reason}, _} ->
        {:error, reason}

      {_, {:error, reason}} ->
        {:error, reason}
    end
  end

  # -- Run resolution helpers --

  defp load_test_run(project_id, git_commit_hash) do
    alias Spotter.Transcripts.Commit

    case Commit
         |> Ash.Query.filter(commit_hash == ^git_commit_hash)
         |> Ash.read_one!() do
      nil ->
        nil

      commit ->
        CommitTestRun
        |> Ash.Query.filter(project_id == ^project_id and commit_id == ^commit.id)
        |> Ash.read_one!()
    end
  end

  defp find_previous_dolt_hash(project_id, current_run) do
    runs =
      CommitTestRun
      |> Ash.Query.filter(
        project_id == ^project_id and
          not is_nil(dolt_commit_hash) and
          id != ^current_run.id
      )
      |> Ash.read!()

    commit_ids = Enum.map(runs, & &1.commit_id)
    commits_by_id = load_commits_by_id(commit_ids)

    current_commit = Map.get(commits_by_id, current_run.commit_id)
    current_date = commit_sort_date(current_commit) || current_run.started_at

    runs
    |> Enum.map(fn run ->
      commit = Map.get(commits_by_id, run.commit_id)
      sort_date = commit_sort_date(commit) || run.started_at
      {sort_date, run}
    end)
    |> Enum.filter(fn {date, _run} ->
      date != nil and current_date != nil and DateTime.compare(date, current_date) == :lt
    end)
    |> Enum.sort_by(fn {date, _run} -> date end, {:desc, DateTime})
    |> List.first()
    |> case do
      {_date, run} -> run.dolt_commit_hash
      nil -> nil
    end
  end

  defp load_commits_by_id([]), do: %{}

  defp load_commits_by_id(ids) do
    alias Spotter.Transcripts.Commit

    Commit
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read!()
    |> Map.new(&{&1.id, &1})
  end

  defp commit_sort_date(nil), do: nil
  defp commit_sort_date(commit), do: commit.committed_at || commit.inserted_at
end
