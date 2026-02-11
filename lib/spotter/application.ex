defmodule Spotter.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Spotter.PubSub},
      Spotter.Services.SessionRegistry,
      Spotter.Services.ReviewSessionRegistry,
      Spotter.Repo,
      {Oban,
       AshOban.config(
         Application.fetch_env!(:spotter, :ash_domains),
         Application.fetch_env!(:spotter, Oban)
       )},
      SpotterWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Spotter.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
