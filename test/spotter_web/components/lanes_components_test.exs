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

    %{
      agent_name: agent_name,
      session: %{session_id: "session-#{agent_name}", cwd: "/tmp/test"},
      messages: messages,
      started_at: started_at,
      ended_at: ended_at
    }
  end

  describe "lanes_panel/1" do
    test "renders container with time axis and lane columns for 3 lanes" do
      lanes = [
        build_lane("team-lead", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z]),
        build_lane("qa-tester", ~U[2026-02-01 10:05:00Z], ~U[2026-02-01 10:20:00Z]),
        build_lane("implementer", ~U[2026-02-01 10:10:00Z], ~U[2026-02-01 10:30:00Z])
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          overlaps: [],
          timeline: %{earliest: ~U[2026-02-01 10:00:00Z], latest: ~U[2026-02-01 10:30:00Z]}
        )

      assert html =~ "lanes-container"
      assert html =~ "lanes-time-axis"
      assert html =~ "lanes-column"
    end

    test "renders empty message when lanes list is empty" do
      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: [],
          overlaps: [],
          timeline: %{earliest: nil, latest: nil}
        )

      assert html =~ "lanes-container"
      refute html =~ "lanes-column"
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
  end

  describe "lane_column/1" do
    test "renders messages wrapped in .lanes-entry elements" do
      lane = build_lane("implementer", ~U[2026-02-01 10:10:00Z], ~U[2026-02-01 10:30:00Z], 3)

      html =
        render_component(&LanesComponents.lane_column/1,
          lane: lane,
          color: "#60a5fa"
        )

      assert html =~ "lanes-column"
      assert html =~ "lanes-entry"
      assert html =~ "implementer"
    end
  end

  describe "time_axis/1" do
    test "renders time labels and gutter bars for full overlaps" do
      overlaps = [
        %{
          start: ~U[2026-02-01 10:10:00Z],
          end: ~U[2026-02-01 10:20:00Z],
          agents: ["team-lead", "qa-tester", "implementer"],
          agent_count: 3,
          type: :full
        }
      ]

      html =
        render_component(&LanesComponents.time_axis/1,
          timeline: %{earliest: ~U[2026-02-01 10:00:00Z], latest: ~U[2026-02-01 10:30:00Z]},
          overlaps: overlaps
        )

      assert html =~ "lanes-time-axis"
      assert html =~ "lanes-gutter-bar"
    end

    test "renders partial gutter bar for partial overlaps" do
      overlaps = [
        %{
          start: ~U[2026-02-01 10:05:00Z],
          end: ~U[2026-02-01 10:15:00Z],
          agents: ["team-lead", "qa-tester"],
          agent_count: 2,
          type: :partial
        }
      ]

      html =
        render_component(&LanesComponents.time_axis/1,
          timeline: %{earliest: ~U[2026-02-01 10:00:00Z], latest: ~U[2026-02-01 10:30:00Z]},
          overlaps: overlaps
        )

      assert html =~ "lanes-time-axis"
      assert html =~ "lanes-gutter-bar"
      assert html =~ "partial"
    end
  end
end
