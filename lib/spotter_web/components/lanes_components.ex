defmodule SpotterWeb.LanesComponents do
  @moduledoc """
  HEEx components for parallel transcript lanes view.

  Renders agent transcripts as side-by-side independently scrollable columns,
  each piped through the TranscriptRenderer pipeline for full-fidelity display.
  """
  use Phoenix.Component

  @lane_colors ~w(--lane-lead --lane-agent-1 --lane-agent-2 --lane-agent-3 --lane-agent-4 --lane-agent-5 --lane-agent-6)

  @doc "Returns the CSS variable name for a given lane index."
  def lane_color(index), do: Enum.at(@lane_colors, index, "--lane-agent-6")

  @doc """
  Renders the parallel lanes panel with independently scrollable lane columns.

  ## Assigns

    * `:lanes` (required) - list of lane maps with agent_name, session, messages, started_at, ended_at
    * `:active_lane_index` - index of the active lane for responsive tab view (default 0)
  """
  attr(:lanes, :list, required: true)
  attr(:active_lane_index, :integer, default: 0)

  def lanes_panel(assigns) do
    ~H"""
    <div id="lanes-scroll" class="lanes-container" data-testid="lanes-panel">
      <div
        :if={@lanes != []}
        id="lane-tab-bar"
        class="lanes-tab-bar"
        role="tablist"
        phx-hook="LaneDrag"
        phx-update="replace"
      >
        <button
          :for={{lane, idx} <- Enum.with_index(@lanes)}
          class={"lanes-tab#{if idx == @active_lane_index, do: " is-active", else: ""}"}
          data-testid={"lane-tab-#{sanitize_agent_name(lane.agent_name)}"}
          data-lane-session-id={lane.session && lane.session.session_id}
          phx-click="switch_lane"
          phx-value-index={idx}
          role="tab"
          aria-selected={"#{idx == @active_lane_index}"}
        >
          <span style={"width: 6px; height: 6px; border-radius: 50%; display: inline-block; background: var(#{lane_color(idx)})"}></span>
          <%= lane.agent_name %>
        </button>
      </div>
      <div class="lanes-columns-row">
        <.lane_column
          :for={{lane, idx} <- Enum.with_index(@lanes)}
          lane={lane}
          color={lane_color(idx)}
          active={idx == @active_lane_index}
          role="tabpanel"
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a sticky lane header with agent name, colored dot, duration, and message count.

  ## Assigns

    * `:lane` (required) - lane map with agent_name, started_at, ended_at, messages
    * `:color` (required) - CSS variable name (e.g. "--lane-lead")
  """
  attr(:lane, :map, required: true)
  attr(:color, :string, required: true)

  def lane_header(assigns) do
    assigns =
      assign(assigns, :duration, format_duration(assigns.lane.started_at, assigns.lane.ended_at))

    assigns = assign(assigns, :msg_count, length(assigns.lane.messages))

    ~H"""
    <div class="lanes-header" data-testid="lane-header">
      <span style={"width: 8px; height: 8px; border-radius: 50%; display: inline-block; background: var(#{@color})"}></span>
      <span data-testid="lane-name" style="font-weight: 600;"><%= @lane.agent_name %></span>
      <span data-testid="lane-duration" style="font-size: var(--text-xs); color: var(--text-secondary);"><%= @duration %></span>
      <span style="font-size: var(--text-xs); color: var(--text-secondary);"><%= @msg_count %></span>
    </div>
    """
  end

  @doc """
  Renders a single lane column with header and message entries.

  ## Assigns

    * `:lane` (required) - lane map with agent_name, messages, started_at, ended_at
    * `:color` (required) - CSS variable name (e.g. "--lane-agent-1")
    * `:active` - whether this lane is the active tab (default false)
    * `:role` - ARIA role for the container (default nil)
  """
  attr(:lane, :map, required: true)
  attr(:color, :string, required: true)
  attr(:active, :boolean, default: false)
  attr(:role, :string, default: nil)

  def lane_column(assigns) do
    rendered = Map.get(assigns.lane, :rendered_lines, [])
    panel_id = "lane-transcript-#{sanitize_agent_name(assigns.lane.agent_name)}"

    assigns =
      assigns
      |> assign(:rendered_lines, rendered)
      |> assign(:panel_id, panel_id)

    ~H"""
    <div
      class={"lanes-column#{if @active, do: " is-active", else: ""}"}
      data-testid={"lane-column-#{sanitize_agent_name(@lane.agent_name)}"}
      style={"border-left: 3px solid var(#{@color}); overflow-y: auto;"}
      role={@role}
    >
      <.lane_header lane={@lane} color={@color} />
      <%= if @rendered_lines != [] do %>
        <SpotterWeb.TranscriptComponents.transcript_panel
          rendered_lines={@rendered_lines}
          panel_id={@panel_id}
          empty_message="No messages."
        />
      <% else %>
        <p class="transcript-empty" data-testid="transcript-empty">No messages.</p>
      <% end %>
    </div>
    """
  end

  defp format_duration(started_at, ended_at)
       when not is_nil(started_at) and not is_nil(ended_at) do
    diff = max(DateTime.diff(ended_at, started_at, :second), 0)
    hours = div(diff, 3600)
    minutes = div(rem(diff, 3600), 60)
    seconds = rem(diff, 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m"
      true -> "#{seconds}s"
    end
  end

  defp format_duration(_, _), do: ""

  @doc "Sanitizes an agent name for use in data-testid attributes: lowercase, spaces to hyphens."
  def sanitize_agent_name(name) when is_binary(name) do
    name |> String.downcase() |> String.replace(" ", "-")
  end
end
