defmodule SpotterWeb.ProjectContext do
  @moduledoc "LiveView on_mount hook that sets current_project_id from URL query params."

  import Phoenix.Component, only: [assign: 3]

  alias SpotterWeb.ProjectHelpers

  def on_mount(:default, params, _session, socket) do
    {projects, current_project_id} =
      ProjectHelpers.load_and_resolve(params["project"] || params["project_id"])

    {:cont,
     socket
     |> assign(:projects, projects)
     |> assign(:current_project_id, current_project_id)}
  end
end
