defmodule SpotterWeb.Live.TranscriptComputers do
  @moduledoc """
  Shared AshComputer definitions for transcript rendering state.

  Attached by both `SessionLive` and `SubagentLive` to provide a single
  reactive pipeline from raw messages to visible transcript lines.
  """
  use AshComputer

  alias Spotter.Services.TranscriptRenderer

  computer :transcript_view do
    input :messages do
      initial []
    end

    input :session_cwd do
      initial nil
    end

    input :show_debug do
      initial false
    end

    input :expanded_tool_groups do
      initial MapSet.new()
    end

    input :expanded_hook_groups do
      initial MapSet.new()
    end

    val :rendered_lines do
      compute(fn %{messages: messages, session_cwd: session_cwd} ->
        opts = if session_cwd, do: [session_cwd: session_cwd], else: []
        TranscriptRenderer.render(messages, opts)
      end)

      depends_on([:messages, :session_cwd])
    end

    val :visible_lines do
      compute(fn %{
                   rendered_lines: rendered_lines,
                   expanded_tool_groups: expanded_tools,
                   expanded_hook_groups: expanded_hooks
                 } ->
        Enum.reject(rendered_lines, fn line ->
          hidden_tool_result?(line, expanded_tools) or
            hidden_hook_detail?(line, expanded_hooks)
        end)
      end)

      depends_on([:rendered_lines, :expanded_tool_groups, :expanded_hook_groups])
    end

    event :toggle_tool_result_group do
      handle(fn %{expanded_tool_groups: expanded}, %{"group" => group} ->
        %{expanded_tool_groups: toggle_set(expanded, group)}
      end)
    end

    event :toggle_hook_group do
      handle(fn %{expanded_hook_groups: expanded}, %{"group" => group} ->
        %{expanded_hook_groups: toggle_set(expanded, group)}
      end)
    end
  end

  defp hidden_tool_result?(line, expanded) do
    line[:hidden_by_default] == true and
      line[:kind] == :tool_result and
      not MapSet.member?(expanded, line[:tool_result_group])
  end

  defp hidden_hook_detail?(line, expanded) do
    line[:hidden_by_default] == true and
      is_binary(line[:hook_group]) and
      not MapSet.member?(expanded, line[:hook_group])
  end

  defp toggle_set(set, value) do
    if MapSet.member?(set, value) do
      MapSet.delete(set, value)
    else
      MapSet.put(set, value)
    end
  end
end
