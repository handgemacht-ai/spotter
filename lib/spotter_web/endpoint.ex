defmodule SpotterWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :spotter

  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave, allow_remote_access: true
  end

  plug Plug.RequestId

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug SpotterWeb.AshJsonApiRouter
end
