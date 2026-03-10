defmodule SpotterWeb.Plugs.ProjectContext do
  @moduledoc "Loads projects and resolves current project from ?project= query param."

  @behaviour Plug

  import Plug.Conn

  alias SpotterWeb.ProjectHelpers

  def init(opts), do: opts

  def call(conn, _opts) do
    projects =
      case Spotter.Transcripts.Project |> Ash.Query.sort(name: :asc) |> Ash.read() do
        {:ok, list} -> list
        {:error, _} -> []
      end

    raw_id = conn.query_params["project"] || conn.query_params["project_id"]

    current_project_id =
      ProjectHelpers.normalize_project_id(projects, ProjectHelpers.parse_project_id(raw_id))

    conn
    |> assign(:projects, projects)
    |> assign(:current_project_id, current_project_id)
  end
end
