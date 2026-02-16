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
    * `:expanded_tool_groups` - MapSet of expanded tool result group keys (default empty)
    * `:expanded_hook_groups` - MapSet of expanded hook group keys (default empty)
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
  attr(:expanded_hook_groups, :any, default: nil)
  attr(:current_message_id, :any, default: nil)
  attr(:clicked_subagent, :string, default: nil)
  attr(:session_id, :string, default: nil)
  attr(:subagent_labels, :map, default: %{})
  attr(:current_agent_id, :string, default: nil)
  attr(:show_debug, :boolean, default: false)
  attr(:anchors, :list, default: [])
  attr(:panel_id, :string, default: "transcript-messages")
  attr(:project_id, :string, default: nil)
  attr(:existing_files, :any, default: nil)
  attr(:empty_message, :string, default: "No transcript available.")

  def transcript_panel(assigns) do
    all_lines = assigns.all_rendered_lines || assigns.rendered_lines
    expanded = assigns.expanded_tool_groups || MapSet.new()
    expanded_hooks = assigns.expanded_hook_groups || MapSet.new()

    assigns =
      assigns
      |> assign(:expand_groups, compute_expand_groups(all_lines, expanded))
      |> assign(:tool_hook_controls, compute_tool_hook_controls(all_lines, expanded_hooks))

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
            session_id={@session_id}
            subagent_labels={@subagent_labels}
            current_agent_id={@current_agent_id}
            show_debug={@show_debug}
            anchors={@anchors}
            tool_hook_controls={@tool_hook_controls}
            project_id={@project_id}
            existing_files={@existing_files}
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
  attr(:session_id, :string, default: nil)
  attr(:subagent_labels, :map, default: %{})
  attr(:current_agent_id, :string, default: nil)
  attr(:show_debug, :boolean, default: false)
  attr(:anchors, :list, default: [])
  attr(:tool_hook_controls, :map, default: %{})
  attr(:project_id, :string, default: nil)
  attr(:existing_files, :any, default: nil)

  def transcript_row(assigns) do
    ~H"""
    <div
      id={"msg-" <> Integer.to_string(@line.line_number)}
      data-testid="transcript-row"
      data-message-id={@line.message_id}
      data-line-number={@line.line_number}
      data-render-mode={to_string(@line[:render_mode] || "plain")}
        data-tool-name={@line[:tool_name]}
        data-command-status={if @line[:command_status], do: to_string(@line[:command_status])}
        data-thread-key={@line.thread_key}
        class={row_classes(@line, @current_message_id, @clicked_subagent) <>
               if(has_row_meta?(@line, @tool_hook_controls), do: " is-meta-row", else: "")}
      >
      <div class="row-main">
        <span class="row-content">
          <%= if @show_debug do %>
            <% anchor = Enum.find(@anchors, &(&1.tl == @line.line_number)) %>
            <span
              :if={anchor}
              class="transcript-anchor"
              style={"background:#{anchor_color(anchor.type)};"}
              title={"#{anchor.type} → terminal line #{anchor.t}"}
            />
          <% end %>
          <%= if @line[:subagent_invocation?] == true and is_binary(@line[:subagent_ref]) and is_binary(@session_id) and @current_agent_id != @line.subagent_ref do %>
            <% agent_id = @line.subagent_ref %>
            <% label = Map.get(@subagent_labels, agent_id) || String.slice(agent_id, 0, 7) %>
            <a
              class="subagent-badge"
              href={"/sessions/#{@session_id}/agents/#{agent_id}"}
              title={"type=#{@line[:subagent_type]} model=#{@line[:subagent_model]} agent_id=#{agent_id}"}
            >
              Subagent {label}
            </a>
          <% else %>
            <%= if @line[:subagent_ref] && is_binary(@line[:subagent_ref]) && is_binary(@session_id) do %>
              <% agent_id = @line.subagent_ref %>
              <a
                class="subagent-badge"
                href={"/sessions/#{@session_id}/agents/#{agent_id}"}
              >
                agent
              </a>
            <% end %>
          <% end %>
          <span :if={@line[:kind] == :thinking} class="thinking-icon">💡</span>
          <span :if={tool_status_dot_visible?(@line)} class={"row-status-dot #{status_dot_class(@line)}"}></span>
          <%= if @line[:render_mode] == :code do %>
            <pre class="row-text row-text-code"><span :if={@line[:source_line_number]} class="source-line-number"><%= @line[:source_line_number] %></span><code class={"language-#{@line[:code_language] || "plaintext"}"}><%= @line.line %></code></pre>
          <% else %>
            <span
              class="row-text"
              data-render-markdown={if markdown_line?(@line), do: "true", else: "false"}
            ><%= linkify_file_refs(@line, @project_id, @existing_files) %></span>
          <% end %>
        </span>
        <span :if={has_row_meta?(@line, @tool_hook_controls)} class="row-meta">
          <span :if={tool_hook_controls(@line, @tool_hook_controls) != []} class="row-hook-controls">
            <%= for hook_control <- tool_hook_controls(@line, @tool_hook_controls) do %>
              <button
                class="btn-expand-tool-result btn-expand-tool-hook"
                phx-click="transcript_view_toggle_hook_group"
                phx-value-group={hook_control.group}
              >
                <%= hook_control_text(hook_control) %>
              </button>
            <% end %>
          </span>
        </span>
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

  # ── Expand group computation for tool result lines ─────────────────────────────────────

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

  defp has_row_meta?(line, tool_hook_controls) do
    tool_hook_controls(line, tool_hook_controls) != []
  end

  defp expand_button_text(%{is_expanded: true, event: "transcript_view_toggle_hook_group"}),
    do: "Hide hooks"

  defp expand_button_text(%{is_expanded: true}), do: "Show less"

  defp expand_button_text(%{event: "transcript_view_toggle_hook_group", hidden_count: count}) do
    "Show #{count} hooks"
  end

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

  @kind_class_map %{
    tool_result: ["is-tool-result"],
    thinking: ["is-thinking"],
    ask_user_question: ["is-ask-user-question"],
    ask_user_answer: ["is-ask-user-answer"],
    plan_content: ["is-plan-content"],
    plan_decision: ["is-plan-decision"],
    hook_progress: ["is-hook-progress"],
    hook_group: ["is-hook-group"],
    hook_output: ["is-hook-output"]
  }

  defp kind_classes(%{kind: :tool_use} = line) do
    ["is-tool-use"] ++ bash_status_classes(line)
  end

  defp kind_classes(line) do
    Map.get(@kind_class_map, line[:kind], [])
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

  # ── File reference linkification ────────────────────────────────────

  @file_ext_pattern ~r/(?:^|(?<=[\s("'`]))([a-zA-Z0-9_\-\.\/]+\.(?:ex|exs|heex|eex|leex|json|jsonl|js|jsx|ts|tsx|py|rb|rs|go|yml|yaml|toml|md|html|css|sql|sh|bash|diff|txt|conf|cfg|xml|csv))(?::(\d+)(?::(\d+))?)?(?=$|[\s)"'`.,;!?])/

  def linkify_file_refs(line, nil, _existing_files), do: line.line
  def linkify_file_refs(line, _project_id, nil), do: line.line

  def linkify_file_refs(line, project_id, existing_files) do
    if line[:file_ref_relative_path] &&
         MapSet.member?(existing_files, line[:file_ref_relative_path]) do
      linkify_structured_ref(line, project_id)
    else
      linkify_plain_text(line.line, project_id, existing_files)
    end
  end

  defp linkify_structured_ref(line, project_id) do
    path = line.file_ref_relative_path
    href = "/projects/#{project_id}/files/#{path}"

    Phoenix.HTML.raw(
      String.replace(
        Phoenix.HTML.html_escape(line.line) |> Phoenix.HTML.safe_to_string(),
        Phoenix.HTML.html_escape(path) |> Phoenix.HTML.safe_to_string(),
        ~s(<a href="#{href}" class="file-ref-link">#{Phoenix.HTML.html_escape(path) |> Phoenix.HTML.safe_to_string()}</a>),
        global: false
      )
    )
  end

  defp linkify_plain_text(text, project_id, existing_files) do
    case Regex.split(@file_ext_pattern, text, include_captures: true) do
      [^text] ->
        text

      parts ->
        parts
        |> Enum.map_join("", &linkify_part(&1, project_id, existing_files))
        |> Phoenix.HTML.raw()
    end
  end

  defp linkify_part(part, project_id, existing_files) do
    case Regex.run(@file_ext_pattern, part) do
      [_full, path | _rest] ->
        render_file_ref_part(part, path, project_id, existing_files)

      _ ->
        escape_to_string(part)
    end
  end

  defp render_file_ref_part(part, path, project_id, existing_files) do
    if MapSet.member?(existing_files, path) do
      href = "/projects/#{project_id}/files/#{path}"
      escaped_path = escape_to_string(path)

      String.replace(
        escape_to_string(part),
        escaped_path,
        ~s(<a href="#{href}" class="file-ref-link">#{escaped_path}</a>),
        global: false
      )
    else
      escape_to_string(part)
    end
  end

  defp escape_to_string(text) do
    text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  # ── Hook control computation for tool headers ───────────────────────────────────

  defp compute_tool_hook_controls(all_lines, expanded_hooks) do
    detail_counts =
      Enum.reduce(all_lines, %{}, fn line, counts ->
        group = line[:hook_group]

        if group && line[:kind] != :hook_group do
          Map.update(counts, group, 1, &(&1 + 1))
        else
          counts
        end
      end)

    all_lines
    |> Enum.filter(&(&1[:kind] == :hook_group))
    |> Enum.group_by(& &1.tool_use_id)
    |> Map.new(fn {tool_use_id, rows} ->
      controls =
        Enum.map(rows, fn summary ->
          %{
            group: summary.hook_group,
            is_expanded: MapSet.member?(expanded_hooks, summary.hook_group),
            hidden_count: Map.get(detail_counts, summary.hook_group, 0)
          }
        end)

      {tool_use_id, controls}
    end)
  end

  defp tool_hook_controls(line, tool_hook_controls) do
    if line[:kind] == :tool_use do
      Map.get(tool_hook_controls, line[:tool_use_id], [])
    else
      []
    end
  end

  defp hook_control_text(%{is_expanded: true}), do: "Hide hooks"

  defp hook_control_text(%{hidden_count: count}) when count <= 1, do: "Show 1 hook"

  defp hook_control_text(%{hidden_count: count}), do: "Show #{count} hooks"

  defp tool_status_dot_visible?(line) do
    Map.get(line, :kind) == :tool_use and Map.has_key?(line, :command_status)
  end

  defp status_dot_class(line) do
    case line[:command_status] do
      :success -> "is-success"
      :error -> "is-error"
      :pending -> "is-pending"
      _ -> "is-default"
    end
  end

  defp anchor_color(:tool_use), do: "var(--accent-amber)"
  defp anchor_color(:user), do: "var(--accent-blue)"
  defp anchor_color(:result), do: "var(--accent-green)"
  defp anchor_color(:text), do: "var(--accent-purple)"
  defp anchor_color(_), do: "var(--text-tertiary)"
end
