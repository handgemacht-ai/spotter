defmodule Spotter.Beads.Client do
  @moduledoc """
  Read-only Dolt client for querying beads issue data.

  Manages lazy-started MyXQL connection pools per project. Each project maps
  directly to a Dolt database by name.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Beads.DoltConfig

  @pool_prefix __MODULE__.Pool
  @query_timeout 5_000
  @connect_timeout 500

  # -- Public API --

  @doc """
  Executes a raw SQL query against the given project's beads database.
  """
  @spec query(String.t(), String.t(), list()) ::
          {:ok, MyXQL.Result.t()} | {:error, atom()}
  def query(project, sql, params \\ []) do
    Tracer.with_span "spotter.beads.client.query" do
      Tracer.set_attribute("spotter.beads.database", DoltConfig.database_name(project))
      Tracer.set_attribute("spotter.beads.query_name", "raw")

      with {:ok, pool} <- ensure_pool(project) do
        run_query(pool, sql, params)
      end
    end
  end

  @doc """
  Lists epic issues for a project, optionally filtered by status.
  """
  @spec list_epics(String.t(), :all | :open | :closed) ::
          {:ok, [map()]} | {:error, atom()}
  def list_epics(project, filter \\ :all) do
    Tracer.with_span "spotter.beads.client.list_epics" do
      Tracer.set_attribute("spotter.beads.database", DoltConfig.database_name(project))
      Tracer.set_attribute("spotter.beads.query_name", "list_epics")

      {where_clause, params} = epic_filter_clause(filter)

      sql = """
      SELECT id, title, status, priority, issue_type, description,
             created_at, updated_at, closed_at, assignee
      FROM issues
      WHERE issue_type = 'epic' #{where_clause}
      ORDER BY priority ASC, created_at DESC
      """

      with {:ok, pool} <- ensure_pool(project) do
        case run_query(pool, sql, params) do
          {:ok, result} -> {:ok, rows_to_maps(result)}
          {:error, _} = err -> err
        end
      end
    end
  end

  @doc """
  Fetches a single issue by ID.
  """
  @spec get_issue(String.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | atom()}
  def get_issue(project, issue_id) do
    Tracer.with_span "spotter.beads.client.get_issue" do
      Tracer.set_attribute("spotter.beads.database", DoltConfig.database_name(project))
      Tracer.set_attribute("spotter.beads.query_name", "get_issue")

      sql = """
      SELECT id, title, status, priority, issue_type, description,
             created_at, updated_at, closed_at, assignee
      FROM issues
      WHERE id = ?
      """

      with {:ok, pool} <- ensure_pool(project) do
        case run_query(pool, sql, [issue_id]) do
          {:ok, %{num_rows: 0}} -> {:error, :not_found}
          {:ok, %{num_rows: 1} = result} -> {:ok, result |> rows_to_maps() |> hd()}
          {:error, _} = err -> err
        end
      end
    end
  end

  @doc """
  Fetches child issues (dependencies where this issue is depended upon).
  """
  @spec get_children(String.t(), String.t()) ::
          {:ok, [map()]} | {:error, atom()}
  def get_children(project, parent_id) do
    Tracer.with_span "spotter.beads.client.get_children" do
      Tracer.set_attribute("spotter.beads.database", DoltConfig.database_name(project))
      Tracer.set_attribute("spotter.beads.query_name", "get_children")

      sql = """
      SELECT i.id, i.title, i.status, i.priority, i.issue_type, i.description,
             i.created_at, i.updated_at, i.closed_at, i.assignee
      FROM issues i
      INNER JOIN dependencies d ON d.issue_id = i.id
      WHERE d.depends_on_id = ? AND d.type IN ('parent-child', 'parent')
      ORDER BY i.priority ASC, i.created_at DESC
      """

      with {:ok, pool} <- ensure_pool(project) do
        case run_query(pool, sql, [parent_id]) do
          {:ok, result} -> {:ok, rows_to_maps(result)}
          {:error, _} = err -> err
        end
      end
    end
  end

  @doc """
  Returns a map of project names to their epic counts.

  Queries the shared workspace Dolt server for all non-system databases,
  then counts epics in each.
  """
  @spec epic_counts_by_project() :: {:ok, map()} | {:error, atom()}
  def epic_counts_by_project do
    Tracer.with_span "spotter.beads.client.epic_counts_by_project" do
      Tracer.set_attribute("spotter.beads.query_name", "epic_counts_by_project")

      config = DoltConfig.connection_opts("__admin__")
      admin_opts = Keyword.put(config, :database, "information_schema")

      case MyXQL.start_link(admin_opts) do
        {:ok, conn} ->
          try do
            fetch_epic_counts(conn, config)
          after
            GenServer.stop(conn)
          end

        {:error, err} ->
          {:error, classify_error(err)}
      end
    end
  end

  @doc """
  Searches beads with text search, status filtering, sort, and direction.

  Returns a unified list of epics (with task counts) and orphan beads.

  ## Options

    * `:query` - substring search across id, title, description (default: nil)
    * `:status` - `:open | :closed | :all` (default: `:open`)
    * `:sort` - `:priority | :created_at` (default: `:priority`)
    * `:dir` - `:asc | :desc` (default: `:desc`)
    * `:types` - `[:epic | :orphan]` (default: `[:epic, :orphan]`)
  """
  @spec search_beads(String.t(), keyword()) :: {:ok, [map()]} | {:error, atom()}
  def search_beads(project, opts \\ []) do
    Tracer.with_span "spotter.beads.client.search_beads" do
      Tracer.set_attribute("spotter.beads.database", DoltConfig.database_name(project))
      Tracer.set_attribute("spotter.beads.query_name", "search_beads")

      search_opts = %{
        query: normalize_query(opts[:query]),
        status: opts[:status] || :open,
        order: "ORDER BY #{validate_sort(opts[:sort])} #{validate_dir(opts[:dir])}",
        types: opts[:types] || [:epic, :orphan]
      }

      with {:ok, pool} <- ensure_pool(project) do
        epics = search_epics(pool, search_opts)
        orphans = search_orphans(pool, search_opts)
        {:ok, epics ++ orphans}
      end
    end
  end

  @doc """
  Lists non-epic issues with no parent dependency (orphans).
  """
  @spec list_orphan_issues(String.t(), :all | :open | :closed) ::
          {:ok, [map()]} | {:error, atom()}
  def list_orphan_issues(project, filter \\ :all) do
    Tracer.with_span "spotter.beads.client.list_orphan_issues" do
      Tracer.set_attribute("spotter.beads.database", DoltConfig.database_name(project))
      Tracer.set_attribute("spotter.beads.query_name", "list_orphan_issues")

      {where_clause, params} = orphan_filter_clause(filter)

      sql = """
      SELECT id, title, status, priority, issue_type, description,
             created_at, updated_at, closed_at, assignee
      FROM issues
      WHERE issue_type != 'epic'
      AND id NOT IN (
        SELECT issue_id FROM dependencies WHERE type IN ('parent-child', 'parent')
      )
      #{where_clause}
      ORDER BY priority ASC, created_at DESC
      """

      with {:ok, pool} <- ensure_pool(project) do
        case run_query(pool, sql, params) do
          {:ok, result} -> {:ok, rows_to_maps(result)}
          {:error, _} = err -> err
        end
      end
    end
  end

  @doc """
  Fetches dependencies for an issue.
  """
  @spec get_dependencies(String.t(), String.t()) ::
          {:ok, [map()]} | {:error, atom()}
  def get_dependencies(project, issue_id) do
    Tracer.with_span "spotter.beads.client.get_dependencies" do
      Tracer.set_attribute("spotter.beads.database", DoltConfig.database_name(project))
      Tracer.set_attribute("spotter.beads.query_name", "get_dependencies")

      sql = """
      SELECT d.depends_on_id, d.type, d.created_at,
             i.title AS depends_on_title, i.status AS depends_on_status
      FROM dependencies d
      LEFT JOIN issues i ON i.id = d.depends_on_id
      WHERE d.issue_id = ?
      ORDER BY d.created_at ASC
      """

      with {:ok, pool} <- ensure_pool(project) do
        case run_query(pool, sql, [issue_id]) do
          {:ok, result} -> {:ok, rows_to_maps(result)}
          {:error, _} = err -> err
        end
      end
    end
  end

  # -- Pool Management --

  defp ensure_pool(project) do
    pool_name = pool_name(project)

    case Process.whereis(pool_name) do
      nil -> start_pool(project)
      _pid -> {:ok, pool_name}
    end
  end

  defp start_pool(project) do
    pool_name = pool_name(project)
    opts = DoltConfig.connection_opts(project)

    myxql_opts =
      opts
      |> Keyword.put(:name, pool_name)
      |> Keyword.put(:pool_size, 2)
      |> Keyword.put(:queue_target, 1_000)
      |> Keyword.put(:queue_interval, 5_000)

    case MyXQL.start_link(myxql_opts) do
      {:ok, pid} ->
        case verify_connection(pool_name) do
          :ok ->
            {:ok, pool_name}

          {:error, reason} ->
            GenServer.stop(pid)
            {:error, reason}
        end

      {:error, err} ->
        {:error, classify_error(err)}
    end
  end

  defp verify_connection(pool_name) do
    case MyXQL.query(pool_name, "SELECT 1", [], timeout: @connect_timeout) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, classify_error(err)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :connection_refused}
  end

  defp pool_name(project) do
    Module.concat(@pool_prefix, Macro.camelize(project))
  end

  # -- Query Execution --

  defp run_query(pool, sql, params) do
    case MyXQL.query(pool, sql, params, timeout: @query_timeout) do
      {:ok, result} -> {:ok, result}
      {:error, err} -> {:error, classify_error(err)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :connection_refused}
  end

  # -- Helpers --

  defp epic_filter_clause(:all), do: {"", []}
  defp epic_filter_clause(:open), do: {"AND status = ?", ["open"]}
  defp epic_filter_clause(:closed), do: {"AND status = ?", ["closed"]}

  defp orphan_filter_clause(:all), do: {"", []}
  defp orphan_filter_clause(:open), do: {"AND status = ?", ["open"]}
  defp orphan_filter_clause(:closed), do: {"AND status = ?", ["closed"]}

  defp search_epics(pool, %{types: types} = opts) do
    if :epic in types, do: do_search_epics(pool, opts), else: []
  end

  defp do_search_epics(pool, %{status: status, query: query, order: order}) do
    {where, params} = search_where_clause(status, query, "i.issue_type = 'epic'")

    sql = """
    SELECT i.*, (
      SELECT COUNT(*) FROM dependencies d
      WHERE d.depends_on_id = i.id AND d.type IN ('parent-child', 'parent')
    ) AS task_count
    FROM issues i
    WHERE #{where}
    #{order}
    """

    case run_query(pool, sql, params) do
      {:ok, result} -> rows_to_maps(result)
      {:error, _} -> []
    end
  end

  defp search_orphans(pool, %{types: types} = opts) do
    if :orphan in types, do: do_search_orphans(pool, opts), else: []
  end

  defp do_search_orphans(pool, %{status: status, query: query, order: order}) do
    base =
      "i.issue_type != 'epic' AND i.id NOT IN (SELECT issue_id FROM dependencies WHERE type IN ('parent-child', 'parent'))"

    {where, params} = search_where_clause(status, query, base)

    sql = """
    SELECT i.*, 0 AS task_count
    FROM issues i
    WHERE #{where}
    #{order}
    """

    case run_query(pool, sql, params) do
      {:ok, result} -> rows_to_maps(result)
      {:error, _} -> []
    end
  end

  defp normalize_query(nil), do: nil

  defp normalize_query(q) when is_binary(q) do
    trimmed = String.trim(q)
    if trimmed == "", do: nil, else: trimmed
  end

  @allowed_sorts %{priority: "i.priority", created_at: "i.created_at"}
  defp validate_sort(col) when is_atom(col), do: Map.get(@allowed_sorts, col, "i.priority")
  defp validate_sort(_), do: "i.priority"

  defp validate_dir(:asc), do: "ASC"
  defp validate_dir(:desc), do: "DESC"
  defp validate_dir(_), do: "DESC"

  defp search_where_clause(status, query, base_condition) do
    {status_clause, status_params} = search_status_clause(status)
    {query_clause, query_params} = search_query_clause(query)

    where =
      Enum.join(
        [base_condition, status_clause, query_clause] |> Enum.reject(&(&1 == "")),
        " AND "
      )

    {where, status_params ++ query_params}
  end

  defp search_status_clause(:all), do: {"", []}
  defp search_status_clause(:open), do: {"i.status = ?", ["open"]}
  defp search_status_clause(:closed), do: {"i.status = ?", ["closed"]}
  defp search_status_clause(_), do: {"i.status = ?", ["open"]}

  defp search_query_clause(nil), do: {"", []}

  defp search_query_clause(q) do
    pattern = "%#{q}%"
    {"(i.id LIKE ? OR i.title LIKE ? OR i.description LIKE ?)", [pattern, pattern, pattern]}
  end

  defp rows_to_maps(%MyXQL.Result{columns: columns, rows: rows}) do
    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new(fn {col, val} -> {String.to_atom(col), val} end)
    end)
  end

  defp fetch_epic_counts(conn, config) do
    case MyXQL.query(
           conn,
           "SELECT SCHEMA_NAME FROM SCHEMATA WHERE SCHEMA_NAME NOT IN ('information_schema', 'mysql', 'dolt', 'performance_schema')",
           [],
           timeout: @query_timeout
         ) do
      {:ok, %{rows: rows}} ->
        db_names = Enum.map(rows, fn [db_name] -> db_name end)
        {:ok, aggregate_epic_counts(db_names, config)}

      {:error, err} ->
        {:error, classify_error(err)}
    end
  end

  defp aggregate_epic_counts(db_names, config) do
    Enum.reduce(db_names, %{}, fn db_name, acc ->
      case count_epics_in(config, db_name) do
        {:ok, count} -> Map.put(acc, db_name, count)
        {:error, _} -> acc
      end
    end)
  end

  defp count_epics_in(base_config, db_name) do
    opts = Keyword.put(base_config, :database, db_name)

    with {:ok, conn} <- MyXQL.start_link(opts) do
      result = query_epic_count(conn)
      GenServer.stop(conn)
      result
    end
  end

  defp query_epic_count(conn) do
    case MyXQL.query(conn, "SELECT COUNT(*) FROM issues WHERE issue_type = 'epic'", [],
           timeout: @query_timeout
         ) do
      {:ok, %{rows: [[count]]}} -> {:ok, count}
      {:error, _} = err -> err
    end
  end

  defp classify_error(%MyXQL.Error{mysql: %{code: 1044}}), do: :access_denied
  defp classify_error(%MyXQL.Error{mysql: %{code: 1049}}), do: :unknown_project
  defp classify_error(%MyXQL.Error{mysql: %{code: 2003}}), do: :connection_refused
  defp classify_error(%MyXQL.Error{mysql: %{code: 2005}}), do: :connection_refused

  defp classify_error(%MyXQL.Error{message: msg}) when is_binary(msg) do
    cond do
      msg =~ "refused" -> :connection_refused
      msg =~ "timeout" -> :query_timeout
      true -> :unknown_error
    end
  end

  defp classify_error(%DBConnection.ConnectionError{}), do: :connection_refused
  defp classify_error(_), do: :unknown_error
end
