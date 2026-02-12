defmodule Spotter.Services.ReviewCounts do
  @moduledoc "Aggregation service for open-review counts per project and sidebar badge."

  alias Spotter.Transcripts.{Annotation, Project, Session}

  require Ash.Query

  @doc """
  Returns a list of all projects with their open annotation counts,
  sorted by project name ascending.

  Each element has shape:
    %{project_id: uuid, project_name: string, open_count: non_neg_integer()}
  """
  def list_project_open_counts do
    projects = Project |> Ash.Query.sort(name: :asc) |> Ash.read!()

    open_annotations =
      Annotation
      |> Ash.Query.filter(state == :open)
      |> Ash.Query.select([:session_id])
      |> Ash.read!()

    session_ids = open_annotations |> Enum.map(& &1.session_id) |> Enum.uniq()

    sessions_by_id =
      if session_ids == [] do
        %{}
      else
        Session
        |> Ash.Query.filter(id in ^session_ids)
        |> Ash.Query.select([:id, :project_id])
        |> Ash.read!()
        |> Map.new(&{&1.id, &1})
      end

    counts_by_project =
      open_annotations
      |> Enum.map(fn a -> get_in(sessions_by_id, [a.session_id, Access.key(:project_id)]) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    Enum.map(projects, fn project ->
      %{
        project_id: project.id,
        project_name: project.name,
        open_count: Map.get(counts_by_project, project.id, 0)
      }
    end)
  rescue
    _ -> []
  end

  @doc """
  Returns the total number of open annotations across all projects.
  """
  def total_open_count do
    list_project_open_counts()
    |> Enum.map(& &1.open_count)
    |> Enum.sum()
  rescue
    _ -> 0
  end
end
