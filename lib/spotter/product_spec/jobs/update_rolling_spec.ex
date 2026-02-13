defmodule Spotter.ProductSpec.Jobs.UpdateRollingSpec do
  @moduledoc """
  Oban worker that updates the Dolt-backed product spec for a single Git commit.

  For a given (project_id, commit_hash), runs at most once successfully and
  creates at most one Dolt commit.
  """

  use Oban.Worker,
    queue: :spec,
    max_attempts: 5,
    unique: [keys: [:project_id, :commit_hash], period: 86_400]

  require Ash.Query
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.ProductSpec.Agent.Runner
  alias Spotter.ProductSpec.DoltVersioning
  alias Spotter.ProductSpec.RollingSpecRun
  alias Spotter.Services.CommitContextBuilder
  alias Spotter.Services.CommitDiffExtractor
  alias Spotter.Services.CommitHotspotFilters
  alias Spotter.Services.CommitPatchExtractor
  alias Spotter.Transcripts.{Commit, Session, SessionCommitLink}

  @max_error_chars 8_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "commit_hash" => commit_hash} = args}) do
    Tracer.with_span "spotter.product_spec.update_rolling_spec.perform" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_hash", commit_hash)

      if args["otel_trace_id"] do
        Tracer.set_attribute("spotter.parent_trace_id", args["otel_trace_id"])
      end

      do_perform(args)
    end
  end

  defp do_perform(%{"project_id" => project_id, "commit_hash" => commit_hash} = args) do
    git_cwd = args["git_cwd"]
    git_branch = args["git_branch"]

    run = ensure_run(project_id, commit_hash, git_cwd, git_branch)

    if run.status == :ok do
      Logger.info("UpdateRollingSpec: already completed for #{commit_hash}, skipping")
      Ash.update!(run, %{}, action: :mark_skipped)
      :ok
    else
      run = Ash.update!(run, %{}, action: :mark_running)
      execute_spec_update(run, project_id, commit_hash, git_cwd)
    end
  end

  defp ensure_run(project_id, commit_hash, git_cwd, git_branch) do
    case RollingSpecRun
         |> Ash.Query.filter(project_id == ^project_id and commit_hash == ^commit_hash)
         |> Ash.read_one() do
      {:ok, %RollingSpecRun{} = run} ->
        run

      _ ->
        Ash.create!(RollingSpecRun, %{
          project_id: project_id,
          commit_hash: commit_hash,
          status: :pending,
          git_cwd: git_cwd,
          git_branch: git_branch
        })
    end
  end

  defp execute_spec_update(run, project_id, commit_hash, git_cwd) do
    with {:ok, agent_input} <- build_agent_input(project_id, commit_hash, git_cwd),
         {:ok, _output} <- invoke_agent(agent_input),
         {:ok, dolt_hash} <-
           DoltVersioning.commit_spec_changes(commit_hash, agent_input.commit_subject) do
      Ash.update!(run, %{dolt_commit_hash: dolt_hash}, action: :mark_ok)
      :ok
    else
      {:error, reason} ->
        error_msg = inspect(reason) |> String.slice(0, @max_error_chars)
        Logger.warning("UpdateRollingSpec: failed for #{commit_hash}: #{error_msg}")
        Tracer.set_status(:error, error_msg)
        Ash.update!(run, %{error: error_msg}, action: :mark_error)
        :ok
    end
  end

  defp build_agent_input(project_id, commit_hash, git_cwd) do
    Tracer.with_span "spotter.product_spec.build_agent_input" do
      {subject, body} = load_commit_message(commit_hash, git_cwd)

      case build_diff_context(git_cwd, commit_hash) do
        {:ok, diff_context} ->
          summaries = load_linked_session_summaries(commit_hash)

          {:ok,
           %{
             project_id: project_id,
             commit_hash: commit_hash,
             commit_subject: subject,
             commit_body: body,
             diff_stats: diff_context.diff_stats,
             patch_files: diff_context.patch_files,
             context_windows: diff_context.context_windows,
             linked_session_summaries: summaries
           }}

        {:error, _} = err ->
          err
      end
    end
  end

  defp load_commit_message(commit_hash, git_cwd) do
    case Commit |> Ash.Query.filter(commit_hash == ^commit_hash) |> Ash.read_one() do
      {:ok, %Commit{} = commit} ->
        {commit.subject || "", commit.body || ""}

      _ ->
        load_commit_message_from_git(commit_hash, git_cwd)
    end
  end

  defp load_commit_message_from_git(commit_hash, git_cwd) when is_binary(git_cwd) do
    case System.cmd("git", ["show", "--no-patch", "--format=%s%n%b", commit_hash],
           cd: git_cwd,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        [subject | rest] = String.split(output, "\n", parts: 2)
        body = List.first(rest) || ""
        {String.trim(subject), String.trim(body)}

      _ ->
        {"", ""}
    end
  end

  defp load_commit_message_from_git(_, _), do: {"", ""}

  defp build_diff_context(git_cwd, commit_hash) when is_binary(git_cwd) do
    with {:ok, diff_stats} <- CommitDiffExtractor.diff_stats(git_cwd, commit_hash),
         {:ok, patch_files} <- CommitPatchExtractor.patch_hunks(git_cwd, commit_hash) do
      eligible = filter_eligible(patch_files, diff_stats.binary_files)
      context_windows = build_context_windows(git_cwd, eligible)

      {:ok,
       %{
         diff_stats: diff_stats,
         patch_files: eligible,
         context_windows: context_windows
       }}
    end
  end

  defp build_diff_context(_, _),
    do: {:ok, %{diff_stats: %{}, patch_files: [], context_windows: %{}}}

  defp filter_eligible(patch_files, binary_files) do
    binary_set = MapSet.new(binary_files)

    Enum.filter(patch_files, fn file ->
      not MapSet.member?(binary_set, file.path) and
        CommitHotspotFilters.eligible_path?(file.path)
    end)
  end

  defp build_context_windows(repo_path, patch_files) do
    Map.new(patch_files, fn file ->
      ranges =
        Enum.map(file.hunks, fn h ->
          {h.new_start, h.new_start + max(h.new_len - 1, 0)}
        end)

      content = read_file_content(repo_path, file.path)
      windows = CommitContextBuilder.build_windows(content, ranges)
      {file.path, windows}
    end)
  end

  defp read_file_content(repo_path, relative_path) do
    Path.join(repo_path, relative_path)
    |> File.read()
    |> case do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  defp invoke_agent(input), do: Runner.run(input)

  @doc """
  Loads distilled session summaries linked to the given commit hash.

  Returns a list of summary maps for sessions with `:completed` or `:error`
  distillation status.
  """
  def load_linked_session_summaries(commit_hash) do
    case Commit |> Ash.Query.filter(commit_hash == ^commit_hash) |> Ash.read_one() do
      {:ok, %Commit{id: commit_id}} ->
        SessionCommitLink
        |> Ash.Query.filter(commit_id == ^commit_id)
        |> Ash.Query.load(:session)
        |> Ash.read!()
        |> Enum.map(& &1.session)
        |> Enum.filter(&(&1.distilled_status in [:completed, :error]))
        |> Enum.map(&format_session_summary/1)

      _ ->
        []
    end
  end

  defp format_session_summary(session) do
    %{
      session_id: session.session_id,
      slug: session.slug,
      hook_ended_at: session.hook_ended_at && DateTime.to_iso8601(session.hook_ended_at),
      distilled_status: session.distilled_status,
      distilled_summary: session.distilled_summary,
      distilled_at: session.distilled_at && DateTime.to_iso8601(session.distilled_at)
    }
  end

  @doc """
  Resolves a git repo path for a project from the most recent session with a cwd.
  """
  @spec resolve_repo_path(String.t()) :: {:ok, String.t()} | :no_cwd
  def resolve_repo_path(project_id) do
    case Session
         |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
         |> Ash.Query.sort(started_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read!() do
      [session] -> if File.dir?(session.cwd), do: {:ok, session.cwd}, else: :no_cwd
      [] -> :no_cwd
    end
  end
end
