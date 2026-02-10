defmodule SpotterWeb.AshJsonApiRouter do
  @moduledoc """
  JSON API router for Ash-powered resources.
  """
  use AshJsonApi.Router,
    domains: [Spotter.Transcripts],
    open_api: "/open_api"
end
