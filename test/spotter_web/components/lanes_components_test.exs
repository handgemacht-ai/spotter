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

    test "SVG connector overlay and message drawer are rendered" do
      lanes = [
        build_lane("agent-a", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z], 1)
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows
        )

      assert html =~ ~s(data-testid="lanes-connector-overlay")
      assert html =~ ~s(phx-hook="ConnectorOverlay")
      assert html =~ ~s(data-testid="lanes-message-drawer")
      assert html =~ "lanes-drawer-close"
      assert html =~ "Jump to response"
    end

    test "message cells carry data-msg-uuid and data-agent-name" do
      lanes = [
        build_lane("agent-a", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z], 1)
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows
        )

      assert html =~ ~s(data-msg-uuid="uuid-agent-a-1")
      assert html =~ ~s(data-agent-name="agent-a")
    end

    test "link badges carry data attributes for connector hooks" do
      lanes = [
        build_lane("sender", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z], 1),
        build_lane("receiver", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z], 1)
      ]

      # Build a message_link from sender to receiver
      message_links = [
        %{
          sender: "sender",
          recipient: "receiver",
          timestamp: ~U[2026-02-01 10:00:00Z],
          sender_message_uuid: "uuid-sender-1",
          content_preview: "Hello receiver"
        }
      ]

      rows = build_rows(lanes)

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows,
          message_links: message_links
        )

      assert html =~ ~s(data-link-direction="sent")
      assert html =~ ~s(data-link-peer="receiver")
      assert html =~ ~s(data-link-preview="Hello receiver")
      assert html =~ "-&gt; receiver"
    end
  end

  describe "expanded message content rendering parity" do
    test "expanded content includes tool_use and code block text, not just plain text blocks" do
      # A message with mixed block types: text, tool_use, and code
      msg_with_mixed_blocks = %{
        id: "mixed-msg-1",
        uuid: "uuid-mixed-1",
        type: :assistant,
        role: :assistant,
        content: %{
          "blocks" => [
            %{"type" => "text", "text" => "Let me check the file."},
            %{"type" => "tool_use", "name" => "Read", "input" => %{"file_path" => "/tmp/foo.ex"}},
            %{
              "type" => "tool_result",
              "tool_use_id" => "tool-1",
              "content" => "defmodule Foo do\n  def bar, do: :ok\nend"
            },
            %{"type" => "text", "text" => "The file looks correct."}
          ]
        },
        timestamp: ~U[2026-02-01 10:00:00Z]
      }

      lane = %{
        agent_name: "agent-a",
        session: %{session_id: "session-a", cwd: "/tmp/test"},
        messages: [msg_with_mixed_blocks],
        rendered_lines: [
          %{
            line_number: 1,
            line: "Let me check the file.",
            kind: :text,
            render_mode: :plain
          },
          %{
            line_number: 2,
            line: "Read /tmp/foo.ex",
            kind: :tool_use,
            render_mode: :tool_badge
          },
          %{
            line_number: 3,
            line: "defmodule Foo do\n  def bar, do: :ok\nend",
            kind: :tool_result,
            render_mode: :code
          },
          %{
            line_number: 4,
            line: "The file looks correct.",
            kind: :text,
            render_mode: :plain
          }
        ],
        idle_periods: [],
        started_at: ~U[2026-02-01 10:00:00Z],
        ended_at: ~U[2026-02-01 10:30:00Z]
      }

      rows = [
        %{
          timestamp: ~U[2026-02-01 10:00:00Z],
          cells: %{"agent-a" => msg_with_mixed_blocks}
        }
      ]

      html =
        render_component(&LanesComponents.lanes_panel/1,
          lanes: [lane],
          rows: rows,
          expanded_messages: %{"mixed-msg-1" => true}
        )

      # The expanded content should include tool_use information, not just text blocks.
      # Currently extract_text only returns text blocks and ignores tool_use/tool_result,
      # losing critical information that the normal transcript renderer shows.
      assert html =~ "Let me check the file."
      assert html =~ "The file looks correct."

      # The expanded content area (inside lanes-msg-content) should include tool details.
      # Currently extract_text only extracts "text" type blocks and ignores tool_use/tool_result,
      # losing critical information that the normal transcript renderer shows.
      #
      # We check the content within the expanded area specifically:
      assert html =~ "foo.ex",
             "Expanded content should show tool_use file path (foo.ex) but extract_text drops tool_use blocks"

      assert html =~ "defmodule Foo",
             "Expanded content should show tool_result code but extract_text drops tool_result blocks"
    end
  end

  test "received link badges only appear on the correct message, not all messages in recipient lane" do
    # Receiver has 3 messages; only one should get the received badge
    receiver_messages = [
      %{
        id: "recv-msg-1",
        uuid: "uuid-recv-1",
        type: :assistant,
        role: :assistant,
        content: %{"text" => "first message"},
        timestamp: ~U[2026-02-01 10:01:00Z]
      },
      %{
        id: "recv-msg-2",
        uuid: "uuid-recv-2",
        type: :assistant,
        role: :assistant,
        content: %{"text" => "second message"},
        timestamp: ~U[2026-02-01 10:05:00Z]
      },
      %{
        id: "recv-msg-3",
        uuid: "uuid-recv-3",
        type: :assistant,
        role: :assistant,
        content: %{"text" => "third message"},
        timestamp: ~U[2026-02-01 10:10:00Z]
      }
    ]

    sender_lane = build_lane("sender", ~U[2026-02-01 10:00:00Z], ~U[2026-02-01 10:30:00Z], 1)

    receiver_lane = %{
      agent_name: "receiver",
      session: %{session_id: "session-receiver", cwd: "/tmp/test"},
      messages: receiver_messages,
      rendered_lines: receiver_messages,
      idle_periods: [],
      started_at: ~U[2026-02-01 10:00:00Z],
      ended_at: ~U[2026-02-01 10:30:00Z]
    }

    lanes = [sender_lane, receiver_lane]

    # Link sent at 10:00 from sender to receiver
    message_links = [
      %{
        sender: "sender",
        recipient: "receiver",
        timestamp: ~U[2026-02-01 10:00:00Z],
        sender_message_uuid: "uuid-sender-1",
        content_preview: "Hello receiver"
      }
    ]

    all_agents = Enum.map(lanes, & &1.agent_name)

    rows =
      Enum.map(receiver_messages, fn msg ->
        cells = Map.new(all_agents, fn name -> {name, if(name == "receiver", do: msg)} end)
        %{timestamp: msg.timestamp, cells: cells}
      end)

    # Pre-compute received_link_targets (moved from component to ParallelLanes)
    # The link from sender at 10:00 should target uuid-recv-1 (first msg at or after 10:00)
    received_link_targets = %{
      {"sender", "receiver", "uuid-sender-1"} => "uuid-recv-1"
    }

    html =
      render_component(&LanesComponents.lanes_panel/1,
        lanes: lanes,
        rows: rows,
        message_links: message_links,
        received_link_targets: received_link_targets
      )

    # The received badge should appear at most once — only on the message
    # temporally closest to the send event, NOT on every message in the receiver lane.
    received_badge_count =
      html
      |> String.split("data-link-direction=\"received\"")
      |> length()
      |> Kernel.-(1)

    assert received_badge_count == 1,
           "Expected exactly 1 received badge but found #{received_badge_count}. " <>
             "Received badges are leaking to every message in the recipient lane."
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
