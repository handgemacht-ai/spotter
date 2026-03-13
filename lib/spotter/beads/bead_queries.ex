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

        {:error, _} = err ->
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
        {:ok, rows} -> {:ok, BeadStructs.Epic.from_rows(rows)}
        {:error, _} = err -> err
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
        {:ok, row} -> {:ok, BeadStructs.Epic.from_row(row)}
        {:error, _} = err -> err
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
        {:ok, rows} -> {:ok, BeadStructs.Task.from_rows(rows)}
        {:error, _} = err -> err
      end
    end
  end
end
