defmodule SpotterWeb.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {SpotterWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", SpotterWeb do
    pipe_through(:api)

    post("/hooks/session-start", SessionHookController, :session_start)
    post("/hooks/file-snapshot", HooksController, :file_snapshot)
  end

  scope "/", SpotterWeb do
    pipe_through(:browser)

    live("/", PaneListLive)
    live("/debug", DebugTerminalLive)
    live("/sessions/:session_id", SessionLive)
  end
end
