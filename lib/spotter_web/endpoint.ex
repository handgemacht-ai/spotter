defmodule SpotterWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :spotter

  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave, allow_remote_access: true
  end

  socket "/live", Phoenix.LiveView.Socket
  socket "/socket", SpotterWeb.UserSocket

  plug Plug.Static,
    at: "/",
    from: :spotter,
    gzip: false,
    only: ~w(assets)

  plug Plug.RequestId

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.Session,
    store: :cookie,
    key: "_spotter_key",
    signing_salt: "spotter_salt"

  plug SpotterWeb.Router
end
