defmodule SpotterWeb.LanesComponents do
  @moduledoc """
  HEEx components for the time-normalized table lanes view.

  Renders agent transcripts as a CSS Grid table with a sticky time column,
  agent header row, and collapsed/expandable message cells.
  """
  use Phoenix.Component

  @lane_colors ~w(--lane-lead --lane-agent-1 --lane-agent-2 --lane-agent-3 --lane-agent-4 --lane-agent-5 --lane-agent-6)

  @doc "Returns the CSS variable name for a given lane index."
  def lane_color(index), do: Enum.at(@lane_colors, index, "--lane-agent-6")

  attr(:lanes, :list, required: true)
  attr(:rows, :list, default: [])
  attr(:timeline, :map, default: nil)
  attr(:message_links, :list, default: [])
  attr(:active_lane_index, :integer, default: 0)
  attr(:expanded_messages, :map, default: %{})
  attr(:session_id, :string, default: nil)

  def lanes_panel(assigns) do
    lane_index =
      Map.new(Enum.with_index(assigns.lanes), fn {lane, idx} -> {lane.agent_name, idx} end)

    received_link_targets =
      compute_received_link_targets(assigns.message_links, assigns.lanes)

    rendered_lines_index = build_rendered_lines_index(assigns.lanes)

    assigns =
      assigns
      |> assign(:lane_index, lane_index)
      |> assign(:received_link_targets, received_link_targets)
      |> assign(:rendered_lines_index, rendered_lines_index)

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

      <%!-- Desktop: table grid layout --%>
      <div class="lanes-grid" data-testid="lanes-grid" style={"grid-template-columns: 100px repeat(#{length(@lanes)}, minmax(280px, 420px))"}>
        <%!-- Header row: time column --%>
        <div class="lanes-grid-header lanes-time-col" data-testid="lanes-time-header">
          Time
        </div>
        <%!-- Header row: agent columns (sortable) --%>
        <div
          :if={@lanes != []}
          id="lane-headers"
          class="lanes-header-row"
          phx-hook="SortableColumns"
          data-session-id={@session_id}
          data-testid="lanes-header-row"
          style={"display: contents"}
        >
          <div
            :for={{lane, idx} <- Enum.with_index(@lanes)}
            class="lanes-grid-header lanes-agent-header"
            data-testid={"lanes-agent-header-#{sanitize_agent_name(lane.agent_name)}"}
            data-lane-session-id={lane.session && lane.session.session_id}
            data-lane-col-index={idx}
            style={"border-bottom: 3px solid var(#{lane_color(idx)})"}
          >
            <span class="lanes-drag-handle" title="Drag to reorder">&#x2807;</span>
            <span style={"width: 8px; height: 8px; border-radius: 50%; display: inline-block; background: var(#{lane_color(idx)})"}></span>
            <span data-testid="lane-name" style="font-weight: 600;"><%= lane.agent_name %></span>
            <span style="font-size: var(--text-xs); color: var(--text-secondary);">
              <%= format_duration(lane.started_at, lane.ended_at) %>
            </span>
            <span style="font-size: var(--text-xs); color: var(--text-secondary);">
              <%= length(lane.messages) %>
            </span>
          </div>
        </div>

        <%!-- Data rows --%>
        <%= for row <- @rows do %>
          <.table_row
            row={row}
            lanes={@lanes}
            lane_index={@lane_index}
            timeline={@timeline}
            message_links={@message_links}
            expanded_messages={@expanded_messages}
            received_link_targets={@received_link_targets}
            rendered_lines_index={@rendered_lines_index}
          />
        <% end %>

        <%!-- Empty state --%>
        <div :if={@rows == [] && @lanes != []} class="lanes-grid-empty" style={"grid-column: 1 / -1; padding: var(--space-4); color: var(--text-secondary); text-align: center;"}>
          No messages to display.
        </div>
      </div>

      <%!-- SVG connector overlay --%>
      <svg
        id="lanes-connector-overlay"
        class="lanes-connector-overlay"
        data-testid="lanes-connector-overlay"
        phx-hook="ConnectorOverlay"
      ></svg>

      <%!-- Message link drawer --%>
      <div id="lanes-message-drawer" class="lanes-message-drawer" data-testid="lanes-message-drawer" style="display: none;">
        <div class="lanes-drawer-header">
          <span class="lanes-drawer-direction" data-drawer-direction></span>
          <span class="lanes-drawer-peer" data-drawer-peer></span>
          <button class="lanes-drawer-close" data-drawer-close>&times;</button>
        </div>
        <div class="lanes-drawer-preview" data-drawer-preview></div>
        <button class="lanes-drawer-jump" data-drawer-jump>Jump to response</button>
      </div>

      <%!-- Toolbar --%>
      <div :if={@rows != []} class="lanes-toolbar" data-testid="lanes-toolbar">
        <button phx-click="expand_all" class="lanes-toolbar-btn">Expand all</button>
        <button phx-click="collapse_all" class="lanes-toolbar-btn">Collapse all</button>
        <button phx-click="collapse_idle" class="lanes-toolbar-btn">Hide idle</button>
        <button
          :if={length(@lanes) > 1}
          phx-click="reset_column_order"
          class="lanes-toolbar-btn"
          data-testid="reset-column-order"
        >Reset order</button>
      </div>
    </div>
    """
  end

  attr(:row, :map, required: true)
  attr(:lanes, :list, required: true)
  attr(:lane_index, :map, required: true)
  attr(:timeline, :map, default: nil)
  attr(:message_links, :list, default: [])
  attr(:expanded_messages, :map, default: %{})
  attr(:received_link_targets, :map, default: %{})
  attr(:rendered_lines_index, :map, default: %{})

  defp table_row(assigns) do
    offset = format_offset(assigns.row.timestamp, assigns.timeline)
    wall_clock = format_wall_clock(assigns.row.timestamp)
    is_idle = Map.get(assigns.row, :type) == :idle
    assigns = assign(assigns, offset: offset, wall_clock: wall_clock, is_idle: is_idle)

    ~H"""
    <div class={"lanes-time-col lanes-row-time#{if @is_idle, do: " lanes-idle-time", else: ""}"} data-testid="lanes-row">
      <span class="lanes-wall-clock"><%= @wall_clock %></span>
      <span class="lanes-offset"><%= @offset %></span>
    </div>
    <%= for lane <- @lanes do %>
      <.table_cell
        cell={Map.get(@row.cells, lane.agent_name)}
        agent_name={lane.agent_name}
        lane_idx={Map.get(@lane_index, lane.agent_name, 0)}
        is_idle={@is_idle}
        message_links={@message_links}
        expanded_messages={@expanded_messages}
        received_link_targets={@received_link_targets}
        rendered_lines_index={@rendered_lines_index}
      />
    <% end %>
    """
  end

  attr(:cell, :any, default: nil)
  attr(:agent_name, :string, required: true)
  attr(:lane_idx, :integer, required: true)
  attr(:is_idle, :boolean, default: false)
  attr(:message_links, :list, default: [])
  attr(:expanded_messages, :map, default: %{})
  attr(:received_link_targets, :map, default: %{})
  attr(:rendered_lines_index, :map, default: %{})

  defp table_cell(%{cell: nil, is_idle: false} = assigns) do
    ~H"""
    <div class="lanes-cell lanes-cell-empty" data-testid={"lanes-cell-#{sanitize_agent_name(@agent_name)}"}></div>
    """
  end

  defp table_cell(%{is_idle: true} = assigns) do
    idle_duration = if is_map(assigns.cell), do: Map.get(assigns.cell, :idle_duration), else: nil
    assigns = assign(assigns, :idle_duration, idle_duration)

    ~H"""
    <div
      class="lanes-cell lanes-idle-row"
      data-testid={"lanes-cell-#{sanitize_agent_name(@agent_name)}"}
      style={"background: color-mix(in srgb, var(#{lane_color(@lane_idx)}) 15%, transparent)"}
    >
      <span :if={@idle_duration} class="lanes-idle-label">
        idle <%= format_seconds(@idle_duration) %>
      </span>
    </div>
    """
  end

  defp table_cell(assigns) do
    msg = assigns.cell
    msg_id = if is_map(msg), do: Map.get(msg, :id) || Map.get(msg, :uuid), else: nil
    msg_uuid = if is_map(msg), do: Map.get(msg, :uuid), else: nil
    is_expanded = msg_id && Map.get(assigns.expanded_messages, msg_id, false)
    role = if is_map(msg), do: Map.get(msg, :role, :assistant), else: :assistant
    content = if is_map(msg), do: Map.get(msg, :content), else: nil
    preview = content_preview(content)
    tools = extract_tools(content)

    links_for_msg =
      find_message_links(
        assigns.message_links,
        assigns.agent_name,
        msg,
        assigns.received_link_targets
      )

    duration_class = message_duration_class(msg)

    rendered_lines = Map.get(assigns.rendered_lines_index, msg_uuid, [])

    assigns =
      assign(assigns,
        msg: msg,
        msg_id: msg_id,
        is_expanded: is_expanded,
        role: role,
        preview: preview,
        tools: tools,
        links_for_msg: links_for_msg,
        duration_class: duration_class,
        rendered_lines: rendered_lines
      )

    ~H"""
    <div
      class={"lanes-cell#{if @is_expanded, do: " lanes-msg-expanded", else: " lanes-msg-collapsed"}"}
      data-testid={"lanes-cell-#{sanitize_agent_name(@agent_name)}"}
      data-msg-uuid={is_map(@msg) && (Map.get(@msg, :uuid) || Map.get(@msg, :id))}
      data-agent-name={@agent_name}
      phx-click="toggle_message_expand"
      phx-value-message-id={@msg_id}
    >
      <div class="lanes-msg-header">
        <span class="lanes-msg-chevron"><%= if @is_expanded, do: "\u25BC", else: "\u25B6" %></span>
        <span class={"lanes-msg-role lanes-role-#{@role}"}><%= @role %></span>
        <span :if={@duration_class} class={"lanes-msg-duration #{@duration_class}"}></span>
        <%= for tool <- @tools do %>
          <span class="lanes-tool-badge"><%= tool %></span>
        <% end %>
        <%= for link <- @links_for_msg do %>
          <span
            class={"lanes-msg-link-badge lanes-link-#{link.direction}"}
            data-link-direction={link.direction}
            data-link-peer={link.peer}
            data-link-preview={link.content_preview}
            data-link-sender-uuid={link[:sender_message_uuid]}
          >
            <%= link.label %>
          </span>
        <% end %>
        <span :if={!@is_expanded} class="lanes-msg-preview"><%= @preview %></span>
      </div>
      <div :if={@is_expanded} class="lanes-msg-content">
        <.expanded_message_content msg={@msg} rendered_lines={@rendered_lines} />
      </div>
    </div>
    """
  end

  attr(:msg, :map, required: true)
  attr(:rendered_lines, :list, default: [])

  defp expanded_message_content(%{rendered_lines: [_ | _]} = assigns) do
    ~H"""
    <div class="lanes-rendered-lines">
      <%= for line <- @rendered_lines do %>
        <div class={"lanes-rendered-line lanes-line-#{line[:kind] || :text}"} data-render-mode={to_string(line[:render_mode] || "plain")}>
          <%= if line[:render_mode] == :code do %>
            <pre class="lanes-msg-text"><code class={"language-#{line[:code_language] || "plaintext"}"}><%= line.line %></code></pre>
          <% else %>
            <span class="lanes-msg-text"><%= line.line %></span>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp expanded_message_content(assigns) do
    content = Map.get(assigns.msg, :content)
    text = extract_text(content)
    assigns = assign(assigns, :text, text)

    ~H"""
    <pre class="lanes-msg-text"><%= @text %></pre>
    """
  end

  # --- Helpers ---

  defp content_preview(nil), do: ""

  defp content_preview(content) when is_map(content) do
    text = extract_text(content)
    if String.length(text) > 80, do: String.slice(text, 0, 80) <> "...", else: text
  end

  defp content_preview(content) when is_binary(content) do
    if String.length(content) > 80, do: String.slice(content, 0, 80) <> "...", else: content
  end

  defp content_preview(_), do: ""

  defp extract_text(content) when is_map(content) do
    blocks = Map.get(content, "blocks", [])

    blocks
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} -> [text]
      _ -> []
    end)
    |> Enum.join("\n")
    |> case do
      "" -> Map.get(content, "text", "")
      text -> text
    end
  end

  defp extract_text(content) when is_binary(content), do: content
  defp extract_text(_), do: ""

  defp extract_tools(nil), do: []

  defp extract_tools(content) when is_map(content) do
    blocks = Map.get(content, "blocks", [])

    tools =
      blocks
      |> Enum.flat_map(fn
        %{"type" => "tool_use", "name" => name} -> [name]
        _ -> []
      end)
      |> Enum.uniq()

    if length(tools) > 3 do
      ["#{length(tools)} tools"]
    else
      tools
    end
  end

  defp extract_tools(_), do: []

  # Bug 3 fix: use received_link_targets to scope received badges to the correct message
  defp find_message_links(links, agent_name, msg, received_link_targets)
       when is_list(links) and is_map(msg) do
    msg_uuid = Map.get(msg, :uuid)

    sent =
      links
      |> Enum.filter(&(&1.sender == agent_name && &1.sender_message_uuid == msg_uuid))
      |> Enum.map(
        &%{
          direction: :sent,
          label: "-> #{&1.recipient}",
          peer: &1.recipient,
          content_preview: Map.get(&1, :content_preview, ""),
          timestamp: &1.timestamp
        }
      )

    received =
      links
      |> Enum.filter(fn link ->
        link.recipient == agent_name &&
          Map.get(received_link_targets, link_key(link)) == msg_uuid
      end)
      |> Enum.map(
        &%{
          direction: :received,
          label: "<- #{&1.sender}",
          peer: &1.sender,
          sender_message_uuid: &1.sender_message_uuid,
          content_preview: Map.get(&1, :content_preview, ""),
          timestamp: &1.timestamp
        }
      )

    sent ++ received
  end

  defp find_message_links(_, _, _, _), do: []

  # Pre-compute which message UUID in each recipient lane should show each received badge.
  # For each link, find the first message in the recipient's lane at or after the link timestamp.
  defp compute_received_link_targets(links, lanes) when is_list(links) and is_list(lanes) do
    lane_messages =
      Map.new(lanes, fn lane ->
        {lane.agent_name, Enum.sort_by(lane.messages, & &1.timestamp, DateTime)}
      end)

    Enum.reduce(links, %{}, fn link, acc ->
      messages = Map.get(lane_messages, link.recipient, [])
      target_uuid = first_msg_uuid_at_or_after(messages, link.timestamp)

      if target_uuid do
        Map.put(acc, link_key(link), target_uuid)
      else
        acc
      end
    end)
  end

  defp compute_received_link_targets(_, _), do: %{}

  defp first_msg_uuid_at_or_after(messages, timestamp) do
    Enum.find_value(messages, fn msg ->
      if msg.timestamp && DateTime.compare(msg.timestamp, timestamp) != :lt, do: msg.uuid
    end)
  end

  defp link_key(link) do
    {link.sender, link.recipient, link.sender_message_uuid}
  end

  # Build a map from msg_uuid to rendered_lines for expanded content rendering (Bug 2 fix).
  # Uses pre-computed rendered_lines from ParallelLanes.build_lane.
  defp build_rendered_lines_index(lanes) when is_list(lanes) do
    Enum.reduce(lanes, %{}, fn lane, acc ->
      rendered = Map.get(lane, :rendered_lines, [])
      index_lane_rendered_lines(lane.messages, rendered, acc)
    end)
  end

  defp build_rendered_lines_index(_), do: %{}

  defp index_lane_rendered_lines(messages, rendered_lines, acc) do
    msg_id_to_uuid =
      Map.new(messages, fn msg -> {msg.id || msg.uuid, msg.uuid} end)

    lines_by_msg_id = Enum.group_by(rendered_lines, fn line -> line[:message_id] end)

    # If all lines lack :message_id (nil key only), distribute to each message by id
    case Map.keys(lines_by_msg_id) do
      [nil] ->
        distribute_unkeyed_lines(messages, rendered_lines, acc)

      _ ->
        Enum.reduce(lines_by_msg_id, acc, &merge_lines_for_msg(&1, &2, msg_id_to_uuid))
    end
  end

  defp distribute_unkeyed_lines(messages, rendered_lines, acc) do
    case messages do
      [single] -> Map.put(acc, single.uuid, rendered_lines)
      _ -> acc
    end
  end

  defp merge_lines_for_msg({nil, _lines}, acc, _msg_id_to_uuid), do: acc

  defp merge_lines_for_msg({msg_id, lines}, acc, msg_id_to_uuid) do
    case Map.get(msg_id_to_uuid, msg_id) do
      nil -> acc
      uuid -> Map.put(acc, uuid, lines)
    end
  end

  defp message_duration_class(msg) when is_map(msg) do
    # Could compute from consecutive messages; for now return nil
    nil
  end

  defp message_duration_class(_), do: nil

  defp format_wall_clock(nil), do: ""

  defp format_wall_clock(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_wall_clock(_), do: ""

  defp format_offset(_ts, nil), do: ""
  defp format_offset(nil, _timeline), do: ""

  defp format_offset(%DateTime{} = ts, %{earliest: %DateTime{} = earliest}) do
    diff = max(DateTime.diff(ts, earliest, :second), 0)
    minutes = div(diff, 60)
    seconds = rem(diff, 60)
    "+#{minutes}:#{String.pad_leading("#{seconds}", 2, "0")}"
  end

  defp format_offset(_, _), do: ""

  @doc false
  def format_duration(started_at, ended_at)
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

  def format_duration(_, _), do: ""

  defp format_seconds(nil), do: ""

  defp format_seconds(seconds) when is_integer(seconds) do
    cond do
      seconds >= 3600 -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
      seconds >= 60 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{seconds}s"
    end
  end

  defp format_seconds(_), do: ""

  @doc "Sanitizes an agent name for use in data-testid attributes: lowercase, spaces to hyphens."
  def sanitize_agent_name(nil), do: "unknown"

  def sanitize_agent_name(name) when is_binary(name) do
    name |> String.downcase() |> String.replace(" ", "-")
  end
end
