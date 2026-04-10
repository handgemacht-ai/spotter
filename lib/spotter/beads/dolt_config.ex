defmodule Spotter.Beads.DoltConfig do
  @moduledoc """
  Resolves project configuration for beads data.

  Configuration is read from application env under `:spotter, Spotter.Beads.JsonlStore`.
  Maps project names to their `.beads/backup/` directory paths.
  """

  @doc """
  Returns the display/tracing database name for a project.

  Checks `database_mapping` config first, falls back to the project name as-is.
  """
  @spec database_name(String.t()) :: String.t()
  def database_name(project_name) when is_binary(project_name) do
    mapping =
      Application.get_env(:spotter, __MODULE__, [])
      |> Keyword.get(:database_mapping, %{})

    Map.get(mapping, project_name, project_name)
  end
end
