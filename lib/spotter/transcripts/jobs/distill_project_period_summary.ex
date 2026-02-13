defmodule Spotter.Transcripts.Jobs.DistillProjectPeriodSummary do
  @moduledoc """
  Oban worker that computes a period summary for a project date bucket.

  Only includes sessions whose commits are reachable from the default branch.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id, :bucket_kind, :bucket_start_date], period: 3_600]

  alias Spotter.Services.{
    GitLogReader,
    ProjectPeriodRollupPack,
    ProjectRollupBucket,
    ProjectRollupDistiller
  }

  alias Spotter.Transcripts.{Commit, Project, ProjectPeriodSummary, Session, SessionCommitLink}
  alias Spotter.Transcripts.Jobs.DistillProjectRollingSummary

  require Ash.Query
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    project_id = args["project_id"]
    bucket_kind = String.to_existing_atom(args["bucket_kind"])
    bucket_start_date = Date.from_iso8601!(args["bucket_start_date"])

    Tracer.with_span "spotter.jobs.distill_project_period_summary" do
      Tracer.set_attribute("spotter.project_id", project_id)
      do_perform(project_id, bucket_kind, bucket_start_date)
    end
  end

  defp do_perform(project_id, bucket_kind, bucket_start_date) do
    project = Ash.get!(Project, project_id)
    tz = project.timezone || "Etc/UTC"

    case resolve_repo_and_branch(project) do
      {:ok, repo_path, default_branch} ->
        run_distillation(project, tz, bucket_kind, bucket_start_date, repo_path, default_branch)

      {:error, reason} ->
        save_empty(
          project,
          tz,
          bucket_kind,
          bucket_start_date,
          "unknown",
          "No repo path: #{reason}"
        )
    end
  end

  defp run_distillation(project, tz, bucket_kind, bucket_start_date, repo_path, default_branch) do
    {start_utc, end_utc} =
      ProjectRollupBucket.bucket_range_utc(bucket_start_date, tz, bucket_kind)

    branch_ref = resolve_branch_ref(repo_path, default_branch)

    candidates = load_candidate_sessions(project.id, start_utc, end_utc)
    qualifying = filter_by_ancestor(candidates, repo_path, branch_ref)

    if qualifying == [] do
      save_empty(
        project,
        tz,
        bucket_kind,
        bucket_start_date,
        default_branch,
        "No qualifying sessions."
      )
    else
      distill_and_save(project, tz, bucket_kind, bucket_start_date, default_branch, qualifying)
    end
  end

  defp distill_and_save(project, tz, bucket_kind, bucket_start_date, default_branch, sessions) do
    pack =
      ProjectPeriodRollupPack.build(project, sessions,
        bucket_kind: bucket_kind,
        bucket_start_date: bucket_start_date,
        default_branch: default_branch
      )

    case ProjectRollupDistiller.distill(pack) do
      {:ok, result} ->
        Ash.create!(ProjectPeriodSummary, %{
          project_id: project.id,
          bucket_kind: bucket_kind,
          bucket_start_date: bucket_start_date,
          timezone: tz,
          default_branch: default_branch,
          included_session_ids: Enum.map(sessions, &to_string(&1.session_id)),
          included_commit_hashes: sessions |> Enum.flat_map(& &1.commit_hashes) |> Enum.uniq(),
          summary_json: result.summary_json,
          summary_text: result.summary_text,
          model_used: result.model_used,
          computed_at: DateTime.utc_now()
        })

        enqueue_rolling(project.id)
        :ok

      {:error, reason} ->
        Logger.warning("DistillProjectPeriodSummary: distillation failed: #{inspect(reason)}")

        save_empty(
          project,
          tz,
          bucket_kind,
          bucket_start_date,
          default_branch,
          "Distillation failed: #{inspect(reason)}"
        )
    end
  end

  defp save_empty(project, tz, bucket_kind, bucket_start_date, default_branch, text) do
    Ash.create!(ProjectPeriodSummary, %{
      project_id: project.id,
      bucket_kind: bucket_kind,
      bucket_start_date: bucket_start_date,
      timezone: tz,
      default_branch: default_branch,
      included_session_ids: [],
      included_commit_hashes: [],
      summary_text: text,
      computed_at: DateTime.utc_now()
    })

    enqueue_rolling(project.id)
    :ok
  end

  defp load_candidate_sessions(project_id, start_utc, end_utc) do
    sessions =
      Session
      |> Ash.Query.filter(
        project_id == ^project_id and
          distilled_status == :completed and
          hook_ended_at >= ^start_utc and
          hook_ended_at < ^end_utc
      )
      |> Ash.read!()

    Enum.map(sessions, fn session ->
      commit_hashes = load_commit_hashes(session.id)

      %{
        session_id: session.session_id,
        hook_ended_at: session.hook_ended_at,
        distilled_summary: session.distilled_summary,
        commit_hashes: commit_hashes,
        db_id: session.id
      }
    end)
    |> Enum.reject(&(&1.commit_hashes == []))
  end

  defp load_commit_hashes(session_db_id) do
    links =
      SessionCommitLink
      |> Ash.Query.filter(session_id == ^session_db_id)
      |> Ash.read!()

    commit_ids = Enum.map(links, & &1.commit_id)

    if commit_ids == [] do
      []
    else
      Commit
      |> Ash.Query.filter(id in ^commit_ids)
      |> Ash.read!()
      |> Enum.map(& &1.commit_hash)
    end
  end

  defp filter_by_ancestor(sessions, repo_path, branch_ref) do
    {result, _cache} =
      Enum.reduce(sessions, {[], %{}}, fn session, {acc, cache} ->
        {reachable, cache} =
          any_hash_reachable?(session.commit_hashes, repo_path, branch_ref, cache)

        if reachable, do: {[session | acc], cache}, else: {acc, cache}
      end)

    Enum.reverse(result)
  end

  defp any_hash_reachable?([], _repo_path, _branch_ref, cache), do: {false, cache}

  defp any_hash_reachable?([hash | rest], repo_path, branch_ref, cache) do
    {reachable, cache} = check_ancestor(hash, repo_path, branch_ref, cache)
    if reachable, do: {true, cache}, else: any_hash_reachable?(rest, repo_path, branch_ref, cache)
  end

  defp check_ancestor(hash, repo_path, branch_ref, cache) do
    case Map.fetch(cache, hash) do
      {:ok, val} ->
        {val, cache}

      :error ->
        result = ancestor?(repo_path, hash, branch_ref)
        {result, Map.put(cache, hash, result)}
    end
  end

  defp ancestor?(repo_path, commit_hash, branch_ref) do
    case System.cmd(
           "git",
           ["-C", repo_path, "merge-base", "--is-ancestor", commit_hash, branch_ref],
           stderr_to_stdout: true
         ) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp resolve_repo_and_branch(project) do
    case find_repo_path(project.id) do
      nil ->
        {:error, "no session with valid cwd"}

      repo_path ->
        case GitLogReader.resolve_branch(repo_path, nil) do
          {:ok, branch} -> {:ok, repo_path, branch}
          {:error, reason} -> {:error, inspect(reason)}
        end
    end
  end

  defp find_repo_path(project_id) do
    Session
    |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> case do
      [%{cwd: cwd}] when is_binary(cwd) ->
        if File.dir?(cwd), do: cwd, else: nil

      _ ->
        nil
    end
  end

  defp resolve_branch_ref(repo_path, branch) do
    case System.cmd(
           "git",
           ["-C", repo_path, "rev-parse", "--verify", "refs/remotes/origin/#{branch}"],
           stderr_to_stdout: true
         ) do
      {_, 0} -> "refs/remotes/origin/#{branch}"
      _ -> branch
    end
  end

  defp enqueue_rolling(project_id) do
    %{project_id: project_id}
    |> DistillProjectRollingSummary.new()
    |> Oban.insert()
  end
end
