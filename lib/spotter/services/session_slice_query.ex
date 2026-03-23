defmodule Spotter.Services.SessionSliceQuery do
  @moduledoc "Query service for SessionSlice lookups used by the dashboard and CLI."

  require Ash.Query
  require OpenTelemetry.Tracer

  alias Spotter.Transcripts.SessionSlice

  @doc "List slices for a project, preloaded with session, ordered by inserted_at desc."
  def list_for_project(project_id) do
    OpenTelemetry.Tracer.with_span "spotter.session_slice_query.list_for_project",
                                   %{attributes: %{"project_id" => project_id}} do
      SessionSlice
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.load(:session)
      |> Ash.read()
    end
  end

  @doc "Count slices grouped by project_id. Returns a map of project_id => count."
  def count_by_project do
    OpenTelemetry.Tracer.with_span "spotter.session_slice_query.count_by_project" do
      case Ash.read(SessionSlice) do
        {:ok, slices} ->
          counts =
            slices
            |> Enum.group_by(& &1.project_id)
            |> Map.new(fn {pid, group} -> {pid, length(group)} end)

          {:ok, counts}

        {:error, _} = err ->
          err
      end
    end
  end
end
