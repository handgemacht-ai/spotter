defmodule Spotter.Beads.Client do
  @moduledoc """
  Read-only client for querying beads issue data from JSONL files.

  Delegates to `Spotter.Beads.JsonlStore` for in-memory lookups against
  data loaded from `.beads/backup/` JSONL exports.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Beads.DoltConfig
  alias Spotter.Beads.JsonlStore

  @parent_types ["parent-child", "parent"]

  # -- Public API --

  @doc """
  Lists epic issues for a project, optionally filtered by status.
  """
  @spec list_epics(String.t(), :all | :open | :closed) ::
          {:ok, [map()]} | {:error, atom()}
  def list_epics(project, filter \\ :all) do
    Tracer.with_span "spotter.beads.client.list_epics" do
      Tracer.set_attribute("spotter.beads.database", DoltConfig.database_name(project))
      Tracer.set_attribute("spotter.beads.query_name", "list_epics")

      with {:ok, state} <- JsonlStore.get_state(project) do
        epics =
          state.issues_by_id
          |> Map.values()
          |> Enum.filter(&(&1.issue_type == "epic"))
          |> filter_by_status(filter)
          |> Enum.map(fn epic ->
            task_count = count_children(state, epic.id)
            Map.put(epic, :task_count, task_count)
          end)
          |> sort_by_priority_created()

        {:ok, epics}
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

      with {:ok, state} <- JsonlStore.get_state(project) do
        case Map.fetch(state.issues_by_id, issue_id) do
          {:ok, issue} -> {:ok, issue}
          :error -> {:error, :not_found}
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

      with {:ok, state} <- JsonlStore.get_state(project) do
        children =
          state.deps_by_target
          |> Map.get(parent_id, [])
          |> Enum.filter(&(&1.type in @parent_types))
          |> Enum.map(& &1.issue_id)
          |> Enum.map(&Map.get(state.issues_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> sort_by_priority_created()

        {:ok, children}
      end
    end
  end

  @doc """
  Returns a map of project names to their epic counts.

  Iterates configured projects and counts epics in each.
  """
  @spec epic_counts_by_project() :: {:ok, map()} | {:error, atom()}
  def epic_counts_by_project do
    Tracer.with_span "spotter.beads.client.epic_counts_by_project" do
      Tracer.set_attribute("spotter.beads.query_name", "epic_counts_by_project")

      counts =
        JsonlStore.configured_projects()
        |> Enum.reduce(%{}, fn project, acc ->
          case JsonlStore.get_state(project) do
            {:ok, state} ->
              count =
                state.issues_by_id
                |> Map.values()
                |> Enum.count(&(&1.issue_type == "epic"))

              db_name = DoltConfig.database_name(project)
              Map.put(acc, db_name, count)

            {:error, _} ->
              acc
          end
        end)

      {:ok, counts}
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

      query = normalize_query(opts[:query])
      status = opts[:status] || :open
      sort = opts[:sort] || :priority
      dir = opts[:dir] || :desc
      types = opts[:types] || [:epic, :orphan]

      with {:ok, state} <- JsonlStore.get_state(project) do
        epics = search_epics(state, types, status, query)
        orphans = search_orphans(state, types, status, query)

        sorted = sort_results(epics ++ orphans, sort, dir)
        {:ok, sorted}
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

      with {:ok, state} <- JsonlStore.get_state(project) do
        orphans =
          state.issues_by_id
          |> Map.values()
          |> Enum.filter(&orphan?(&1, state.child_ids))
          |> filter_by_status(filter)
          |> sort_by_priority_created()

        {:ok, orphans}
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

      with {:ok, state} <- JsonlStore.get_state(project) do
        deps =
          state.deps_by_issue
          |> Map.get(issue_id, [])
          |> Enum.map(fn dep ->
            target = Map.get(state.issues_by_id, dep.depends_on_id)

            %{
              depends_on_id: dep.depends_on_id,
              type: dep.type,
              created_at: dep.created_at,
              depends_on_title: if(target, do: target.title),
              depends_on_status: if(target, do: target.status)
            }
          end)
          |> Enum.sort_by(& &1.created_at, NaiveDateTime)

        {:ok, deps}
      end
    end
  end

  @doc """
  Builds the sibling dependency graph for a bead.

  Finds the parent epic, fetches all sibling issues under that parent,
  then fetches non-parent dependencies among those siblings.

  Returns `{:ok, graph}` where graph is `%{nodes: [...], edges: [...]}` or
  `{:ok, nil}` when there are fewer than 2 siblings.
  """
  @spec get_sibling_graph(String.t(), String.t()) ::
          {:ok, map() | nil} | {:error, atom()}
  def get_sibling_graph(project, issue_id) do
    Tracer.with_span "spotter.beads.client.get_sibling_graph" do
      Tracer.set_attribute("spotter.beads.database", DoltConfig.database_name(project))
      Tracer.set_attribute("spotter.beads.issue_id", issue_id)

      with {:ok, state} <- JsonlStore.get_state(project) do
        parent_id = find_parent_id(state, issue_id)
        build_sibling_graph(state, parent_id || issue_id)
      end
    end
  end

  # -- Helpers --

  defp count_children(state, parent_id) do
    state.deps_by_target
    |> Map.get(parent_id, [])
    |> Enum.count(&(&1.type in @parent_types))
  end

  defp orphan?(issue, child_ids) do
    issue.issue_type != "epic" && !MapSet.member?(child_ids, issue.id)
  end

  defp search_epics(state, types, status, query) do
    if :epic in types do
      state.issues_by_id
      |> Map.values()
      |> Enum.filter(&(&1.issue_type == "epic"))
      |> filter_by_status(status)
      |> filter_by_query(query)
      |> Enum.map(&Map.put(&1, :task_count, count_children(state, &1.id)))
    else
      []
    end
  end

  defp search_orphans(state, types, status, query) do
    if :orphan in types do
      state.issues_by_id
      |> Map.values()
      |> Enum.filter(&orphan?(&1, state.child_ids))
      |> filter_by_status(status)
      |> filter_by_query(query)
      |> Enum.map(&Map.put(&1, :task_count, 0))
    else
      []
    end
  end

  defp filter_by_status(issues, :all), do: issues
  defp filter_by_status(issues, :open), do: Enum.filter(issues, &(&1.status == "open"))
  defp filter_by_status(issues, :closed), do: Enum.filter(issues, &(&1.status == "closed"))
  defp filter_by_status(issues, _), do: Enum.filter(issues, &(&1.status == "open"))

  defp filter_by_query(issues, nil), do: issues

  defp filter_by_query(issues, query) do
    down = String.downcase(query)

    Enum.filter(issues, fn issue ->
      String.contains?(String.downcase(issue.id || ""), down) ||
        String.contains?(String.downcase(issue.title || ""), down) ||
        String.contains?(String.downcase(issue.description || ""), down)
    end)
  end

  defp sort_by_priority_created(issues) do
    Enum.sort_by(issues, &{&1.priority, neg_datetime(&1.created_at)})
  end

  defp sort_results(issues, :priority, :asc), do: Enum.sort_by(issues, & &1.priority)
  defp sort_results(issues, :priority, :desc), do: Enum.sort_by(issues, & &1.priority, :desc)

  defp sort_results(issues, :created_at, :asc),
    do: Enum.sort_by(issues, & &1.created_at, NaiveDateTime)

  defp sort_results(issues, :created_at, :desc),
    do: Enum.sort_by(issues, & &1.created_at, {:desc, NaiveDateTime})

  defp sort_results(issues, _, _), do: sort_by_priority_created(issues)

  defp neg_datetime(nil), do: 0

  defp neg_datetime(%NaiveDateTime{} = ndt) do
    {seconds, _microseconds} = NaiveDateTime.to_gregorian_seconds(ndt)
    -seconds
  end

  defp normalize_query(nil), do: nil

  defp normalize_query(q) when is_binary(q) do
    trimmed = String.trim(q)
    if trimmed == "", do: nil, else: trimmed
  end

  defp find_parent_id(state, issue_id) do
    state.deps_by_issue
    |> Map.get(issue_id, [])
    |> Enum.find(&(&1.type in @parent_types))
    |> case do
      nil -> nil
      dep -> dep.depends_on_id
    end
  end

  defp build_sibling_graph(state, parent_id) do
    siblings =
      state.deps_by_target
      |> Map.get(parent_id, [])
      |> Enum.filter(&(&1.type in @parent_types))
      |> Enum.map(& &1.issue_id)
      |> Enum.map(&Map.get(state.issues_by_id, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&{&1.priority, &1.created_at})

    if length(siblings) < 2 do
      {:ok, nil}
    else
      sibling_ids = MapSet.new(siblings, & &1.id)

      edges =
        state.all_deps
        |> Enum.filter(fn dep ->
          dep.type not in @parent_types &&
            MapSet.member?(sibling_ids, dep.issue_id) &&
            MapSet.member?(sibling_ids, dep.depends_on_id)
        end)
        |> Enum.map(fn dep ->
          %{from: dep.issue_id, to: dep.depends_on_id, type: dep.type}
        end)

      nodes =
        Enum.map(siblings, fn s ->
          %{
            id: s.id,
            title: s.title,
            status: s.status,
            priority: s.priority,
            issue_type: s.issue_type
          }
        end)

      {:ok, %{nodes: nodes, edges: edges}}
    end
  end
end
