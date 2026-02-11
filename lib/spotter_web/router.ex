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
    post("/hooks/tool-call", HooksController, :tool_call)
    post("/hooks/commit-event", HooksController, :commit_event)

    get("/review-context/:token", ReviewContextController, :show)
  end

  scope "/", SpotterWeb do
    pipe_through(:browser)

    live("/", PaneListLive)
    live("/history", HistoryLive)
    live("/debug", DebugTerminalLive)
    live("/sessions/:session_id", SessionLive)
    live("/sessions/:session_id/agents/:agent_id", SubagentLive)
    live("/projects/:project_id/review", ProjectReviewLive)
  end
end
