defmodule SpotterWeb.PaneListLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="dashboard-root" id="dashboard-root">
      <div class="page-header">
        <h1>Dashboard</h1>
      </div>

      <div class="empty-state">
        No ongoing sessions.
      </div>
    </div>
    """
  end
end
