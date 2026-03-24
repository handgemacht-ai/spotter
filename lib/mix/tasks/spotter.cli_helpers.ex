defmodule Mix.Tasks.Spotter.CliHelpers do
  @moduledoc false

  @doc "Load config and start only the Repo (no Oban, no PubSub, no Endpoint)."
  def start_app_without_server do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, _} = Application.ensure_all_started(:ash)

    case Spotter.Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
