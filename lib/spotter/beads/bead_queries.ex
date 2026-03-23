defmodule Spotter.Beads.BeadQueries do
  @moduledoc """
  High-level query interface for bead data, returning typed structs.

  Wraps `Spotter.Beads.Client` raw MyXQL queries and converts results
  into `Spotter.Beads.BeadStructs` structs.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Beads.BeadStructs
  alias Spotter.Beads.Client

  @doc """
  Returns a list of project summaries with epic counts.
  """
  @spec project_summaries() ::
          {:ok, [%{project: String.t(), epic_count: integer()}]} | {:error, atom()}
  def project_summaries do
    Tracer.with_span "spotter.beads.queries.project_summaries" do
      case Client.epic_counts_by_project() do
        {:ok, counts_map} ->
          summaries =
            counts_map
            |> Enum.map(fn {project, count} -> %{project: project, epic_count: count} end)
            |> Enum.sort_by(& &1.project)

          {:ok, summaries}

        {:error, reason} = err ->
          Tracer.set_status(:error, inspect(reason))
          err
      end
    end
  end

  @doc """
  Lists epics for a project as Epic structs.
  """
  @spec list_epics(String.t(), :all | :open | :closed) ::
          {:ok, [BeadStructs.Epic.t()]} | {:error, atom()}
  def list_epics(project, filter \\ :all) do
    Tracer.with_span "spotter.beads.queries.list_epics" do
      Tracer.set_attribute("spotter.beads.project", project)
      Tracer.set_attribute("spotter.beads.filter", Atom.to_string(filter))

      case Client.list_epics(project, filter) do
        {:ok, rows} ->
          {:ok, BeadStructs.Epic.from_rows(rows)}

        {:error, reason} = err ->
          Tracer.set_status(:error, inspect(reason))
          err
      end
    end
  end

  @doc """
  Fetches a single epic by ID as an Epic struct.
  """
  @spec get_epic(String.t(), String.t()) ::
          {:ok, BeadStructs.Epic.t()} | {:error, :not_found | atom()}
  def get_epic(project, epic_id) do
    Tracer.with_span "spotter.beads.queries.get_epic" do
      Tracer.set_attribute("spotter.beads.project", project)
      Tracer.set_attribute("spotter.beads.epic_id", epic_id)

      case Client.get_issue(project, epic_id) do
        {:ok, row} ->
          {:ok, BeadStructs.Epic.from_row(row)}

        {:error, reason} = err ->
          Tracer.set_status(:error, inspect(reason))
          err
      end
    end
  end

  @doc """
  Lists child tasks of a parent issue as Task structs.
  """
  @spec list_children(String.t(), String.t()) ::
          {:ok, [BeadStructs.Task.t()]} | {:error, atom()}
  def list_children(project, parent_id) do
    Tracer.with_span "spotter.beads.queries.list_children" do
      Tracer.set_attribute("spotter.beads.project", project)
      Tracer.set_attribute("spotter.beads.parent_id", parent_id)

      case Client.get_children(project, parent_id) do
        {:ok, rows} ->
          {:ok, BeadStructs.Task.from_rows(rows)}

        {:error, reason} = err ->
          Tracer.set_status(:error, inspect(reason))
          err
      end
    end
  end

  @doc """
  Lists dependencies for an issue as Dependency structs.
  """
  @spec list_dependencies(String.t(), String.t()) ::
          {:ok, [BeadStructs.Dependency.t()]} | {:error, atom()}
  def list_dependencies(project, issue_id) do
    Tracer.with_span "spotter.beads.queries.list_dependencies" do
      Tracer.set_attribute("spotter.beads.project", project)
      Tracer.set_attribute("spotter.beads.issue_id", issue_id)

      case Client.get_dependencies(project, issue_id) do
        {:ok, rows} ->
          {:ok, BeadStructs.Dependency.from_rows(rows)}

        {:error, reason} = err ->
          Tracer.set_status(:error, inspect(reason))
          err
      end
    end
  end

  @doc """
  Lists non-epic issues with no parent dependency (orphans).
  """
  @spec list_orphan_issues(String.t(), :all | :open | :closed) ::
          {:ok, [BeadStructs.Task.t()]} | {:error, atom()}
  def list_orphan_issues(project, filter \\ :all) do
    Tracer.with_span "spotter.beads.queries.list_orphan_issues" do
      Tracer.set_attribute("spotter.beads.project", project)
      Tracer.set_attribute("spotter.beads.filter", Atom.to_string(filter))

      case Client.list_orphan_issues(project, filter) do
        {:ok, rows} ->
          {:ok, BeadStructs.Task.from_rows(rows)}

        {:error, reason} = err ->
          Tracer.set_status(:error, inspect(reason))
          err
      end
    end
  end

  @doc """
  Searches beads with text search, status filtering, sort, and direction.

  Returns a flat list of Epic structs (epics with task_count, orphans with task_count=0).
  See `Client.search_beads/2` for available options.
  """
  @spec search_beads(String.t(), keyword()) ::
          {:ok, [BeadStructs.Epic.t()]} | {:error, atom()}
  def search_beads(project, opts \\ []) do
    Tracer.with_span "spotter.beads.queries.search_beads" do
      Tracer.set_attribute("spotter.beads.project", project)

      case Client.search_beads(project, opts) do
        {:ok, rows} ->
          {:ok, BeadStructs.Epic.from_rows(rows)}

        {:error, reason} = err ->
          Tracer.set_status(:error, inspect(reason))
          err
      end
    end
  end

  @doc """
  Fetches a single bead by ID. Delegates to `get_epic/2` since all
  issue types share the same underlying query and struct shape.
  """
  defdelegate get_bead(project, bead_id), to: __MODULE__, as: :get_epic
end
