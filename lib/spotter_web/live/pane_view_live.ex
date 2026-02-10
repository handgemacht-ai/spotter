defmodule SpotterWeb.PaneViewLive do
  use Phoenix.LiveView

  alias Spotter.Services.Tmux

  @impl true
  def mount(%{"pane_id" => pane_num}, _session, socket) do
    pane_id = Tmux.num_to_pane_id(pane_num)

    {cols, rows} =
      case Tmux.list_panes() do
        {:ok, panes} ->
          case Enum.find(panes, &(&1.pane_id == pane_id)) do
            %{pane_width: w, pane_height: h} -> {w, h}
            _ -> {80, 24}
          end

        _ ->
          {80, 24}
      end

    {:ok, assign(socket, pane_id: pane_id, cols: cols, rows: rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="header">
      <a href="/">&larr; Back</a>
      <span>Pane: {@pane_id} ({@cols}x{@rows})</span>
    </div>
    <div style="overflow-x: auto; padding: 1rem;">
      <div style="display: inline-block; min-width: 100%;">
        <div
          id="terminal"
          phx-hook="Terminal"
          data-pane-id={@pane_id}
          data-cols={@cols}
          data-rows={@rows}
          phx-update="ignore"
          style="display: inline-block;"
        >
        </div>
      </div>
    </div>
    """
  end
end
