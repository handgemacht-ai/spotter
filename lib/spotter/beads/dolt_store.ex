defmodule Spotter.Beads.DoltStore do
  @moduledoc """
  GenServer-per-project with in-memory issue/dependency cache backed by
  embedded Dolt CLI (`dolt sql --data-dir`).

  Each configured project gets its own GenServer that:
  - Loads all issues + dependencies on init via two SQL queries
  - Polls `.dolt/noms/manifest` mtime every 10s for change detection
  - Retries lock errors up to 3 times with 500ms backoff
  - Serves cached data on persistent failure

  ## Configuration

      config :spotter, Spotter.Beads.DoltStore,
        projects: %{
          "levio" => %{
            data_dir: "/srv/handgemacht/handgemacht/levio/.beads/embeddeddolt",
            database: "le"
          }
        }

  ## Test mode

  Set `:fixture_path` in the project config to load from JSONL files
  instead of the Dolt CLI:

      config :spotter, Spotter.Beads.DoltStore,
        projects: %{
          "test_project" => %{fixture_path: "/path/to/fixtures"}
        }
  """

  use GenServer

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @poll_interval_ms 10_000
  @cli_timeout_ms 15_000
  @max_retries 3
  @retry_backoff_ms 500

  # -- Public API --

  @doc "Returns the cached state for a project, or {:error, reason}."
  @spec get_state(String.t()) :: {:ok, map()} | {:error, :not_started | :loading}
  def get_state(project) do
    case Registry.lookup(Spotter.Beads.DoltStore.Registry, project) do
      [{pid, _}] -> GenServer.call(pid, :get_state)
      [] -> {:error, :not_started}
    end
  end

  @doc "Returns the config map for a project, or nil if not configured."
  @spec project_config(String.t()) :: map() | nil
  def project_config(project) do
    projects_config()[project]
  end

  @doc "Returns the list of configured project names."
  @spec configured_projects() :: [String.t()]
  def configured_projects do
    Map.keys(projects_config())
  end

  # -- Supervision --

  @doc false
  def child_spec(project) do
    %{
      id: {__MODULE__, project},
      start: {__MODULE__, :start_link, [project]},
      restart: :permanent
    }
  end

  @doc false
  def start_link(project) do
    GenServer.start_link(__MODULE__, project,
      name: {:via, Registry, {Spotter.Beads.DoltStore.Registry, project}}
    )
  end

  # -- GenServer Callbacks --

  @impl true
  def init(project) do
    config = project_config(project)

    state = %{
      project: project,
      config: config,
      issues_by_id: %{},
      deps_by_issue: %{},
      deps_by_target: %{},
      all_deps: [],
      child_ids: MapSet.new(),
      last_mtime: nil,
      loaded?: false
    }

    {:ok, state, {:continue, :initial_load}}
  end

  @impl true
  def handle_continue(:initial_load, state) do
    state = do_refresh(state)
    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, %{loaded?: false} = state) do
    {:reply, {:error, :loading}, state}
  end

  def handle_call(:get_state, _from, state) do
    reply = %{
      issues_by_id: state.issues_by_id,
      deps_by_issue: state.deps_by_issue,
      deps_by_target: state.deps_by_target,
      all_deps: state.all_deps,
      child_ids: state.child_ids
    }

    {:reply, {:ok, reply}, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state =
      if manifest_changed?(state) do
        do_refresh(state)
      else
        state
      end

    schedule_poll()
    {:noreply, state}
  end

  # -- Internals --

  defp do_refresh(state) do
    Tracer.with_span "spotter.dolt_store.refresh",
      attributes: [{"spotter.beads.project", state.project}] do
      case load_data(state.config, state.project) do
        {:ok, issues, deps} ->
          issues_by_id = Map.new(issues, &{&1.id, &1})
          {deps_by_issue, deps_by_target, child_ids} = index_deps(deps)

          Tracer.set_attribute("spotter.dolt_store.issue_count", map_size(issues_by_id))

          %{
            state
            | issues_by_id: issues_by_id,
              deps_by_issue: deps_by_issue,
              deps_by_target: deps_by_target,
              all_deps: deps,
              child_ids: child_ids,
              last_mtime: current_manifest_mtime(state.config),
              loaded?: true
          }

        {:error, reason} ->
          Logger.warning("DoltStore refresh failed for #{state.project}: #{inspect(reason)}")

          Tracer.set_status(:error, inspect(reason))

          if state.loaded? do
            state
          else
            %{state | loaded?: true}
          end
      end
    end
  end

  defp load_data(%{fixture_path: path}, _project) do
    load_fixtures(path)
  end

  defp load_data(%{data_dir: data_dir, database: database}, _project) do
    with {:ok, issues} <- run_query_with_retry(data_dir, database, issues_sql()),
         {:ok, deps} <- run_query_with_retry(data_dir, database, deps_sql()) do
      {:ok, issues, deps}
    end
  end

  defp issues_sql do
    """
    SELECT id, title, status, priority, issue_type, description,
           created_at, updated_at, closed_at, assignee
    FROM issues
    """
  end

  defp deps_sql do
    """
    SELECT issue_id, depends_on_id, type, created_at
    FROM dependencies
    """
  end

  defp run_query_with_retry(data_dir, database, sql, attempt \\ 1) do
    case run_dolt_sql(data_dir, database, sql) do
      {:ok, rows} ->
        {:ok, rows}

      {:error, :lock_error} when attempt < @max_retries ->
        Process.sleep(@retry_backoff_ms * attempt)
        run_query_with_retry(data_dir, database, sql, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_dolt_sql(data_dir, database, sql) do
    full_sql = "USE #{database}; #{String.trim(sql)}"

    args = [
      "--data-dir",
      data_dir,
      "sql",
      "-q",
      full_sql,
      "-r",
      "json"
    ]

    case System.cmd("dolt", args, stderr_to_stdout: true, timeout: @cli_timeout_ms) do
      {output, 0} ->
        parse_json_output(output)

      {output, _code} ->
        if String.contains?(output, "lock") do
          {:error, :lock_error}
        else
          {:error, {:cli_error, String.slice(output, 0, 200)}}
        end
    end
  rescue
    e -> {:error, {:cli_exception, Exception.message(e)}}
  end

  defp parse_json_output(output) do
    case Jason.decode(output) do
      {:ok, %{"rows" => rows}} when is_list(rows) ->
        {:ok, Enum.map(rows, &atomize_keys/1)}

      {:ok, %{}} ->
        {:ok, []}

      {:error, _} ->
        {:error, :json_parse_error}
    end
  end

  @datetime_fields ~w(created_at updated_at closed_at)
  @integer_fields ~w(priority)

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      atom_key = String.to_atom(k)
      {atom_key, coerce_value(k, v)}
    end)
  end

  defp coerce_value(key, value) when key in @datetime_fields and is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, ndt} -> ndt
      {:error, _} -> parse_datetime_relaxed(value)
    end
  end

  defp coerce_value(key, value) when key in @integer_fields and is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> value
    end
  end

  defp coerce_value(_key, value), do: value

  defp parse_datetime_relaxed(str) do
    case NaiveDateTime.from_iso8601(String.replace(str, " ", "T")) do
      {:ok, ndt} -> ndt
      {:error, _} -> str
    end
  end

  defp index_deps(deps) do
    deps_by_issue = Enum.group_by(deps, & &1.issue_id)
    deps_by_target = Enum.group_by(deps, & &1.depends_on_id)

    child_ids =
      deps
      |> Enum.filter(&(&1.type in ["parent-child", "parent"]))
      |> Enum.map(& &1.issue_id)
      |> MapSet.new()

    {deps_by_issue, deps_by_target, child_ids}
  end

  defp manifest_changed?(%{config: %{fixture_path: _}}), do: false

  defp manifest_changed?(state) do
    current = current_manifest_mtime(state.config)
    current != nil and current != state.last_mtime
  end

  defp current_manifest_mtime(%{fixture_path: _}), do: nil

  defp current_manifest_mtime(%{data_dir: data_dir, database: database}) do
    path = Path.join([data_dir, database, ".dolt", "noms", "manifest"])

    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> nil
    end
  end

  defp current_manifest_mtime(_), do: nil

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp projects_config do
    Application.get_env(:spotter, __MODULE__, [])
    |> Keyword.get(:projects, %{})
  end

  # -- JSONL Fixture Loading --

  defp load_fixtures(path) do
    issues_file = Path.join(path, "issues.jsonl")
    deps_file = Path.join(path, "dependencies.jsonl")

    with {:ok, issues} <- read_jsonl(issues_file),
         {:ok, deps} <- read_jsonl(deps_file) do
      {:ok, issues, deps}
    end
  end

  defp read_jsonl(path) do
    case File.read(path) do
      {:ok, content} ->
        rows =
          content
          |> String.split("\n", trim: true)
          |> Enum.flat_map(&decode_jsonl_line/1)

        {:ok, rows}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_jsonl_line(line) do
    case Jason.decode(line) do
      {:ok, map} -> [atomize_keys(map)]
      {:error, _} -> []
    end
  end
end
