defmodule Spotter.Plans.BeadsSource do
  @moduledoc """
  PlanSource implementation backed by Dolt beads databases.

  Pure delegation to `Spotter.Beads.BeadQueries` — no additional logic,
  caching, or error transformation. OTEL spans are handled by BeadQueries.
  """

  @behaviour Spotter.Plans.PlanSource

  alias Spotter.Beads.BeadQueries

  @impl true
  def list_projects do
    case BeadQueries.project_summaries() do
      {:ok, summaries} ->
        {:ok, Enum.map(summaries, fn s -> %{project: s.project, plan_count: s.epic_count} end)}

      error ->
        error
    end
  end

  @impl true
  def list_plans(project, filter), do: BeadQueries.list_epics(project, filter)

  @impl true
  def get_plan(project, plan_id), do: BeadQueries.get_epic(project, plan_id)

  @impl true
  def list_children(project, plan_id), do: BeadQueries.list_children(project, plan_id)
end
