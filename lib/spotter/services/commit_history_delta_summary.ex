defmodule Spotter.Services.CommitHistoryDeltaSummary do
  @moduledoc """
  Computes product spec and test spec delta summaries for a list of commit rows.

  Returns a map keyed by commit ID with counts of added/changed/removed items
  for both product and test specs. Missing or errored runs produce `nil` for
  that side, keeping the page render fail-safe.
  """

  alias Spotter.ProductSpec
  alias Spotter.ProductSpec.RollingSpecRun
  alias Spotter.TestSpec
  alias Spotter.Transcripts.CommitTestRun

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @max_concurrency 4
  @diff_timeout_ms 10_000

  @type counts :: %{
          added: non_neg_integer(),
          changed: non_neg_integer(),
          removed: non_neg_integer()
        }
  @type summary :: %{product: counts() | nil, tests: counts() | nil}

  @doc """
  Computes delta summaries for the given commit rows.

  ## Parameters
    - `project_id` - UUID string of the project
    - `rows` - List of CommitHistory row maps (must have `.commit.commit_hash` and `.commit.id`)
    - `opts` - Reserved for future use

  ## Returns
    Map of `%{commit_id => %{product: counts | nil, tests: counts | nil}}`
  """
  @spec summaries_for_commits(String.t(), [map()], keyword()) :: %{String.t() => summary()}
  def summaries_for_commits(project_id, rows, opts \\ [])
  def summaries_for_commits(_project_id, [], _opts), do: %{}

  def summaries_for_commits(project_id, rows, _opts) do
    Tracer.with_span "spotter.commit_history.delta_summary" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_count", length(rows))

      commit_hashes = Enum.map(rows, & &1.commit.commit_hash)
      commit_ids = Enum.map(rows, & &1.commit.id)

      spec_runs = load_spec_runs(project_id, commit_hashes)
      test_runs = load_test_runs(project_id, commit_ids)

      eligible_product = eligible_product_commits(rows, spec_runs)
      eligible_test = eligible_test_commits(rows, test_runs)

      Tracer.set_attribute("spotter.product_diff_requests", length(eligible_product))
      Tracer.set_attribute("spotter.test_diff_requests", length(eligible_test))

      product_results = compute_product_diffs(project_id, eligible_product)
      test_results = compute_test_diffs(project_id, eligible_test)

      rows
      |> Map.new(fn row ->
        commit_id = row.commit.id

        {commit_id,
         %{
           product: Map.get(product_results, commit_id),
           tests: Map.get(test_results, commit_id)
         }}
      end)
    end
  end

  defp load_spec_runs(_project_id, []), do: %{}

  defp load_spec_runs(project_id, commit_hashes) do
    RollingSpecRun
    |> Ash.Query.filter(project_id == ^project_id and commit_hash in ^commit_hashes)
    |> Ash.read!()
    |> Map.new(&{&1.commit_hash, &1})
  end

  defp load_test_runs(_project_id, []), do: %{}

  defp load_test_runs(project_id, commit_ids) do
    CommitTestRun
    |> Ash.Query.filter(project_id == ^project_id and commit_id in ^commit_ids)
    |> Ash.read!()
    |> Map.new(&{&1.commit_id, &1})
  end

  defp eligible_product_commits(rows, spec_runs) do
    Enum.filter(rows, fn row ->
      case Map.get(spec_runs, row.commit.commit_hash) do
        %{status: :ok} -> true
        _ -> false
      end
    end)
  end

  defp eligible_test_commits(rows, test_runs) do
    Enum.filter(rows, fn row ->
      case Map.get(test_runs, row.commit.id) do
        %{status: :completed} -> true
        _ -> false
      end
    end)
  end

  defp compute_product_diffs(_project_id, []), do: %{}

  defp compute_product_diffs(project_id, eligible_rows) do
    eligible_rows
    |> Task.async_stream(
      fn row ->
        {row.commit.id, safe_product_diff(project_id, row.commit.commit_hash)}
      end,
      max_concurrency: @max_concurrency,
      timeout: @diff_timeout_ms,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.reduce(%{}, fn
      {:ok, {commit_id, counts}}, acc -> Map.put(acc, commit_id, counts)
      {:exit, _reason}, acc -> acc
    end)
  end

  defp compute_test_diffs(_project_id, []), do: %{}

  defp compute_test_diffs(project_id, eligible_rows) do
    eligible_rows
    |> Task.async_stream(
      fn row ->
        {row.commit.id, safe_test_diff(project_id, row.commit.commit_hash)}
      end,
      max_concurrency: @max_concurrency,
      timeout: @diff_timeout_ms,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.reduce(%{}, fn
      {:ok, {commit_id, counts}}, acc -> Map.put(acc, commit_id, counts)
      {:exit, _reason}, acc -> acc
    end)
  end

  defp safe_product_diff(project_id, commit_hash) do
    case ProductSpec.diff_for_commit(project_id, commit_hash) do
      {:ok, diff} -> extract_counts(diff)
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp safe_test_diff(project_id, commit_hash) do
    case TestSpec.diff_for_commit(project_id, commit_hash) do
      {:ok, diff} -> extract_counts(diff)
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp extract_counts(%{added: added, changed: changed, removed: removed}) do
    %{
      added: length(added),
      changed: length(changed),
      removed: length(removed)
    }
  end
end
