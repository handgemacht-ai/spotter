defmodule SpotterWeb.ProjectContext do
  @moduledoc "LiveView on_mount hook that sets current_project_id from URL query params."

  import Phoenix.Component, only: [assign: 3]

  alias SpotterWeb.ProjectHelpers

  def on_mount(:default, params, _session, socket) do
    projects =
      case Spotter.Transcripts.Project |> Ash.Query.sort(name: :asc) |> Ash.read() do
        {:ok, list} -> list
        {:error, _} -> []
      end

    raw_id = params["project"] || params["project_id"]

    current_project_id =
      ProjectHelpers.normalize_project_id(projects, ProjectHelpers.parse_project_id(raw_id))

    {:cont,
     socket
     |> assign(:projects, projects)
     |> assign(:current_project_id, current_project_id)}
  end
end
