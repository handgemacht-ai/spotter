defmodule Spotter.Transcripts.Jobs.AnalyzeCommitTests do
  @moduledoc "Oban worker that extracts/syncs test cases for a commit's changed files."

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [keys: [:project_id, :commit_hash], period: 3600]

  require Ash.Query
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Services.GitRunner
  alias Spotter.Transcripts.{Commit, CommitTestRun, Session, TestCase}

  @test_path_patterns [
    ~r{(^|/)test/},
    ~r{(^|/)spec/},
    ~r{__tests__},
    ~r{_test\.exs$},
    ~r{\.test\.[tj]sx?$},
    ~r{\.spec\.[tj]sx?$}
  ]

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "commit_hash" => commit_hash}}) do
    Tracer.with_span "spotter.commit_tests.analyze.perform" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_hash", commit_hash)

      case {load_commit(commit_hash), resolve_repo_path(project_id)} do
        {{:ok, commit}, {:ok, repo_path}} ->
          run_analysis(project_id, commit, repo_path)

        {{:error, reason}, _} ->
          Logger.warning("AnalyzeCommitTests: commit not found: #{inspect(reason)}")
          :ok

        {_, :no_cwd} ->
          mark_commit_error(commit_hash, "no accessible repo path")
          :ok
      end
    end
  end

  # -- Loading / resolution --

  defp load_commit(commit_hash) do
    case Commit |> Ash.Query.filter(commit_hash == ^commit_hash) |> Ash.read_one() do
      {:ok, nil} -> {:error, :not_found}
      {:ok, commit} -> {:ok, commit}
      {:error, _} = err -> err
    end
  end

  defp resolve_repo_path(project_id) do
    case Session
         |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
         |> Ash.Query.sort(started_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read!() do
      [session] -> if File.dir?(session.cwd), do: {:ok, session.cwd}, else: :no_cwd
      [] -> :no_cwd
    end
  end

  # -- Analysis pipeline --

  defp run_analysis(project_id, commit, repo_path) do
    test_run = create_test_run(project_id, commit)
    test_run = Ash.update!(test_run, %{}, action: :mark_running)

    try do
      changes = diff_tree(repo_path, commit.commit_hash)
      {candidates, skipped} = partition_candidates(changes)

      Tracer.set_attribute("spotter.files_total", length(changes))
      Tracer.set_attribute("spotter.files_candidate", length(candidates))

      {results, direct_deletes} = process_files(project_id, commit, repo_path, candidates)

      totals = aggregate_tool_counts(results, direct_deletes)

      Tracer.set_attribute("spotter.tool.created", totals[:created])
      Tracer.set_attribute("spotter.tool.updated", totals[:updated])
      Tracer.set_attribute("spotter.tool.deleted", totals[:deleted])

      model_used = results |> List.first() |> then(fn r -> r && r[:model_used] end)

      Ash.update!(
        test_run,
        %{
          model_used: model_used,
          input_stats: %{
            files_total: length(changes),
            files_candidate: length(candidates),
            files_skipped: skipped
          },
          output_stats: totals
        },
        action: :complete
      )

      mark_commit_success(commit, totals, skipped)
    rescue
      e ->
        reason = Exception.message(e)
        Logger.warning("AnalyzeCommitTests: failed: #{reason}")
        Tracer.set_status(:error, reason)
        Ash.update!(test_run, %{error: String.slice(reason, 0, 500)}, action: :fail)
        mark_commit_error(commit, reason)
        :ok
    end
  end

  defp create_test_run(project_id, commit) do
    Ash.create!(CommitTestRun, %{project_id: project_id, commit_id: commit.id})
  end

  # -- Git operations --

  defp diff_tree(repo_path, commit_hash) do
    Tracer.with_span "spotter.commit_tests.git.diff_tree" do
      case GitRunner.run(["diff-tree", "--name-status", "-r", commit_hash],
             cd: repo_path,
             timeout_ms: 10_000
           ) do
        {:ok, output} ->
          parse_diff_tree(output)

        {:error, err} ->
          Logger.warning("AnalyzeCommitTests: diff-tree failed: #{inspect(err.kind)}")
          []
      end
    end
  end

  @doc false
  def parse_diff_tree(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t") do
        ["A", path] ->
          [%{status: :added, path: path}]

        ["M", path] ->
          [%{status: :modified, path: path}]

        ["D", path] ->
          [%{status: :deleted, path: path}]

        [<<"R", _rest::binary>>, old_path, new_path] ->
          [%{status: :renamed, old_path: old_path, path: new_path}]

        _ ->
          []
      end
    end)
  end

  # -- Filtering --

  defp partition_candidates(changes) do
    {candidates, skipped} =
      Enum.split_with(changes, fn change ->
        test_candidate?(change.path) or
          (change[:old_path] && test_candidate?(change[:old_path]))
      end)

    {candidates, length(skipped)}
  end

  @doc false
  def test_candidate?(path) do
    Enum.any?(@test_path_patterns, &Regex.match?(&1, path))
  end

  # -- Per-file processing --

  defp process_files(project_id, commit, repo_path, candidates) do
    results_and_deletes =
      Enum.map(candidates, fn change ->
        Tracer.with_span "spotter.commit_tests.file.process" do
          Tracer.set_attribute("spotter.relative_path", change.path)
          Tracer.set_attribute("spotter.change_status", Atom.to_string(change.status))
          process_file(project_id, commit, repo_path, change)
        end
      end)

    {results, direct_deletes} =
      Enum.reduce(results_and_deletes, {[], 0}, fn
        {:agent_result, result}, {rs, dd} -> {[result | rs], dd}
        {:direct_delete, count}, {rs, dd} -> {rs, dd + count}
        :skip, {rs, dd} -> {rs, dd}
      end)

    {Enum.reverse(results), direct_deletes}
  end

  defp process_file(project_id, _commit, _repo_path, %{status: :deleted, path: path}) do
    count = delete_tests_for_path(project_id, path)
    {:direct_delete, count}
  end

  defp process_file(project_id, commit, repo_path, change) do
    path = change.path

    case git_show_file(repo_path, commit.commit_hash, path) do
      {:ok, content} ->
        diff = git_show_diff(repo_path, commit.commit_hash, path)

        case agent_module().run_file(%{
               project_id: project_id,
               commit_hash: commit.commit_hash,
               relative_path: path,
               file_content: content,
               file_diff: diff
             }) do
          {:ok, result} ->
            {:agent_result, result}

          {:error, reason} ->
            Logger.warning("AnalyzeCommitTests: agent error for #{path}: #{inspect(reason)}")
            :skip
        end

      :file_missing ->
        count = delete_tests_for_path(project_id, path)
        {:direct_delete, count}
    end
  end

  defp git_show_file(repo_path, commit_hash, path) do
    case GitRunner.run(["show", "#{commit_hash}:#{path}"],
           cd: repo_path,
           timeout_ms: 10_000
         ) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> :file_missing
    end
  end

  defp git_show_diff(repo_path, commit_hash, path) do
    case GitRunner.run(["show", "--format=", "--unified=3", commit_hash, "--", path],
           cd: repo_path,
           timeout_ms: 10_000
         ) do
      {:ok, diff} -> diff
      {:error, _} -> ""
    end
  end

  defp delete_tests_for_path(project_id, path) do
    tests =
      TestCase
      |> Ash.Query.filter(project_id == ^project_id and relative_path == ^path)
      |> Ash.read!()

    Enum.each(tests, &Ash.destroy!/1)
    length(tests)
  end

  # -- Aggregation --

  defp aggregate_tool_counts(results, direct_deletes) do
    base = %{created: 0, updated: 0, deleted: direct_deletes}

    Enum.reduce(results, base, fn result, acc ->
      counts = result[:tool_counts] || %{}

      %{
        created: acc.created + Map.get(counts, "mcp__spotter-tests__create_test", 0),
        updated: acc.updated + Map.get(counts, "mcp__spotter-tests__update_test", 0),
        deleted: acc.deleted + Map.get(counts, "mcp__spotter-tests__delete_test", 0)
      }
    end)
  end

  # -- Commit status --

  defp mark_commit_success(commit, totals, skipped) do
    Ash.update(commit, %{
      tests_status: :ok,
      tests_analyzed_at: DateTime.utc_now(),
      tests_error: nil,
      tests_metadata: %{
        tool_counts: totals,
        skipped_files: skipped
      }
    })

    :ok
  end

  defp mark_commit_error(commit_or_hash, error_msg) do
    commit =
      case commit_or_hash do
        %Commit{} = c ->
          c

        hash when is_binary(hash) ->
          case load_commit(hash) do
            {:ok, c} -> c
            _ -> nil
          end
      end

    if commit do
      Ash.update(commit, %{
        tests_status: :error,
        tests_error: String.slice(error_msg, 0, 500)
      })
    end
  end

  defp agent_module do
    Application.get_env(:spotter, :commit_test_agent_module, Spotter.Services.CommitTestAgent)
  end
end
