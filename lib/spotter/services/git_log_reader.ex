defmodule Spotter.Services.GitLogReader do
  @moduledoc "Thin wrapper around git CLI to read commit history with changed files."

  require Logger

  @doc """
  Returns a list of maps with :hash, :timestamp, and :files for each commit
  on the given branch within the time window.

  Options:
    - :since - `DateTime.t()` start of window (takes priority over `:since_days`)
    - :until - `DateTime.t()` end of window (only used with `:since`)
    - :since_days - number of days to look back (default 30, used when `:since` not provided)
    - :branch - branch name (default: auto-detect)
    - :filter_spotterignore - when true, exclude paths matching `.spotterignore` rules (default false)
  """
  @spec changed_files_by_commit(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def changed_files_by_commit(repo_path, opts \\ []) do
    time_opts = build_time_opts(opts)
    filter_ignore = Keyword.get(opts, :filter_spotterignore, false)

    with {:ok, branch} <- resolve_branch(repo_path, Keyword.get(opts, :branch)),
         {:ok, commits} <- parse_log(repo_path, branch, time_opts) do
      if filter_ignore do
        {:ok, filter_spotterignore(repo_path, commits)}
      else
        {:ok, commits}
      end
    else
      {:error, reason} ->
        Logger.warning("GitLogReader: could not resolve branch for #{repo_path}: #{reason}")
        {:error, reason}
    end
  end

  @doc "Auto-detect the default branch for a repo."
  @spec resolve_branch(String.t(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def resolve_branch(_repo_path, branch) when is_binary(branch) and branch != "",
    do: {:ok, branch}

  def resolve_branch(repo_path, _) do
    case current_branch(repo_path) do
      {:ok, branch} -> {:ok, branch}
      :no_branch -> detect_fallback_branch(repo_path)
    end
  end

  defp current_branch(repo_path) do
    case System.cmd("git", ["-C", repo_path, "branch", "--show-current"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> then(fn
          "" -> :no_branch
          branch -> {:ok, branch}
        end)

      _ ->
        :no_branch
    end
  end

  defp detect_fallback_branch(repo_path) do
    case System.cmd("git", ["-C", repo_path, "symbolic-ref", "refs/remotes/origin/HEAD"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        {:ok, output |> String.trim() |> String.replace("refs/remotes/origin/", "")}

      _ ->
        detect_legacy_fallback_branches(repo_path)
    end
  end

  defp detect_legacy_fallback_branches(repo_path) do
    case System.cmd("git", ["-C", repo_path, "rev-parse", "--verify", "main"],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        {:ok, "main"}

      _ ->
        case System.cmd("git", ["-C", repo_path, "rev-parse", "--verify", "master"],
               stderr_to_stdout: true
             ) do
          {_, 0} -> {:ok, "master"}
          _ -> {:error, :no_default_branch}
        end
    end
  end

  defp build_time_opts(opts) do
    case Keyword.get(opts, :since) do
      %DateTime{} = since ->
        time_opts = [since: since]

        case Keyword.get(opts, :until) do
          %DateTime{} = until_dt -> Keyword.put(time_opts, :until, until_dt)
          _ -> time_opts
        end

      _ ->
        [since_days: Keyword.get(opts, :since_days, 30)]
    end
  end

  defp time_args(time_opts) do
    case Keyword.get(time_opts, :since) do
      %DateTime{} = since ->
        args = ["--since=#{DateTime.to_iso8601(since)}"]

        case Keyword.get(time_opts, :until) do
          %DateTime{} = until_dt -> args ++ ["--until=#{DateTime.to_iso8601(until_dt)}"]
          _ -> args
        end

      _ ->
        since_days = Keyword.get(time_opts, :since_days, 30)
        ["--since=#{since_days} days ago"]
    end
  end

  defp parse_log(repo_path, branch, time_opts) do
    args =
      ["-C", repo_path, "log", "--name-only", "--format=COMMIT:%H:%ct"] ++
        time_args(time_opts) ++ [branch, "--no-merges"]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, parse_output(output)}

      {error, _} ->
        Logger.warning("GitLogReader: git log failed: #{String.slice(error, 0, 200)}")
        {:error, :git_log_failed}
    end
  end

  @doc false
  def parse_output(output) do
    output
    |> String.split("COMMIT:", trim: true)
    |> Enum.flat_map(&parse_commit_block/1)
  end

  defp parse_commit_block(block) do
    lines = String.split(block, "\n", trim: true)

    case lines do
      [header | file_lines] ->
        case String.split(header, ":", parts: 2) do
          [hash, unix_str] ->
            timestamp = parse_unix_timestamp(unix_str)
            files = Enum.reject(file_lines, &(&1 == ""))

            [%{hash: hash, timestamp: timestamp, files: files}]

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp parse_unix_timestamp(str) do
    case Integer.parse(str) do
      {unix, _} -> DateTime.from_unix!(unix)
      :error -> DateTime.utc_now()
    end
  end

  defp filter_spotterignore(repo_path, commits) do
    with {:ok, repo_root} <- resolve_repo_root(repo_path),
         ignore_file = Path.join(repo_root, ".spotterignore"),
         true <- File.exists?(ignore_file),
         ignored when ignored != :error <- check_ignored_paths(repo_root, ignore_file, commits) do
      drop_ignored(commits, ignored)
    else
      false -> commits
      :error -> commits
      {:error, _} -> commits
    end
  end

  defp resolve_repo_root(repo_path) do
    case System.cmd("git", ["-C", repo_path, "rev-parse", "--show-toplevel"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, String.trim(output)}
      {_, _} -> {:error, :not_a_git_repo}
    end
  end

  defp check_ignored_paths(repo_root, ignore_file, commits) do
    all_paths =
      commits
      |> Enum.flat_map(& &1.files)
      |> Enum.uniq()

    if all_paths == [] do
      MapSet.new()
    else
      git_check_ignore_batch(repo_root, ignore_file, all_paths)
    end
  end

  defp git_check_ignore_batch(repo_root, ignore_file, paths) do
    base_args = [
      "-C",
      repo_root,
      "-c",
      "core.excludesFile=#{ignore_file}",
      "check-ignore",
      "--no-index"
    ]

    paths
    |> Enum.chunk_every(500)
    |> Enum.reduce(MapSet.new(), fn batch, acc ->
      MapSet.union(acc, run_check_ignore(base_args, batch))
    end)
  end

  defp run_check_ignore(base_args, batch) do
    case System.cmd("git", base_args ++ batch, stderr_to_stdout: true) do
      {output, 0} ->
        output |> String.split("\n", trim: true) |> MapSet.new()

      {_output, 1} ->
        MapSet.new()

      {error, code} ->
        Logger.warning(
          "GitLogReader: git check-ignore failed (exit #{code}): #{String.slice(error, 0, 200)}"
        )

        MapSet.new()
    end
  end

  @doc """
  Returns the most recent commit timestamp for a specific file within a time range.

  Returns `{:ok, DateTime.t()}` if a commit was found, `:none` if no commit
  touches the file in the range, or `{:error, term()}` on failure.
  """
  @spec last_file_touch(String.t(), String.t(), keyword()) ::
          {:ok, DateTime.t()} | :none | {:error, term()}
  def last_file_touch(repo_path, path, opts) do
    since = Keyword.fetch!(opts, :since)
    until_dt = Keyword.fetch!(opts, :until)

    with {:ok, branch} <- resolve_branch(repo_path, Keyword.get(opts, :branch)),
         {:ok, output} <- run_last_file_touch(repo_path, branch, path, since, until_dt) do
      parse_single_timestamp(output)
    end
  end

  defp run_last_file_touch(repo_path, branch, path, since, until_dt) do
    args = [
      "-C",
      repo_path,
      "log",
      "-n",
      "1",
      "--format=%ct",
      "--since=#{DateTime.to_iso8601(since)}",
      "--until=#{DateTime.to_iso8601(until_dt)}",
      branch,
      "--",
      path
    ]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {error, _} ->
        Logger.warning("GitLogReader: last_file_touch failed: #{String.slice(error, 0, 200)}")
        {:error, :git_log_failed}
    end
  end

  defp parse_single_timestamp(output) do
    case output |> String.trim() |> Integer.parse() do
      {unix, _} -> {:ok, DateTime.from_unix!(unix)}
      :error -> :none
    end
  end

  defp drop_ignored(commits, ignored) do
    Enum.map(commits, fn commit ->
      %{commit | files: Enum.reject(commit.files, &MapSet.member?(ignored, &1))}
    end)
  end
end
