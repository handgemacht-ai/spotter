defmodule Spotter.Transcripts.Sessions do
  @moduledoc """
  Shared helpers for finding or creating sessions from hook events.
  """

  alias Spotter.Services.GitRunner
  alias Spotter.Transcripts.{Config, Project, Session}

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @worktree_path_pattern ~r|/\.claude/worktrees/[^/]+$|

  @doc """
  Finds an existing session by session_id, or creates a minimal stub.

  When `cwd` is provided, matches it against project config patterns to assign
  the correct project. When no configured pattern matches, a project is
  auto-created from the cwd basename.
  """
  def find_or_create(session_id, opts \\ []) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{} = session} ->
        {:ok, session}

      {:ok, nil} ->
        create_stub(session_id, opts)

      {:error, _} = error ->
        error
    end
  end

  defp create_stub(session_id, opts) do
    cwd = Keyword.get(opts, :cwd)
    canonical_cwd = if is_binary(cwd), do: canonicalize_cwd(cwd), else: cwd

    with {:ok, project} <- find_or_create_project(canonical_cwd) do
      Ash.create(Session, %{
        session_id: session_id,
        cwd: cwd,
        project_id: project.id,
        started_at: DateTime.utc_now()
      })
    end
  end

  @doc """
  Matches a cwd path against configured project patterns and returns the
  matching project name and pattern source.

  Returns `{:ok, name, pattern_source}` or `:no_match`.
  """
  @spec match_project_by_cwd(String.t()) :: {:ok, String.t(), String.t()} | :no_match
  def match_project_by_cwd(cwd) when is_binary(cwd) do
    config = Config.read!()
    match_project(cwd, config.projects)
  end

  @doc """
  Resolves a cwd path to an existing project record without creating one.

  Returns `{:ok, project}` or `{:error, reason}`.
  """
  @spec resolve_project_by_cwd(String.t()) :: {:ok, Project.t()} | {:error, term()}
  def resolve_project_by_cwd(cwd) when is_binary(cwd) do
    case match_project_by_cwd(cwd) do
      {:ok, name, _pattern} ->
        case Project |> Ash.Query.filter(name == ^name) |> Ash.read_one() do
          {:ok, %Project{} = project} -> {:ok, project}
          {:ok, nil} -> {:error, {:project_not_found, cwd}}
          {:error, _} = error -> error
        end

      :no_match ->
        {:error, {:project_not_found, cwd}}
    end
  end

  defp find_or_create_project(cwd) when is_binary(cwd) do
    case match_project_by_cwd(cwd) do
      {:ok, name, pattern} ->
        upsert_project(name, pattern)

      :no_match ->
        name = cwd |> Path.basename() |> String.downcase()
        dir_name = String.replace(cwd, "/", "-")
        pattern = "^#{Regex.escape(dir_name)}$"
        upsert_project(name, pattern)
    end
  end

  defp find_or_create_project(_nil), do: {:error, :project_not_found}

  defp match_project(cwd, projects) do
    # Convert cwd to the transcript dir format: /home/marco/projects/spotter -> -home-marco-projects-spotter
    dir_name = String.replace(cwd, "/", "-")

    projects
    |> Enum.filter(fn {_name, %{pattern: pattern}} -> Regex.match?(pattern, dir_name) end)
    |> longest_pattern_match()
  end

  # When multiple patterns match, pick the longest pattern source (most specific).
  # This prevents "todo" from shadowing "todo2" when both patterns match.
  defp longest_pattern_match([]), do: :no_match

  defp longest_pattern_match(matches) do
    {name, %{pattern: pattern}} =
      Enum.max_by(matches, fn {_name, %{pattern: pattern}} ->
        String.length(Regex.source(pattern))
      end)

    {:ok, name, Regex.source(pattern)}
  end

  defp upsert_project(name, pattern) do
    case Project |> Ash.Query.filter(name == ^name) |> Ash.read_one() do
      {:ok, %Project{} = project} -> {:ok, project}
      {:ok, nil} -> Ash.create(Project, %{name: name, pattern: pattern})
      {:error, _} = error -> error
    end
  end

  @doc """
  Resolves a worktree cwd to its canonical main repository root.

  Uses `git rev-parse --path-format=absolute --git-common-dir` when the
  directory exists on disk. Falls back to path-based heuristic for
  `.claude/worktrees/<name>` patterns. Returns the original cwd if
  neither strategy applies.
  """
  @spec canonicalize_cwd(String.t()) :: String.t()
  def canonicalize_cwd(cwd) when is_binary(cwd) do
    Tracer.with_span "spotter.sessions.canonicalize_cwd" do
      Tracer.set_attribute("spotter.sessions.original_cwd", cwd)
      normalized = String.trim_trailing(cwd, "/")

      canonical = try_git_canonicalize(normalized) || try_path_heuristic(normalized) || normalized

      Tracer.set_attribute("spotter.sessions.canonical_cwd", canonical)
      Tracer.set_attribute("spotter.sessions.cwd_changed", canonical != cwd)
      canonical
    end
  end

  defp try_git_canonicalize(cwd) do
    with true <- File.dir?(cwd),
         {:ok, output} <- git_common_dir(cwd),
         true <- output |> String.trim() |> String.ends_with?("/.git") do
      output |> String.trim() |> Path.dirname()
    else
      _ -> nil
    end
  end

  defp git_common_dir(cwd) do
    GitRunner.run(
      ["rev-parse", "--path-format=absolute", "--git-common-dir"],
      cd: cwd,
      timeout_ms: 5_000
    )
  end

  defp try_path_heuristic(cwd) do
    if Regex.match?(@worktree_path_pattern, cwd) do
      String.replace(cwd, @worktree_path_pattern, "")
    end
  end
end
