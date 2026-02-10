defmodule SpotterWeb.PaneListLive do
  use Phoenix.LiveView

  alias Spotter.Services.Tmux

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, panes: [], claude_panes: [], loading: true) |> load_panes()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_panes(socket)}
  end

  defp load_panes(socket) do
    {claude_panes, other_panes} =
      case Tmux.list_panes() do
        {:ok, panes} ->
          Enum.split_with(panes, fn p ->
            p.pane_current_command in ["claude", "claude-code"] or
              String.contains?(p.pane_title, "claude")
          end)

        {:error, _} ->
          {[], []}
      end

    assign(socket, panes: other_panes, claude_panes: claude_panes, loading: false)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 1rem;">
        <h1>Spotter - Tmux Panes</h1>
        <button phx-click="refresh">Refresh</button>
      </div>

      <%= if @claude_panes != [] do %>
        <h2 style="color: #d4a574; margin-bottom: 0.5rem;">Claude Code Sessions</h2>
        <.pane_table panes={@claude_panes} badge="claude" />
      <% end %>

      <%= if @panes != [] do %>
        <h2 style="margin-top: 1.5rem; margin-bottom: 0.5rem;">Other Panes</h2>
        <.pane_table panes={@panes} badge="other" />
      <% end %>

      <%= if @panes == [] and @claude_panes == [] and not @loading do %>
        <div class="empty-state">
          <p>No tmux panes found.</p>
          <p style="margin-top: 0.5rem;">Make sure tmux is running with active sessions.</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp pane_table(assigns) do
    ~H"""
    <table>
      <thead>
        <tr>
          <th>Pane ID</th>
          <th>Session</th>
          <th>Window</th>
          <th>Command</th>
          <th>Size</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={pane <- @panes}>
          <td><span class={"badge badge-#{@badge}"}>{pane.pane_id}</span></td>
          <td>{pane.session_name}</td>
          <td>{pane.window_index}:{pane.pane_index}</td>
          <td>{pane.pane_current_command}</td>
          <td>{pane.pane_width}x{pane.pane_height}</td>
          <td><a href={"/panes/#{URI.encode(pane.pane_id)}"}>Connect</a></td>
        </tr>
      </tbody>
    </table>
    """
  end
end
