defmodule SpotterWeb.Plugs.ProjectContext do
  @moduledoc "Loads projects and resolves current project from ?project= query param."

  @behaviour Plug

  import Plug.Conn

  alias SpotterWeb.ProjectHelpers

  def init(opts), do: opts

  def call(conn, _opts) do
    {projects, current_project_id} =
      ProjectHelpers.load_and_resolve(
        conn.query_params["project"] || conn.query_params["project_id"]
      )

    conn
    |> assign(:projects, projects)
    |> assign(:current_project_id, current_project_id)
  end
end
