defmodule SpotterWeb.LanesComponents do
  @moduledoc """
  HEEx components for parallel transcript lanes view.

  Renders agent transcripts as side-by-side vertical columns on a shared
  time axis, showing when agents worked in parallel vs sequentially.
  """
  use Phoenix.Component

  @lane_colors ~w(--lane-lead --lane-agent-1 --lane-agent-2 --lane-agent-3 --lane-agent-4 --lane-agent-5 --lane-agent-6)

  @doc "Returns the CSS variable name for a given lane index."
  def lane_color(index), do: Enum.at(@lane_colors, index, "--lane-agent-6")

  @doc """
  Renders the parallel lanes panel with time axis and lane columns.

  ## Assigns

    * `:lanes` (required) - list of lane maps with agent_name, session, messages, started_at, ended_at
    * `:overlaps` (required) - list of overlap region maps
    * `:timeline` (required) - map with :earliest and :latest DateTime
    * `:active_lane_index` - index of the active lane for responsive tab view (default 0)
  """
  attr(:lanes, :list, required: true)
  attr(:overlaps, :list, required: true)
  attr(:timeline, :map, required: true)
  attr(:active_lane_index, :integer, default: 0)

  def lanes_panel(assigns) do
    ~H"""
    <div id="lanes-scroll" class="lanes-container" data-testid="lanes-panel" phx-hook="LaneScroll">
      <div :if={@lanes != []} class="lanes-tab-bar" role="tablist">
        <button
          :for={{lane, idx} <- Enum.with_index(@lanes)}
          class={"lanes-tab#{if idx == @active_lane_index, do: " is-active", else: ""}"}
          data-testid={"lane-tab-#{sanitize_agent_name(lane.agent_name)}"}
          phx-click="switch_lane"
          phx-value-index={idx}
          role="tab"
          aria-selected={"#{idx == @active_lane_index}"}
        >
          <span style={"width: 6px; height: 6px; border-radius: 50%; display: inline-block; background: var(#{lane_color(idx)})"}></span>
          <%= lane.agent_name %>
        </button>
      </div>
      <.time_axis :if={@lanes != []} timeline={@timeline} overlaps={@overlaps} />
      <.lane_column
        :for={{lane, idx} <- Enum.with_index(@lanes)}
        lane={lane}
        color={lane_color(idx)}
        active={idx == @active_lane_index}
        role="tabpanel"
      />
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
    ~H"""
    <div
      class={"lanes-column#{if @active, do: " is-active", else: ""}"}
      data-testid={"lane-column-#{sanitize_agent_name(@lane.agent_name)}"}
      style={"border-left: 3px solid var(#{@color})"}
      role={@role}
    >
      <.lane_header lane={@lane} color={@color} />
      <div :for={msg <- @lane.messages} class="lanes-entry">
        <span style="font-size: var(--text-xs); color: var(--text-secondary);"><%= msg.role %></span>
        <div><%= summarize_content(msg.content) %></div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the time axis gutter with timestamps and parallel region indicators.

  ## Assigns

    * `:timeline` (required) - map with :earliest and :latest DateTime
    * `:overlaps` (required) - list of overlap region maps with :start, :end, :type (:full/:partial)
  """
  attr(:timeline, :map, required: true)
  attr(:overlaps, :list, required: true)

  def time_axis(assigns) do
    ~H"""
    <div class="lanes-time-axis" data-testid="lanes-time-axis">
      <div class="lanes-header">
        <span style="font-size: var(--text-xs); color: var(--text-tertiary);">TIME</span>
      </div>
      <div
        :for={overlap <- @overlaps}
        class={"lanes-gutter-bar#{if overlap.type == :partial, do: " partial", else: ""}"}
        data-testid={"overlap-bar-#{format_time(overlap.start)}"}
      >
        <span data-testid={"overlap-time-#{format_time(overlap.start)}"} style="font-family: var(--font-mono); font-size: var(--text-xs); color: var(--text-tertiary);">
          <%= format_time(overlap.start) %>
        </span>
      </div>
    </div>
    """
  end

  defp summarize_content(content) when is_binary(content), do: content

  defp summarize_content(%{"blocks" => blocks}) when is_list(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("\n", & &1["text"])
  end

  defp summarize_content(_), do: ""

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp format_time(_), do: ""

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
