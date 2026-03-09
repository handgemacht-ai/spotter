defmodule Spotter.Beads.DoltConfig do
  @moduledoc """
  Resolves Dolt connection configuration for beads databases.

  Configuration is read from application env under `:spotter, Spotter.Beads.DoltConfig`.
  Falls back to the bd CLI's Dolt server defaults (port 14065, root user, no password).
  """

  @default_host "127.0.0.1"
  @default_port 14_065
  @default_username "root"
  @default_password ""

  @doc """
  Returns MyXQL connection options for the given project's beads database.

  The database name follows the bd convention: `beads_<project_name>`.
  """
  @spec connection_opts(String.t()) :: keyword()
  def connection_opts(project_name) when is_binary(project_name) do
    config = Application.get_env(:spotter, __MODULE__, [])

    [
      hostname: Keyword.get(config, :hostname, @default_host),
      port: Keyword.get(config, :port, @default_port),
      username: Keyword.get(config, :username, @default_username),
      password: Keyword.get(config, :password, @default_password),
      database: database_name(project_name)
    ]
  end

  @doc """
  Returns the Dolt database name for a project.
  """
  @spec database_name(String.t()) :: String.t()
  def database_name(project_name) when is_binary(project_name) do
    "beads_#{project_name}"
  end
end
