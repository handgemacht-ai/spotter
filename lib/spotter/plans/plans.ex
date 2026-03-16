defmodule Spotter.Plans do
  @moduledoc """
  Public API for accessing project plans.

  Aggregates results from configured plan sources (see `Spotter.Plans.PlanSource`).
  Sources are tried in order; for single-result queries (`get_plan/2`, etc.),
  the first successful response wins.

  ## Configuration

      config :spotter, Spotter.Plans,
        sources: [Spotter.Plans.BeadsSource]
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Plans.BeadsSource

  @doc """
  Lists all projects across all configured sources.

  Merges results via `flat_map` — duplicates are possible if multiple
  sources serve the same project.
  """
  @spec list_projects() :: {:ok, [Spotter.Plans.PlanSource.project_summary()]}
  def list_projects do
    Tracer.with_span "spotter.plans.list_projects" do
      results =
        Enum.flat_map(sources(), fn source ->
          case source.list_projects() do
            {:ok, projects} -> projects
            {:error, _} -> []
          end
        end)

      {:ok, results}
    end
  end

  @doc """
  Lists plans for a project. Tries sources in order, returns first success.
  """
  @spec list_plans(String.t(), :all | :open | :closed) ::
          {:ok, [Spotter.Plans.PlanSource.plan()]} | {:error, term()}
  def list_plans(project, filter \\ :all) do
    Tracer.with_span "spotter.plans.list_plans" do
      Tracer.set_attribute("plans.project", project)
      Tracer.set_attribute("plans.filter", to_string(filter))
      first_success(sources(), fn source -> source.list_plans(project, filter) end)
    end
  end

  @doc """
  Gets a single plan by project and plan ID. Tries sources in order, returns first success.
  """
  @spec get_plan(String.t(), String.t()) ::
          {:ok, Spotter.Plans.PlanSource.plan()} | {:error, term()}
  def get_plan(project, plan_id) do
    Tracer.with_span "spotter.plans.get_plan" do
      Tracer.set_attribute("plans.project", project)
      Tracer.set_attribute("plans.plan_id", plan_id)
      first_success(sources(), fn source -> source.get_plan(project, plan_id) end)
    end
  end

  @doc """
  Lists children of a plan. Tries sources in order, returns first success.
  """
  @spec list_children(String.t(), String.t()) ::
          {:ok, [Spotter.Plans.PlanSource.task()]} | {:error, term()}
  def list_children(project, plan_id) do
    Tracer.with_span "spotter.plans.list_children" do
      Tracer.set_attribute("plans.project", project)
      Tracer.set_attribute("plans.plan_id", plan_id)
      first_success(sources(), fn source -> source.list_children(project, plan_id) end)
    end
  end

  @doc """
  Lists dependencies of a plan. Tries sources in order, returns first success.
  """
  @spec list_dependencies(String.t(), String.t()) ::
          {:ok, [Spotter.Plans.PlanSource.dependency()]} | {:error, term()}
  def list_dependencies(project, plan_id) do
    Tracer.with_span "spotter.plans.list_dependencies" do
      Tracer.set_attribute("plans.project", project)
      Tracer.set_attribute("plans.plan_id", plan_id)
      first_success(sources(), fn source -> source.list_dependencies(project, plan_id) end)
    end
  end

  @doc """
  Gets a single bead by project and bead ID. Delegates to `get_plan/2`.
  """
  def get_bead(project, bead_id), do: get_plan(project, bead_id)

  defp sources do
    Application.get_env(:spotter, __MODULE__, [])
    |> Keyword.get(:sources, [BeadsSource])
  end

  # Returns first {:ok, _} from any source. Note: {:ok, []} is considered a
  # success and stops iteration. Sources must return {:error, _} to signal
  # "not my project" so subsequent sources are tried.
  defp first_success(sources, fun) do
    Enum.find_value(sources, {:error, :not_found}, fn source ->
      case fun.(source) do
        {:ok, _} = ok -> ok
        {:error, _} -> nil
      end
    end)
  end
end
