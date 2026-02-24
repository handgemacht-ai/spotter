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
          type: :assistant,
          role: "assistant",
          content: "message #{i}",
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
      started_at: started_at,
      ended_at: ended_at
    }
  end

  describe "lanes_panel/1" do
    test "renders container and lane columns for 3 lanes" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z]),
        build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z]),
        build_lane("implementer", ~U[2026-02-01 10:10:00Z], ~U[2026-02-01 10:30:00Z])
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes
        )

      assert html =~ "lanes-container"
      assert html =~ "lanes-columns-row"
      assert html =~ "lanes-column"
      refute html =~ "lanes-time-axis"
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

    test "renders lane-column-{name} data-testid on column divs" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z]),
        build_lane("implementer", ~U[2026-02-01 10:10:00Z], ~U[2026-02-01 10:30:00Z])
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes
        )

      assert html =~ ~s(data-testid="lane-column-team-lead")
      assert html =~ ~s(data-testid="lane-column-implementer")
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
      assert html =~ ~s(data-testid="lane-column-agent-1")
    end

    test "renders empty message when lanes list is empty" do
      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: []
        )

      assert html =~ "lanes-container"
      refute html =~ ~s(data-testid="lane-column-)
    end

    test "each lane column has independent scroll via overflow-y style" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z])
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes
        )

      assert html =~ "overflow-y: auto"
    end
  end

  describe "lane_header/1" do
    test "shows agent name, duration, message count, and colored dot" do
      lane = build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z], 3)

      html =
        render_component(&LanesComponents.lane_header/1,
          lane: lane,
          color: "#4ade80"
        )

      assert html =~ "qa-tester"
      assert html =~ "15m"
      assert html =~ "3"
      assert html =~ "#4ade80"
      assert html =~ ~s(data-testid="lane-header")
    end

    test "renders data-testid='lane-name' on agent name span" do
      lane = build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z])

      html =
        render_component(&LanesComponents.lane_header/1,
          lane: lane,
          color: "#4ade80"
        )

      assert html =~ ~s(data-testid="lane-name")
    end

    test "renders data-testid='lane-duration' on duration span" do
      lane = build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z])

      html =
        render_component(&LanesComponents.lane_header/1,
          lane: lane,
          color: "#4ade80"
        )

      assert html =~ ~s(data-testid="lane-duration")
    end
  end

  describe "lane_column/1" do
    test "renders messages using transcript_panel component" do
      lane = build_lane("implementer", ~U[2026-02-01 10:10:00Z], ~U[2026-02-01 10:30:00Z], 3)

      html =
        render_component(&LanesComponents.lane_column/1,
          lane: lane,
          color: "#60a5fa"
        )

      assert html =~ "lanes-column"
      assert html =~ "transcript-row"
      assert html =~ "implementer"
    end

    test "renders empty state when lane has no rendered_lines" do
      lane = %{
        agent_name: "empty-agent",
        session: %{session_id: "session-empty", cwd: "/tmp/test"},
        messages: [],
        rendered_lines: [],
        started_at: ~U[2026-02-01 10:00:00Z],
        ended_at: ~U[2026-02-01 10:30:00Z]
      }

      html =
        render_component(&LanesComponents.lane_column/1,
          lane: lane,
          color: "#60a5fa"
        )

      assert html =~ "No messages."
      assert html =~ ~s(data-testid="transcript-empty")
    end
  end
end
