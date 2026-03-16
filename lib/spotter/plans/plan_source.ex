defmodule Spotter.Plans.PlanSource do
  @moduledoc """
  Behaviour for plan data sources.

  Implementations provide access to project plans (epics) and their
  child tasks from various backends (Dolt beads, local files, etc.).
  """

  alias Spotter.Beads.BeadStructs

  @type plan :: BeadStructs.Epic.t()
  @type task :: BeadStructs.Task.t()
  @type dependency :: BeadStructs.Dependency.t()
  @type project_summary :: %{project: String.t(), plan_count: integer()}

  @callback list_projects() :: {:ok, [project_summary()]} | {:error, term()}
  @callback list_plans(project :: String.t(), filter :: :all | :open | :closed) ::
              {:ok, [plan()]} | {:error, term()}
  @callback get_plan(project :: String.t(), plan_id :: String.t()) ::
              {:ok, plan()} | {:error, term()}
  @callback list_children(project :: String.t(), plan_id :: String.t()) ::
              {:ok, [task()]} | {:error, term()}
  @callback list_dependencies(project :: String.t(), plan_id :: String.t()) ::
              {:ok, [dependency()]} | {:error, term()}
end
