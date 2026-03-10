defmodule SpotterWeb.ProjectHelpers do
  @moduledoc "Shared project selection helpers for sidebar and LiveViews."

  def parse_project_id("all"), do: nil
  def parse_project_id(nil), do: nil
  def parse_project_id(""), do: nil
  def parse_project_id(id), do: id

  def first_project_id([%{id: id} | _]), do: id
  def first_project_id([%{project_id: id} | _]), do: id
  def first_project_id(_), do: nil

  def normalize_project_id(projects, project_id) do
    first = first_project_id(projects)

    case project_id do
      nil -> first
      _ -> if project_exists?(projects, project_id), do: project_id, else: first
    end
  end

  def project_exists?(projects, project_id) do
    Enum.any?(projects, fn
      %{id: id} -> id == project_id
      %{project_id: id} -> id == project_id
    end)
  end
end
