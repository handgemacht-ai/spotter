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
end
