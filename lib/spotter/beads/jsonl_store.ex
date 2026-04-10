defmodule Spotter.Beads.JsonlStore do
  @moduledoc """
  In-memory store for beads JSONL data, one GenServer per project.

  Loads `issues.jsonl` and `dependencies.jsonl` from a project's `.beads/backup/`
  directory. Polls file mtimes every 5 seconds and reloads on change.
  """

  use GenServer

  require Logger

  @poll_interval :timer.seconds(5)
  @registry __MODULE__.Registry

  # -- Public API --

  @doc """
  Returns the data state for a project, starting the store lazily if needed.
  """
  @spec get_state(String.t()) :: {:ok, map()} | {:error, :not_configured}
  def get_state(project) do
    case ensure_started(project) do
      {:ok, pid} -> {:ok, GenServer.call(pid, :get_state)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Returns all configured project names.
  """
  @spec configured_projects() :: [String.t()]
  def configured_projects do
    project_paths()
    |> Map.keys()
  end

  @doc """
  Returns the backup path for a project, or nil if not configured.
  """
  @spec backup_path(String.t()) :: String.t() | nil
  def backup_path(project) do
    Map.get(project_paths(), project)
  end

  # -- GenServer Callbacks --

  def start_link({project, path}) do
    GenServer.start_link(__MODULE__, {project, path}, name: via(project))
  end

  @impl true
  def init({project, path}) do
    state = %{
      project: project,
      path: path,
      issues_by_id: %{},
      deps_by_issue: %{},
      deps_by_target: %{},
      all_deps: [],
      mtimes: %{},
      child_ids: MapSet.new()
    }

    state = reload(state)
    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = maybe_reload(state)
    schedule_poll()
    {:noreply, state}
  end

  # -- Internal --

  defp ensure_started(project) do
    case Registry.lookup(@registry, project) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case backup_path(project) do
          nil -> {:error, :not_configured}
          path -> start_under_supervisor(project, path)
        end
    end
  end

  defp start_under_supervisor(project, path) do
    spec = {__MODULE__, {project, path}}

    case DynamicSupervisor.start_child(__MODULE__.Supervisor, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _} = err -> err
    end
  end

  defp via(project), do: {:via, Registry, {@registry, project}}

  defp project_paths do
    Application.get_env(:spotter, __MODULE__, [])
    |> Keyword.get(:project_paths, %{})
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp maybe_reload(state) do
    current_mtimes = file_mtimes(state.path)

    if current_mtimes != state.mtimes do
      reload(state)
    else
      state
    end
  end

  defp reload(state) do
    issues_path = Path.join(state.path, "issues.jsonl")
    deps_path = Path.join(state.path, "dependencies.jsonl")

    issues = parse_issues(issues_path)
    deps = parse_deps(deps_path)

    issues_by_id =
      Map.new(issues, fn issue -> {issue.id, issue} end)

    deps_by_issue =
      Enum.group_by(deps, & &1.issue_id)

    deps_by_target =
      Enum.group_by(deps, & &1.depends_on_id)

    child_ids =
      deps
      |> Enum.filter(&(&1.type in ["parent-child", "parent"]))
      |> Enum.map(& &1.issue_id)
      |> MapSet.new()

    %{
      state
      | issues_by_id: issues_by_id,
        deps_by_issue: deps_by_issue,
        deps_by_target: deps_by_target,
        all_deps: deps,
        child_ids: child_ids,
        mtimes: file_mtimes(state.path)
    }
  end

  defp file_mtimes(path) do
    %{
      issues: file_mtime(Path.join(path, "issues.jsonl")),
      deps: file_mtime(Path.join(path, "dependencies.jsonl"))
    }
  end

  defp file_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> nil
    end
  end

  defp parse_issues(path) do
    path
    |> read_jsonl()
    |> Enum.map(&normalize_issue/1)
  end

  defp parse_deps(path) do
    path
    |> read_jsonl()
    |> Enum.map(&normalize_dep/1)
  end

  defp read_jsonl(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      {:error, _} ->
        []
    end
  end

  defp normalize_issue(raw) do
    %{
      id: raw["id"],
      title: raw["title"] || "",
      status: raw["status"] || "open",
      priority: raw["priority"] || 2,
      issue_type: raw["issue_type"] || "task",
      description: raw["description"],
      created_at: parse_datetime(raw["created_at"]),
      updated_at: parse_datetime(raw["updated_at"]),
      closed_at: parse_datetime(raw["closed_at"]),
      assignee: raw["assignee"]
    }
  end

  defp normalize_dep(raw) do
    %{
      issue_id: raw["issue_id"],
      depends_on_id: raw["depends_on_id"],
      type: raw["type"],
      created_at: parse_datetime(raw["created_at"])
    }
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case NaiveDateTime.from_iso8601(str) do
      {:ok, ndt} -> ndt
      _ -> nil
    end
  end
end
