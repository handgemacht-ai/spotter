defmodule SpotterWeb.Layouts do
  use Phoenix.Component

  embed_templates("layouts/*")

  defp project_display_name(projects, current_project_id) do
    case Enum.find(projects, fn p -> p.id == current_project_id end) do
      %{name: name} -> name
      nil -> "No projects"
    end
  end
end
