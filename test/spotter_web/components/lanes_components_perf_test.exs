defmodule SpotterWeb.LanesComponentsPerfTest do
  @moduledoc """
  Performance test for LanesComponents.lanes_panel/1.

  Asserts that rendering scales linearly with cells, not quadratically.
  The current implementation calls find_message_links per cell with O(links)
  scan each time, causing O(cells × links) total work. The fix should
  pre-compute a links_by_cell index for O(1) lookups per cell.
  """
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias SpotterWeb.LanesComponents

  @endpoint SpotterWeb.Endpoint

  @agents 8
  @messages_per_agent 200
  @links_count 200

  defp build_stress_lanes do
    for i <- 1..@agents do
      agent = "agent-#{i}"
      base = ~U[2026-02-01 10:00:00Z]

      messages =
        for j <- 1..@messages_per_agent do
          ts = DateTime.add(base, j * 10, :second)

          %{
            id: "#{agent}-msg-#{j}",
            uuid: "uuid-#{agent}-#{j}",
            type: :assistant,
            role: :assistant,
            content: %{"text" => "message #{j} from #{agent}"},
            timestamp: ts
          }
        end

      %{
        agent_name: agent,
        session: %{session_id: "session-#{agent}", cwd: "/tmp/test"},
        messages: messages,
        rendered_lines: [],
        idle_periods: [],
        started_at: base,
        ended_at: DateTime.add(base, @messages_per_agent * 10, :second)
      }
    end
  end

  defp build_stress_rows(lanes) do
    all_agents = Enum.map(lanes, & &1.agent_name)

    lanes
    |> Enum.flat_map(fn lane ->
      Enum.map(lane.messages, fn msg ->
        {msg.timestamp, lane.agent_name, msg}
      end)
    end)
    |> Enum.sort_by(&elem(&1, 0), DateTime)
    |> Enum.map(fn {ts, agent, msg} ->
      cells = Map.new(all_agents, fn name -> {name, if(name == agent, do: msg)} end)
      %{timestamp: ts, cells: cells}
    end)
  end

  defp build_stress_links(lanes) do
    agents = Enum.map(lanes, & &1.agent_name)

    for i <- 1..@links_count do
      sender = Enum.at(agents, rem(i, @agents))
      recipient = Enum.at(agents, rem(i + 1, @agents))

      %{
        sender: sender,
        recipient: recipient,
        timestamp: DateTime.add(~U[2026-02-01 10:00:00Z], i * 10, :second),
        sender_message_uuid: "uuid-#{sender}-#{rem(i, @messages_per_agent) + 1}",
        content_preview: "Link #{i}"
      }
    end
  end

  test "lanes_panel renders #{@agents} agents × #{@messages_per_agent} msgs × #{@links_count} links under 500ms" do
    lanes = build_stress_lanes()
    rows = build_stress_rows(lanes)
    links = build_stress_links(lanes)

    total_cells = length(rows) * @agents

    {elapsed_us, html} =
      :timer.tc(fn ->
        render_component(&LanesComponents.lanes_panel/1,
          lanes: lanes,
          rows: rows,
          message_links: links
        )
      end)

    elapsed_ms = elapsed_us / 1000

    IO.puts("\n--- LanesComponents.lanes_panel/1 Render Performance ---")
    IO.puts("Agents:         #{@agents}")
    IO.puts("Msgs/agent:     #{@messages_per_agent}")
    IO.puts("Total cells:    #{total_cells}")
    IO.puts("Message links:  #{length(links)}")
    IO.puts("Elapsed:        #{Float.round(elapsed_ms, 1)} ms")
    IO.puts("Per-cell avg:   #{Float.round(elapsed_ms / total_cells * 1000, 1)} μs")
    IO.puts("HTML size:      #{byte_size(html)} bytes")
    IO.puts("-------------------------------------------------------")

    # With O(cells × links) this blows up. With pre-computed index it should be fast.
    assert elapsed_ms < 500,
           "lanes_panel render took #{Float.round(elapsed_ms, 1)} ms for #{total_cells} cells × #{length(links)} links — " <>
             "find_message_links is likely doing O(cells × links) work. " <>
             "Pre-compute a links_by_cell index in lanes_panel for O(1) per-cell lookups."
  end
end
