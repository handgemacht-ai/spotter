defmodule Spotter.Transcripts.Sessions do
  @moduledoc """
  Shared helpers for finding or creating sessions from hook events.
  """

  alias Spotter.Transcripts.{Config, Project, Session}
  require Ash.Query

  @doc """
  Finds an existing session by session_id, or creates a minimal stub.

  When `cwd` is provided, matches it against project config patterns to assign
  the correct project. When no matching project can be resolved, returns an error
  instead of silently assigning an "Unknown" project.
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

    with {:ok, project} <- find_or_create_project(cwd) do
      Ash.create(Session, %{
        session_id: session_id,
        cwd: cwd,
        project_id: project.id,
        started_at: DateTime.utc_now()
      })
    end
  end

  defp find_or_create_project(cwd) when is_binary(cwd) do
    config = Config.read!()

    case match_project(cwd, config.projects) do
      {:ok, name, pattern} ->
        upsert_project(name, pattern)

      :no_match ->
        {:error, {:project_not_found, cwd}}
    end
  end

  defp find_or_create_project(_nil), do: {:error, :project_not_found}

  defp match_project(cwd, projects) do
    # Convert cwd to the transcript dir format: /home/marco/projects/spotter -> -home-marco-projects-spotter
    dir_name = String.replace(cwd, "/", "-")

    Enum.find_value(projects, :no_match, fn {name, %{pattern: pattern}} ->
      if Regex.match?(pattern, dir_name), do: {:ok, name, Regex.source(pattern)}
    end)
  end

  defp upsert_project(name, pattern) do
    case Project |> Ash.Query.filter(name == ^name) |> Ash.read_one() do
      {:ok, %Project{} = project} -> {:ok, project}
      {:ok, nil} -> Ash.create(Project, %{name: name, pattern: pattern})
      {:error, _} = error -> error
    end
  end
end
