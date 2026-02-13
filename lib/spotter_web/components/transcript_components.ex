defmodule SpotterWeb.TranscriptComponents do
  @moduledoc """
  Shared HEEx components for transcript rendering.

  Used by both `SessionLive` and `SubagentLive` to render transcript rows
  with consistent markup, CSS classes, and JS hook wiring.
  """
  use Phoenix.Component

  @doc """
  Renders the transcript panel with all rows.

  ## Assigns

    * `:rendered_lines` (required) - list of visible line maps from TranscriptRenderer
    * `:all_rendered_lines` - full list including hidden lines, for expand controls (default same as rendered_lines)
    * `:expanded_tool_groups` - MapSet of expanded group keys (default empty)
    * `:current_message_id` - message ID to highlight as active (default `nil`)
    * `:clicked_subagent` - currently clicked subagent ref (default `nil`)
    * `:show_debug` - whether debug sidecar is visible (default `false`)
    * `:anchors` - list of sync anchors for debug mode (default `[]`)
    * `:panel_id` - DOM id for the transcript container (default "transcript-messages")
    * `:empty_message` - text shown when no lines exist (default "No transcript available.")
  """
  attr(:rendered_lines, :list, required: true)
  attr(:all_rendered_lines, :list, default: nil)
  attr(:expanded_tool_groups, :any, default: nil)
  attr(:current_message_id, :any, default: nil)
  attr(:clicked_subagent, :string, default: nil)
  attr(:show_debug, :boolean, default: false)
  attr(:anchors, :list, default: [])
  attr(:panel_id, :string, default: "transcript-messages")
  attr(:empty_message, :string, default: "No transcript available.")

  def transcript_panel(assigns) do
    all_lines = assigns.all_rendered_lines || assigns.rendered_lines
    expanded = assigns.expanded_tool_groups || MapSet.new()

    assigns =
      assigns
      |> assign(:expand_groups, compute_expand_groups(all_lines, expanded))

    ~H"""
    <%= if @rendered_lines != [] do %>
      <div
        id={@panel_id}
        data-testid="transcript-container"
        phx-hook="TranscriptHighlighter"
        phx-update="replace"
        class={if @show_debug, do: "transcript-debug-grid", else: ""}
      >
        <%= for line <- @rendered_lines do %>
          <.transcript_row
            line={line}
            current_message_id={@current_message_id}
            clicked_subagent={@clicked_subagent}
            show_debug={@show_debug}
            anchors={@anchors}
          />
          <%= if @show_debug do %>
            <div class="transcript-debug-sidecar" data-render-mode="code">
              <pre><code class="language-json"><%= encode_debug_payload(line[:debug_payload]) %></code></pre>
            </div>
          <% end %>
          <.expand_control
            :if={expand_control_for(line, @expand_groups)}
            group_info={expand_control_for(line, @expand_groups)}
          />
        <% end %>
      </div>
    <% else %>
      <p class="transcript-empty" data-testid="transcript-empty">{@empty_message}</p>
    <% end %>
    """
  end

  @doc """
  Renders a single transcript row.
  """
  attr(:line, :map, required: true)
  attr(:current_message_id, :any, default: nil)
  attr(:clicked_subagent, :string, default: nil)
  attr(:show_debug, :boolean, default: false)
  attr(:anchors, :list, default: [])

  def transcript_row(assigns) do
    ~H"""
    <div
      id={"msg-#{@line.line_number}"}
      data-testid="transcript-row"
      data-message-id={@line.message_id}
      data-line-number={@line.line_number}
      class={row_classes(@line, @current_message_id, @clicked_subagent)}
      data-render-mode={to_string(@line[:render_mode] || "plain")}
      data-tool-name={@line[:tool_name]}
      data-command-status={if @line[:command_status], do: to_string(@line[:command_status])}
    >
      <div class="row-main">
        <%= if @show_debug do %>
          <% anchor = Enum.find(@anchors, &(&1.tl == @line.line_number)) %>
          <span
            :if={anchor}
            style={"display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:4px;background:#{anchor_color(anchor.type)};"}
            title={"#{anchor.type} → terminal line #{anchor.t}"}
          />
        <% end %>
        <%= if @line[:subagent_ref] do %>
          <span
            class="subagent-badge"
            phx-click="subagent_reference_clicked"
            phx-value-ref={@line.subagent_ref}
          >
            agent
          </span>
        <% end %>
        <%= if @line[:render_mode] == :code do %>
          <pre class="row-text row-text-code"><span :if={@line[:source_line_number]} class="source-line-number"><%= @line[:source_line_number] %></span><code class={"language-#{@line[:code_language] || "plaintext"}"}><%= @line.line %></code></pre>
        <% else %>
          <span
            class="row-text"
            data-render-markdown={if markdown_line?(@line), do: "true", else: "false"}
          ><%= @line.line %></span>
        <% end %>
        <span :if={@line[:token_count_total]} class="row-token-count">{@line[:token_count_total]} tok{format_token_delta(@line[:token_count_delta])}</span>
      </div>
    </div>
    """
  end

  attr(:group_info, :map, required: true)

  defp expand_control(assigns) do
    ~H"""
    <div class="transcript-expand-control">
      <button
        class="btn-expand-tool-result"
        phx-click={@group_info.event}
        phx-value-group={@group_info.group}
      >
        {expand_button_text(@group_info)}
      </button>
    </div>
    """
  end

  # ── Expand group computation ────────────────────────────────────────

  defp compute_expand_groups(all_lines, expanded) do
    all_lines
    |> Enum.filter(
      &(&1.kind == :tool_result && &1[:result_total_lines] && &1.result_total_lines > 10)
    )
    |> Enum.group_by(& &1.tool_result_group)
    |> Map.new(fn {group, lines} ->
      is_expanded = MapSet.member?(expanded, group)
      hidden_count = Enum.count(lines, & &1.hidden_by_default)
      last_visible_index = last_visible_index(lines, is_expanded)

      {group,
       %{
         group: group,
         hidden_count: hidden_count,
         is_expanded: is_expanded,
         last_visible_index: last_visible_index,
         event: "transcript_view_toggle_tool_result_group"
       }}
    end)
  end

  defp last_visible_index(lines, true) do
    lines |> List.last() |> Map.get(:result_line_index)
  end

  defp last_visible_index(lines, false) do
    lines
    |> Enum.reject(& &1.hidden_by_default)
    |> List.last()
    |> case do
      nil -> 0
      line -> line.result_line_index
    end
  end

  defp expand_control_for(line, expand_groups) do
    result_index = line[:result_line_index]

    case Map.get(expand_groups, line[:tool_result_group]) do
      %{last_visible_index: ^result_index} = info -> info
      _ -> nil
    end
  end

  defp format_token_delta(nil), do: ""
  defp format_token_delta(0), do: " (0)"
  defp format_token_delta(delta) when delta > 0, do: " (+#{delta})"
  defp format_token_delta(delta), do: " (#{delta})"

  defp expand_button_text(%{is_expanded: true}), do: "Show less"

  defp expand_button_text(%{hidden_count: count}) do
    "Show #{count} more lines"
  end

  defp encode_debug_payload(nil), do: "{}"

  defp encode_debug_payload(payload) do
    Jason.encode!(payload, pretty: true)
  rescue
    _ -> ~s({"error": "Could not encode payload"})
  end

  @doc false
  def row_classes(line, current_message_id, clicked_subagent) do
    kind = kind_classes(line)
    type = if line.type == :user, do: ["is-user"], else: []
    code = if line[:render_mode] == :code, do: ["is-code"], else: []
    active = if current_message_id == line.message_id, do: ["is-active"], else: []

    classes = ["transcript-row"] ++ kind ++ type ++ code ++ active
    classes = classes ++ subagent_classes(line[:subagent_ref], clicked_subagent)
    Enum.join(classes, " ")
  end

  defp kind_classes(line) do
    case line[:kind] do
      :tool_use -> ["is-tool-use"] ++ bash_status_classes(line)
      :tool_result -> ["is-tool-result"]
      :thinking -> ["is-thinking"]
      :ask_user_question -> ["is-ask-user-question"]
      :ask_user_answer -> ["is-ask-user-answer"]
      :plan_content -> ["is-plan-content"]
      :plan_decision -> ["is-plan-decision"]
      _ -> []
    end
  end

  defp bash_status_classes(%{tool_name: "Bash", command_status: :success}),
    do: ["is-bash-success"]

  defp bash_status_classes(%{tool_name: "Bash", command_status: :error}), do: ["is-bash-error"]
  defp bash_status_classes(_line), do: []

  defp subagent_classes(nil, _clicked), do: []

  defp subagent_classes(ref, clicked) do
    if clicked == ref, do: ["is-subagent", "is-clicked"], else: ["is-subagent"]
  end

  defp markdown_line?(line) do
    line[:render_mode] == :plain and line[:kind] in [:text, :thinking]
  end

  defp anchor_color(:tool_use), do: "var(--accent-amber)"
  defp anchor_color(:user), do: "var(--accent-blue)"
  defp anchor_color(:result), do: "var(--accent-green)"
  defp anchor_color(:text), do: "var(--accent-purple)"
  defp anchor_color(_), do: "var(--text-tertiary)"
end
