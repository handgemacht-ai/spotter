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
    plug(SpotterWeb.Plugs.ProjectContext)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api" do
    forward("/mcp", SpotterWeb.SpotterMcpPlug)
  end

  scope "/api", SpotterWeb do
    pipe_through(:api)

    get("/search", SearchController, :index)

    post("/hooks/session-start", SessionHookController, :session_start)
    post("/hooks/session-end", SessionHookController, :session_end)
    post("/hooks/file-snapshot", HooksController, :file_snapshot)
    post("/hooks/tool-call", HooksController, :tool_call)
    post("/hooks/commit-event", HooksController, :commit_event)
    post("/hooks/raw-event", HooksController, :raw_event)
    post("/hooks/waiting-summary", SessionHookController, :waiting_summary)
  end

  scope "/", SpotterWeb do
    pipe_through(:browser)

    live("/", DashboardLive)

    live_session :project_scoped, on_mount: [SpotterWeb.ProjectContext] do
      live("/history", HistoryLive)
      live("/reviews", ReviewsLive)
      live("/retros", RetrosLive)
      live("/sessions", SessionsLive)
      live("/file-metrics", FileMetricsLive)
      live("/telemetry/commands", ShellTelemetryLive)
      live("/telemetry/instructions", InstructionsTelemetryLive)
    end

    live("/history/commits/:commit_id", CommitDetailLive)
    live("/sessions/:session_id", SessionLive)
    live("/sessions/:session_id/agents/:agent_id", SubagentLive)
    get("/projects/:project_id/review", ReviewsRedirectController, :show)
    live("/projects/:project_id/files/*relative_path", FileDetailLive)
  end
end
