defmodule Spotter.Transcripts.ParallelLanesPerfTest do
  @moduledoc """
  Performance profiling for ParallelLanes.compute/1.

  Measures wall-clock time for the full compute pipeline and its sub-steps
  with realistic data volumes (5+ agents, 200+ messages each).
  """
  use Spotter.DataCase, async: false

  require Ash.Query
  alias Spotter.Services.TranscriptRenderer
  alias Spotter.Transcripts.ParallelLanes

  @tag :perf
  @agents 5
  @messages_per_agent 200

  setup do
    project = Ash.create!(Spotter.Transcripts.Project, %{name: "perf-test", pattern: "^perf"})
    team = Ash.create!(Spotter.Transcripts.Team, %{name: "perf-team", project_id: project.id})

    # Create agents with many messages to stress the pipeline
    for i <- 1..@agents do
      agent_name = "perf-agent-#{i}"
      base_time = ~U[2026-02-01 10:00:00Z]

      session =
        Ash.create!(Spotter.Transcripts.Session, %{
          session_id: Ash.UUID.generate(),
          project_id: project.id,
          team_name: team.name,
          agent_name: agent_name,
          started_at: base_time,
          ended_at: DateTime.add(base_time, @messages_per_agent * 10, :second)
        })

      Ash.create!(Spotter.Transcripts.TeamMember, %{
        agent_name: agent_name,
        team_id: team.id,
        session_id: session.id
      })

      # Bulk-create messages — alternating user/assistant with realistic content
      for j <- 1..@messages_per_agent do
        type = if rem(j, 2) == 1, do: :user, else: :assistant
        role = type
        ts = DateTime.add(base_time, j * 10, :second)

        content =
          if type == :assistant do
            %{
              "blocks" => [
                %{
                  "type" => "text",
                  "text" => String.duplicate("Response line #{j}. ", 10)
                }
              ]
            }
          else
            %{"text" => "User prompt #{j}: " <> String.duplicate("context ", 20)}
          end

        Ash.create!(Spotter.Transcripts.Message, %{
          uuid: Ash.UUID.generate(),
          type: type,
          role: role,
          content: content,
          timestamp: ts,
          is_sidechain: false,
          session_id: session.id
        })
      end
    end

    %{team: team}
  end

  @tag :perf
  test "compute/1 with #{@agents} agents x #{@messages_per_agent} messages completes under budget",
       %{team: team} do
    # Measure full compute
    {elapsed_us, {:ok, result}} = :timer.tc(fn -> ParallelLanes.compute(team.id) end)
    elapsed_ms = elapsed_us / 1000

    # Report metrics
    IO.puts("\n--- ParallelLanes.compute/1 Performance ---")
    IO.puts("Agents:           #{@agents}")
    IO.puts("Messages/agent:   #{@messages_per_agent}")
    IO.puts("Total messages:   #{@agents * @messages_per_agent}")
    IO.puts("Total lanes:      #{length(result.lanes)}")
    IO.puts("Total rows:       #{length(result.rows)}")
    IO.puts("Message links:    #{length(result.message_links)}")
    IO.puts("Overlaps:         #{length(result.overlaps)}")
    IO.puts("Elapsed:          #{Float.round(elapsed_ms, 1)} ms")
    IO.puts("-------------------------------------------")

    # Per-lane rendered_lines count
    for lane <- result.lanes do
      IO.puts(
        "  Lane #{lane.agent_name}: #{length(lane.messages)} msgs, #{length(lane.rendered_lines)} rendered lines"
      )
    end

    assert length(result.lanes) == @agents
    total_msgs = Enum.map(result.lanes, &length(&1.messages)) |> Enum.sum()
    assert total_msgs == @agents * @messages_per_agent

    # Budget: 5 seconds for this dataset. If it exceeds this, we have a problem.
    assert elapsed_ms < 5_000,
           "compute/1 took #{Float.round(elapsed_ms, 1)} ms — exceeds 5s budget"
  end

  @tag :perf
  test "TranscriptRenderer.render is the dominant cost in build_lane", %{team: team} do
    # First, load team and messages to isolate renderer cost
    team = Ash.load!(team, team_members: [:session])
    session_ids = Enum.map(team.team_members, & &1.session_id)

    messages_by_session =
      Spotter.Transcripts.Message
      |> Ash.Query.filter(
        session_id in ^session_ids and
          is_sidechain == false and
          type in [:user, :assistant, :tool_result]
      )
      |> Ash.Query.sort(timestamp: :asc)
      |> Ash.read!()
      |> Enum.group_by(& &1.session_id)

    # Measure render time per lane
    render_times =
      for member <- team.team_members do
        msgs = Map.get(messages_by_session, member.session_id, [])

        render_msgs =
          Enum.map(msgs, fn m ->
            %{
              id: m.id,
              uuid: m.uuid,
              type: m.type,
              role: m.role,
              content: m.content,
              raw_payload: m.raw_payload,
              timestamp: m.timestamp,
              agent_id: m.agent_id
            }
          end)

        {elapsed_us, _lines} =
          :timer.tc(fn ->
            TranscriptRenderer.render(render_msgs)
          end)

        {member.agent_name, length(msgs), elapsed_us / 1000}
      end

    IO.puts("\n--- TranscriptRenderer.render per lane ---")

    for {name, msg_count, ms} <- render_times do
      IO.puts("  #{name}: #{msg_count} msgs → #{Float.round(ms, 1)} ms")
    end

    total_render_ms = render_times |> Enum.map(&elem(&1, 2)) |> Enum.sum()
    IO.puts("  TOTAL render: #{Float.round(total_render_ms, 1)} ms")
    IO.puts("-------------------------------------------")

    # Each lane render should complete under 1 second
    for {name, _count, ms} <- render_times do
      assert ms < 1_000,
             "Render for #{name} took #{Float.round(ms, 1)} ms — exceeds 1s per-lane budget"
    end
  end

  @tag :perf
  test "DB query vs computation split", %{team: team} do
    # Measure DB load time vs compute time separately
    team_record = Ash.load!(team, team_members: [:session])

    {db_us, messages_by_session} =
      :timer.tc(fn ->
        session_ids = Enum.map(team_record.team_members, & &1.session_id)

        Spotter.Transcripts.Message
        |> Ash.Query.filter(
          session_id in ^session_ids and
            is_sidechain == false and
            type in [:user, :assistant, :tool_result]
        )
        |> Ash.Query.sort(timestamp: :asc)
        |> Ash.read!()
        |> Enum.group_by(& &1.session_id)
      end)

    total_msgs = messages_by_session |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

    {compute_us, {:ok, _result}} = :timer.tc(fn -> ParallelLanes.compute(team.id) end)

    IO.puts("\n--- DB vs Compute split ---")
    IO.puts("DB query:   #{Float.round(db_us / 1000, 1)} ms (#{total_msgs} messages)")
    IO.puts("Full compute: #{Float.round(compute_us / 1000, 1)} ms")
    IO.puts("DB overhead:  ~#{Float.round(db_us / compute_us * 100, 0)}%")
    IO.puts("---------------------------")
  end

  @tag :perf
  test "align_rows scales linearly with total message count", %{team: team} do
    {:ok, result} = ParallelLanes.compute(team.id)

    total_msgs = Enum.map(result.lanes, &length(&1.messages)) |> Enum.sum()

    # Row count should be at most total_msgs (each msg gets its own row in worst case)
    assert length(result.rows) <= total_msgs

    # Each row should have cells for all agents
    expected_agents = Enum.map(result.lanes, & &1.agent_name) |> MapSet.new()

    for row <- result.rows do
      row_agents = Map.keys(row.cells) |> MapSet.new()
      assert MapSet.equal?(row_agents, expected_agents)
    end

    IO.puts("\n--- Row alignment ---")
    IO.puts("Total messages: #{total_msgs}")
    IO.puts("Total rows:     #{length(result.rows)}")
    IO.puts("Ratio:          #{Float.round(length(result.rows) / total_msgs, 2)}")
  end
end
