defmodule SpotterWeb.ProjectHelpers do
  @moduledoc "Shared project selection helpers for sidebar and LiveViews."

  def parse_project_id("all"), do: nil
  def parse_project_id(nil), do: nil
  def parse_project_id(""), do: nil
  def parse_project_id(id), do: id

  def first_project_id([%{id: id} | _]), do: id
  def first_project_id([%{project_id: id} | _]), do: id
  def first_project_id(_), do: nil

  def normalize_project_id(projects, nil), do: first_project_id(projects)

  def normalize_project_id(projects, project_id) do
    if project_exists?(projects, project_id), do: project_id, else: first_project_id(projects)
  end

  def project_exists?(projects, project_id) do
    Enum.any?(projects, fn
      %{id: id} -> id == project_id
      %{project_id: id} -> id == project_id
      _ -> false
    end)
  end

  @doc "Loads sorted projects and resolves current project from a raw param value."
  def load_and_resolve(raw_id) do
    projects =
      case Spotter.Transcripts.Project |> Ash.Query.sort(name: :asc) |> Ash.read() do
        {:ok, list} -> list
        {:error, _} -> []
      end

    current_project_id = normalize_project_id(projects, parse_project_id(raw_id))
    {projects, current_project_id}
  end
end
