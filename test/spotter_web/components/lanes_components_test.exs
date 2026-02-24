defmodule SpotterWeb.LanesComponentsTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias SpotterWeb.LanesComponents

  @endpoint SpotterWeb.Endpoint

  defp build_lane(agent_name, started_at, ended_at, message_count \\ 2) do
    messages =
      for i <- 1..message_count do
        %{
          id: "#{agent_name}-msg-#{i}",
          uuid: "uuid-#{agent_name}-#{i}",
          type: :assistant,
          role: :assistant,
          content: %{"text" => "message #{i}"},
          timestamp: started_at,
          line: "message #{i}",
          line_number: i,
          message_id: "#{agent_name}-msg-#{i}",
          thread_key: "thread-#{agent_name}",
          render_mode: :plain,
          kind: :text
        }
      end

    rendered_lines =
      Enum.with_index(messages, 1)
      |> Enum.map(fn {msg, idx} -> Map.put(msg, :line_number, idx) end)

    %{
      agent_name: agent_name,
      session: %{session_id: "session-#{agent_name}", cwd: "/tmp/test"},
      messages: messages,
      rendered_lines: rendered_lines,
      idle_periods: [],
      started_at: started_at,
      ended_at: ended_at
    }
  end

  defp build_rows(lanes) do
    lanes
    |> Enum.flat_map(fn lane ->
      Enum.map(lane.messages, fn msg ->
        {msg.timestamp, lane.agent_name, msg}
      end)
    end)
    |> Enum.sort_by(&elem(&1, 0), DateTime)
    |> Enum.map(fn {ts, agent, msg} ->
      all_agents = Enum.map(lanes, & &1.agent_name)
      cells = Map.new(all_agents, fn name -> {name, if(name == agent, do: msg)} end)
      %{timestamp: ts, cells: cells}
    end)
  end

  describe "lanes_panel/1" do
    test "renders container with grid layout for 3 lanes" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z]),
        build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z]),
        build_lane("implementer", ~U[2026-02-01 10:10:00Z], ~U[2026-02-01 10:30:00Z])
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows
        )

      assert html =~ "lanes-container"
      assert html =~ "lanes-grid"
      assert html =~ ~s(data-testid="lanes-grid")
    end

    test "renders sticky time column header" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z])
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows
        )

      assert html =~ "lanes-time-col"
      assert html =~ ~s(data-testid="lanes-time-header")
      assert html =~ "Time"
    end

    test "renders agent header cells for each lane" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z]),
        build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z])
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows
        )

      assert html =~ ~s(data-testid="lanes-agent-header-team-lead")
      assert html =~ ~s(data-testid="lanes-agent-header-qa-tester")
      assert html =~ "lanes-agent-header"
    end

    test "renders rows with time cells" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z], 1)
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows
        )

      assert html =~ ~s(data-testid="lanes-row")
      assert html =~ "lanes-cell"
      assert html =~ ~s(data-testid="lanes-cell-team-lead")
    end

    test "tab bar has LaneDrag phx-hook for drag-and-drop" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z]),
        build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z])
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes
        )

      assert html =~ ~s(phx-hook="LaneDrag")
      assert html =~ ~s(data-lane-session-id="session-team-lead")
      assert html =~ ~s(data-lane-session-id="session-qa-tester")
    end

    test "agent headers have SortableColumns hook and drag handles" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z]),
        build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z])
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          session_id: "test-session-123"
        )

      assert html =~ ~s(phx-hook="SortableColumns")
      assert html =~ ~s(data-session-id="test-session-123")
      assert html =~ ~s(data-testid="lanes-header-row")
      assert html =~ "lanes-drag-handle"
      # Agent headers carry session_id for SortableJS
      assert html =~ ~s(data-lane-session-id="session-team-lead")
      assert html =~ ~s(data-lane-session-id="session-qa-tester")
      assert html =~ ~s(data-lane-col-index="0")
      assert html =~ ~s(data-lane-col-index="1")
    end

    test "reset order button shown when more than 1 lane" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z]),
        build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z])
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows
        )

      assert html =~ ~s(data-testid="reset-column-order")
      assert html =~ "Reset order"
    end

    test "reset order button hidden when single lane" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z])
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows
        )

      refute html =~ ~s(data-testid="reset-column-order")
    end

    test "renders data-testid='lanes-panel' on container" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z])
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes
        )

      assert html =~ ~s(data-testid="lanes-panel")
    end

    test "renders lane-tab-{name} data-testid on tab buttons" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z]),
        build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z])
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes
        )

      assert html =~ ~s(data-testid="lane-tab-team-lead")
      assert html =~ ~s(data-testid="lane-tab-qa-tester")
    end

    test "sanitizes agent names with spaces for data-testid" do
      lanes = [
        build_lane("Agent 1", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z])
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes
        )

      assert html =~ ~s(data-testid="lane-tab-agent-1")
      assert html =~ ~s(data-testid="lanes-agent-header-agent-1")
    end

    test "renders empty message when lanes list is empty" do
      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: []
        )

      assert html =~ "lanes-container"
      refute html =~ ~s(data-testid="lanes-agent-header-)
    end

    test "agent headers show name, duration, and message count" do
      lanes = [
        build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z], 3)
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes
        )

      assert html =~ "qa-tester"
      assert html =~ "15m"
      assert html =~ "3"
      assert html =~ ~s(data-testid="lane-name")
    end

    test "collapsed messages show preview text and chevron" do
      lanes = [
        build_lane("agent-a", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z], 1)
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows
        )

      assert html =~ "lanes-msg-collapsed"
      assert html =~ "lanes-msg-chevron"
      assert html =~ "lanes-msg-preview"
    end

    test "renders toolbar with expand/collapse buttons when rows exist" do
      lanes = [
        build_lane("agent-a", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z], 1)
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows
        )

      assert html =~ "lanes-toolbar"
      assert html =~ "Expand all"
      assert html =~ "Collapse all"
      assert html =~ "Hide idle"
    end

    test "expanded message shows content area" do
      lanes = [
        build_lane("agent-a", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z], 1)
      ]

      rows = build_rows(lanes)
      msg_id = "agent-a-msg-1"

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows,
          expanded_messages: %{msg_id => true}
        )

      assert html =~ "lanes-msg-expanded"
      assert html =~ "lanes-msg-content"
    end

    test "tool badges render for messages with tool_use blocks" do
      lane = %{
        agent_name: "tool-agent",
        session: %{session_id: "session-tool", cwd: "/tmp/test"},
        messages: [
          %{
            id: "tool-msg-1",
            uuid: "uuid-tool-1",
            type: :assistant,
            role: :assistant,
            content: %{
              "blocks" => [
                %{"type" => "tool_use", "name" => "Bash", "input" => %{}},
                %{"type" => "tool_use", "name" => "Read", "input" => %{}}
              ]
            },
            timestamp: ~U[2026-02-01 10:00:00Z]
          }
        ],
        rendered_lines: [],
        idle_periods: [],
        started_at: ~U[2026-02-01 10:00:00Z],
        ended_at: ~U[2026-02-01 10:30:00Z]
      }

      rows = [
        %{
          timestamp: ~U[2026-02-01 10:00:00Z],
          cells: %{"tool-agent" => hd(lane.messages)}
        }
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: [lane],
          rows: rows
        )

      assert html =~ "lanes-tool-badge"
      assert html =~ "Bash"
      assert html =~ "Read"
    end
  end

  describe "format_duration/2" do
    test "formats seconds" do
      assert LanesComponents.format_duration(
               ~U[2026-02-01 10:00:00Z],
               ~U[2026-02-01 10:00:30Z]
             ) == "30s"
    end

    test "formats minutes" do
      assert LanesComponents.format_duration(
               ~U[2026-02-01 10:00:00Z],
               ~U[2026-02-01 10:15:00Z]
             ) == "15m"
    end

    test "formats hours" do
      assert LanesComponents.format_duration(
               ~U[2026-02-01 10:00:00Z],
               ~U[2026-02-01 12:30:00Z]
             ) == "2h 30m"
    end

    test "returns empty string for nil timestamps" do
      assert LanesComponents.format_duration(nil, nil) == ""
    end
  end

  describe "sanitize_agent_name/1" do
    test "lowercases and replaces spaces" do
      assert LanesComponents.sanitize_agent_name("Team Lead") == "team-lead"
    end
  end
end
