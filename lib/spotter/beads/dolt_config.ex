defmodule Spotter.Beads.DoltConfig do
  @moduledoc """
  Resolves Dolt connection configuration for beads databases.

  Configuration is read from application env under `:spotter, Spotter.Beads.DoltConfig`.
  Falls back to the shared workspace Dolt server defaults (port 3307, root user, no password).
  """

  @default_host "127.0.0.1"
  @default_port 3307
  @default_username "root"
  @default_password ""

  @doc """
  Returns MyXQL connection options for the given project's beads database.

  The database name matches the project name directly.
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

  Checks `database_mapping` config first, falls back to the project name as-is.
  Example config:
      config :spotter, Spotter.Beads.DoltConfig,
        database_mapping: %{"spotter" => "beads_spotter"}
  """
  @spec database_name(String.t()) :: String.t()
  def database_name(project_name) when is_binary(project_name) do
    mapping =
      Application.get_env(:spotter, __MODULE__, [])
      |> Keyword.get(:database_mapping, %{})

    Map.get(mapping, project_name, project_name)
  end
end
