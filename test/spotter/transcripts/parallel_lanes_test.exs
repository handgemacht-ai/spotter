defmodule Spotter.Transcripts.ParallelLanesTest do
  use Spotter.DataCase, async: false

  alias Spotter.Transcripts.ParallelLanes

  setup do
    project = Ash.create!(Spotter.Transcripts.Project, %{name: "test", pattern: "^test"})
    team = Ash.create!(Spotter.Transcripts.Team, %{name: "test-team", project_id: project.id})

    %{project: project, team: team}
  end

  describe "compute/1" do
    test "non-existent team returns error" do
      assert {:error, :not_found} = ParallelLanes.compute(Ash.UUID.generate())
    end

    test "empty team returns empty lanes", %{team: team} do
      assert {:ok, %{lanes: []}} = ParallelLanes.compute(team.id)
    end

    test "team with 3 members returns 3 lanes", %{team: team, project: project} do
      for name <- ["agent-a", "agent-b", "agent-c"] do
        create_member_with_messages(team, project, name, [
          {:user, :user, ~U[2026-02-01 12:00:00Z]},
          {:assistant, :assistant, ~U[2026-02-01 12:00:01Z]}
        ])
      end

      {:ok, result} = ParallelLanes.compute(team.id)

      assert length(result.lanes) == 3

      lane_names = Enum.map(result.lanes, & &1.agent_name) |> Enum.sort()
      assert lane_names == ["agent-a", "agent-b", "agent-c"]
    end

    test "lane messages are ordered by timestamp", %{team: team, project: project} do
      create_member_with_messages(team, project, "ordered-agent", [
        {:assistant, :assistant, ~U[2026-02-01 12:00:03Z]},
        {:user, :user, ~U[2026-02-01 12:00:01Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:02Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      lane = hd(result.lanes)
      timestamps = Enum.map(lane.messages, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps, DateTime)
    end

    test "timeline reflects global min/max across all members", %{team: team, project: project} do
      create_member_with_messages(team, project, "early-agent", [
        {:user, :user, ~U[2026-02-01 10:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:00Z]}
      ])

      create_member_with_messages(team, project, "late-agent", [
        {:user, :user, ~U[2026-02-01 11:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 14:00:00Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      assert result.timeline.earliest == ~U[2026-02-01 10:00:00Z]
      assert result.timeline.latest == ~U[2026-02-01 14:00:00Z]
    end

    test "sidechain messages are filtered out", %{team: team, project: project} do
      session =
        create_member_with_messages(team, project, "side-agent", [
          {:user, :user, ~U[2026-02-01 12:00:00Z]}
        ])

      # Add a sidechain message directly
      Ash.create!(Spotter.Transcripts.Message, %{
        uuid: Ash.UUID.generate(),
        type: :assistant,
        role: :assistant,
        content: %{"text" => "sidechain response"},
        timestamp: ~U[2026-02-01 12:00:01Z],
        is_sidechain: true,
        session_id: session.id
      })

      {:ok, result} = ParallelLanes.compute(team.id)

      lane = hd(result.lanes)
      assert length(lane.messages) == 1
      refute Enum.any?(lane.messages, & &1.is_sidechain)
    end

    test "progress and system messages are filtered out", %{team: team, project: project} do
      session =
        create_member_with_messages(team, project, "filter-agent", [
          {:user, :user, ~U[2026-02-01 12:00:00Z]},
          {:assistant, :assistant, ~U[2026-02-01 12:00:01Z]}
        ])

      # Add progress and system messages directly
      for {type, ts} <- [
            {:progress, ~U[2026-02-01 12:00:02Z]},
            {:system, ~U[2026-02-01 12:00:03Z]}
          ] do
        Ash.create!(Spotter.Transcripts.Message, %{
          uuid: Ash.UUID.generate(),
          type: type,
          content: %{"text" => "noise"},
          timestamp: ts,
          is_sidechain: false,
          session_id: session.id
        })
      end

      {:ok, result} = ParallelLanes.compute(team.id)

      lane = hd(result.lanes)
      assert length(lane.messages) == 2
      types = Enum.map(lane.messages, & &1.type)
      refute :progress in types
      refute :system in types
    end

    test "compute/1 result includes overlaps key", %{team: team, project: project} do
      create_member_with_messages(team, project, "solo-agent", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      assert Map.has_key?(result, :overlaps)
      assert is_list(result.overlaps)
    end

    test "compute/1 returns empty overlaps for single-member team", %{
      team: team,
      project: project
    } do
      create_member_with_messages(team, project, "lone-agent", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:01Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      assert result.overlaps == []
    end

    test "compute/1 returns non-empty overlaps for overlapping members", %{
      team: team,
      project: project
    } do
      create_member_with_messages(team, project, "agent-x", [
        {:user, :user, ~U[2026-02-01 10:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:00Z]}
      ])

      create_member_with_messages(team, project, "agent-y", [
        {:user, :user, ~U[2026-02-01 11:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 13:00:00Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      assert result.overlaps != []

      [region | _] = result.overlaps
      assert region.agent_count == 2
      assert Enum.sort(region.agents) == ["agent-x", "agent-y"]
    end

    test "lanes are sorted by started_at", %{team: team, project: project} do
      create_member_with_messages(team, project, "late-starter", [
        {:user, :user, ~U[2026-02-01 15:00:00Z]}
      ])

      create_member_with_messages(team, project, "early-starter", [
        {:user, :user, ~U[2026-02-01 10:00:00Z]}
      ])

      create_member_with_messages(team, project, "mid-starter", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      lane_names = Enum.map(result.lanes, & &1.agent_name)
      assert lane_names == ["early-starter", "mid-starter", "late-starter"]
    end
  end

  describe "overlap_regions/1" do
    test "empty lanes list returns empty list" do
      assert ParallelLanes.overlap_regions([]) == []
    end

    test "single lane returns empty list" do
      lanes = [
        %{
          agent_name: "solo",
          started_at: ~U[2026-02-01 10:00:00Z],
          ended_at: ~U[2026-02-01 11:00:00Z]
        }
      ]

      assert ParallelLanes.overlap_regions(lanes) == []
    end

    test "two non-overlapping lanes returns empty list" do
      lanes = [
        %{
          agent_name: "agent-a",
          started_at: ~U[2026-02-01 10:00:00Z],
          ended_at: ~U[2026-02-01 11:00:00Z]
        },
        %{
          agent_name: "agent-b",
          started_at: ~U[2026-02-01 12:00:00Z],
          ended_at: ~U[2026-02-01 13:00:00Z]
        }
      ]

      assert ParallelLanes.overlap_regions(lanes) == []
    end

    test "two fully overlapping lanes returns one :full region" do
      lanes = [
        %{
          agent_name: "agent-a",
          started_at: ~U[2026-02-01 10:00:00Z],
          ended_at: ~U[2026-02-01 12:00:00Z]
        },
        %{
          agent_name: "agent-b",
          started_at: ~U[2026-02-01 10:00:00Z],
          ended_at: ~U[2026-02-01 12:00:00Z]
        }
      ]

      [region] = ParallelLanes.overlap_regions(lanes)

      assert region.start == ~U[2026-02-01 10:00:00Z]
      assert region.end == ~U[2026-02-01 12:00:00Z]
      assert region.type == :full
      assert region.agent_count == 2
      assert Enum.sort(region.agents) == ["agent-a", "agent-b"]
    end

    test "two partially overlapping lanes returns one region covering the overlap" do
      lanes = [
        %{
          agent_name: "agent-a",
          started_at: ~U[2026-02-01 10:00:00Z],
          ended_at: ~U[2026-02-01 12:00:00Z]
        },
        %{
          agent_name: "agent-b",
          started_at: ~U[2026-02-01 11:00:00Z],
          ended_at: ~U[2026-02-01 13:00:00Z]
        }
      ]

      [region] = ParallelLanes.overlap_regions(lanes)

      assert region.start == ~U[2026-02-01 11:00:00Z]
      assert region.end == ~U[2026-02-01 12:00:00Z]
      assert region.type == :full
      assert region.agent_count == 2
    end

    test "three lanes, two overlap but third is sequential → :partial region" do
      lanes = [
        %{
          agent_name: "agent-a",
          started_at: ~U[2026-02-01 10:00:00Z],
          ended_at: ~U[2026-02-01 12:00:00Z]
        },
        %{
          agent_name: "agent-b",
          started_at: ~U[2026-02-01 11:00:00Z],
          ended_at: ~U[2026-02-01 13:00:00Z]
        },
        %{
          agent_name: "agent-c",
          started_at: ~U[2026-02-01 14:00:00Z],
          ended_at: ~U[2026-02-01 15:00:00Z]
        }
      ]

      [region] = ParallelLanes.overlap_regions(lanes)

      assert region.start == ~U[2026-02-01 11:00:00Z]
      assert region.end == ~U[2026-02-01 12:00:00Z]
      assert region.type == :partial
      assert region.agent_count == 2
      assert Enum.sort(region.agents) == ["agent-a", "agent-b"]
    end

    test "three lanes all overlapping returns one :full region" do
      lanes = [
        %{
          agent_name: "agent-a",
          started_at: ~U[2026-02-01 10:00:00Z],
          ended_at: ~U[2026-02-01 14:00:00Z]
        },
        %{
          agent_name: "agent-b",
          started_at: ~U[2026-02-01 11:00:00Z],
          ended_at: ~U[2026-02-01 13:00:00Z]
        },
        %{
          agent_name: "agent-c",
          started_at: ~U[2026-02-01 12:00:00Z],
          ended_at: ~U[2026-02-01 15:00:00Z]
        }
      ]

      regions = ParallelLanes.overlap_regions(lanes)

      full_region = Enum.find(regions, &(&1.type == :full))
      assert full_region != nil
      assert full_region.agent_count == 3
      assert Enum.sort(full_region.agents) == ["agent-a", "agent-b", "agent-c"]
    end

    test "multiple separate overlap regions returned sorted by start" do
      lanes = [
        %{
          agent_name: "agent-a",
          started_at: ~U[2026-02-01 10:00:00Z],
          ended_at: ~U[2026-02-01 12:00:00Z]
        },
        %{
          agent_name: "agent-b",
          started_at: ~U[2026-02-01 11:00:00Z],
          ended_at: ~U[2026-02-01 13:00:00Z]
        },
        %{
          agent_name: "agent-c",
          started_at: ~U[2026-02-01 15:00:00Z],
          ended_at: ~U[2026-02-01 17:00:00Z]
        },
        %{
          agent_name: "agent-d",
          started_at: ~U[2026-02-01 16:00:00Z],
          ended_at: ~U[2026-02-01 18:00:00Z]
        }
      ]

      regions = ParallelLanes.overlap_regions(lanes)

      assert length(regions) >= 2

      starts = Enum.map(regions, & &1.start)
      assert starts == Enum.sort(starts, DateTime)

      first = hd(regions)
      assert Enum.sort(first.agents) == ["agent-a", "agent-b"]

      last = List.last(regions)
      assert Enum.sort(last.agents) == ["agent-c", "agent-d"]
    end

    test "lanes with nil started_at/ended_at are filtered out without crash" do
      lanes = [
        %{
          agent_name: "agent-a",
          started_at: ~U[2026-02-01 10:00:00Z],
          ended_at: ~U[2026-02-01 12:00:00Z]
        },
        %{agent_name: "nil-start", started_at: nil, ended_at: ~U[2026-02-01 12:00:00Z]},
        %{agent_name: "nil-end", started_at: ~U[2026-02-01 10:00:00Z], ended_at: nil},
        %{agent_name: "nil-both", started_at: nil, ended_at: nil}
      ]

      result = ParallelLanes.overlap_regions(lanes)

      assert is_list(result)
      # No overlap possible with only one valid lane
      assert result == []
    end

    test "overlap region agents list contains correct agent names" do
      lanes = [
        %{
          agent_name: "navigator",
          started_at: ~U[2026-02-01 10:00:00Z],
          ended_at: ~U[2026-02-01 14:00:00Z]
        },
        %{
          agent_name: "implementer",
          started_at: ~U[2026-02-01 12:00:00Z],
          ended_at: ~U[2026-02-01 16:00:00Z]
        },
        %{
          agent_name: "tester",
          started_at: ~U[2026-02-01 13:00:00Z],
          ended_at: ~U[2026-02-01 15:00:00Z]
        }
      ]

      regions = ParallelLanes.overlap_regions(lanes)

      # Find the region where all 3 overlap (13:00-14:00)
      full_region = Enum.find(regions, &(&1.type == :full))
      assert full_region != nil
      assert full_region.start == ~U[2026-02-01 13:00:00Z]
      assert full_region.end == ~U[2026-02-01 14:00:00Z]
      assert Enum.sort(full_region.agents) == ["implementer", "navigator", "tester"]
      assert full_region.agent_count == 3
    end
  end

  describe "idle period detection" do
    test "lane includes idle_periods for gaps between consecutive messages", %{
      team: team,
      project: project
    } do
      # Three messages with a 10-minute gap between msg2 and msg3
      create_member_with_messages(team, project, "idle-agent", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:01:00Z]},
        # 10-minute gap here
        {:user, :user, ~U[2026-02-01 12:11:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:12:00Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      lane = hd(result.lanes)
      assert Map.has_key?(lane, :idle_periods), "lane should include :idle_periods key"
      assert is_list(lane.idle_periods)

      # Should detect at least one idle period (the 10-minute gap)
      assert lane.idle_periods != []

      idle = hd(lane.idle_periods)
      assert %{start: _, end: _, duration_seconds: _} = idle
      assert idle.duration_seconds >= 600
    end

    test "no idle periods when messages are closely spaced", %{team: team, project: project} do
      # Messages only 1 second apart — no significant idle gap
      create_member_with_messages(team, project, "busy-agent", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:01Z]},
        {:user, :user, ~U[2026-02-01 12:00:02Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:03Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      lane = hd(result.lanes)
      assert Map.has_key?(lane, :idle_periods)
      # With default threshold (e.g. 60s), no idle periods expected
      assert lane.idle_periods == []
    end
  end

  describe "inter-agent message linking" do
    test "compute/1 result includes message_links between lanes", %{
      team: team,
      project: project
    } do
      # Agent A sends a message to Agent B via SendMessage tool
      _session_a =
        create_member_with_messages(team, project, "agent-a", [
          {:user, :user, ~U[2026-02-01 12:00:00Z]},
          {:assistant, :assistant, ~U[2026-02-01 12:00:01Z]}
        ])

      _session_b =
        create_member_with_messages(team, project, "agent-b", [
          {:user, :user, ~U[2026-02-01 12:00:02Z]},
          {:assistant, :assistant, ~U[2026-02-01 12:00:03Z]}
        ])

      # Create a SendMessage tool call linking agent-a → agent-b
      create_send_message_tool_call(team, "agent-a", "agent-b", ~U[2026-02-01 12:00:01Z])

      {:ok, result} = ParallelLanes.compute(team.id)

      assert Map.has_key?(result, :message_links),
             "compute/1 result should include :message_links"

      assert is_list(result.message_links)
      assert result.message_links != []

      link = hd(result.message_links)
      assert link.sender == "agent-a"
      assert link.recipient == "agent-b"
      assert %DateTime{} = link.timestamp
    end

    test "no message_links when no SendMessage tool calls exist", %{
      team: team,
      project: project
    } do
      create_member_with_messages(team, project, "solo-a", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:01Z]}
      ])

      create_member_with_messages(team, project, "solo-b", [
        {:user, :user, ~U[2026-02-01 12:00:02Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:03Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      assert Map.has_key?(result, :message_links)
      assert result.message_links == []
    end
  end

  describe "compute_and_cache/1" do
    test "caches result and load_cached returns it", %{team: team, project: project} do
      create_member_with_messages(team, project, "cache-agent", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:01Z]}
      ])

      assert {:miss, nil} = ParallelLanes.load_cached(team.id)

      {:ok, computed} = ParallelLanes.compute_and_cache(team.id)
      assert length(computed.lanes) == 1

      {:ok, cached} = ParallelLanes.load_cached(team.id)
      assert length(cached.lanes) == 1
      assert hd(cached.lanes).agent_name == "cache-agent"
    end

    test "cached lanes preserve message fields", %{team: team, project: project} do
      create_member_with_messages(team, project, "field-agent", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:01Z]}
      ])

      {:ok, _} = ParallelLanes.compute_and_cache(team.id)
      {:ok, cached} = ParallelLanes.load_cached(team.id)

      lane = hd(cached.lanes)
      msg = hd(lane.messages)
      assert is_binary(msg.uuid)
      assert msg.type in [:user, :assistant]
      assert %DateTime{} = msg.timestamp
    end

    test "cached result preserves timeline and overlaps", %{team: team, project: project} do
      create_member_with_messages(team, project, "tl-agent-a", [
        {:user, :user, ~U[2026-02-01 10:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:00Z]}
      ])

      create_member_with_messages(team, project, "tl-agent-b", [
        {:user, :user, ~U[2026-02-01 11:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 13:00:00Z]}
      ])

      {:ok, _} = ParallelLanes.compute_and_cache(team.id)
      {:ok, cached} = ParallelLanes.load_cached(team.id)

      assert %{earliest: %DateTime{}, latest: %DateTime{}} = cached.timeline
      assert cached.overlaps != []
    end

    test "cached rows preserve cell structure", %{team: team, project: project} do
      create_member_with_messages(team, project, "row-cache-a", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]}
      ])

      create_member_with_messages(team, project, "row-cache-b", [
        {:user, :user, ~U[2026-02-01 12:00:05Z]}
      ])

      {:ok, _} = ParallelLanes.compute_and_cache(team.id)
      {:ok, cached} = ParallelLanes.load_cached(team.id)

      assert cached.rows != []
      first_row = hd(cached.rows)
      assert %{timestamp: %DateTime{}, cells: cells} = first_row
      assert is_map(cells)
    end

    test "re-caching overwrites previous cache", %{team: team, project: project} do
      create_member_with_messages(team, project, "overwrite-agent", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]}
      ])

      {:ok, _} = ParallelLanes.compute_and_cache(team.id)
      {:ok, first} = ParallelLanes.load_cached(team.id)
      assert length(first.lanes) == 1

      # Add another member and re-cache
      create_member_with_messages(team, project, "overwrite-agent-2", [
        {:user, :user, ~U[2026-02-01 12:00:01Z]}
      ])

      {:ok, _} = ParallelLanes.compute_and_cache(team.id)
      {:ok, second} = ParallelLanes.load_cached(team.id)
      assert length(second.lanes) == 2
    end
  end

  describe "row alignment" do
    test "align_rows/1 normalizes turns across lanes into time-ordered rows", %{
      team: team,
      project: project
    } do
      # Agent A: messages at :00, :02
      # Agent B: messages at :01, :03
      # Expected row order: A(:00), B(:01), A(:02), B(:03)
      create_member_with_messages(team, project, "row-agent-a", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:02Z]}
      ])

      create_member_with_messages(team, project, "row-agent-b", [
        {:user, :user, ~U[2026-02-01 12:00:01Z]},
        {:assistant, :assistant, ~U[2026-02-01 12:00:03Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      assert Map.has_key?(result, :rows),
             "compute/1 result should include :rows for table alignment"

      assert is_list(result.rows)
      assert result.rows != []

      # Each row should have a timestamp and a map of lane_name => message (or nil)
      first_row = hd(result.rows)
      assert %{timestamp: %DateTime{}, cells: cells} = first_row
      assert is_map(cells)

      # Rows should be sorted by timestamp
      timestamps = Enum.map(result.rows, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps, DateTime)
    end

    test "align_rows/1 fills nil cells for lanes with no message at that timestamp", %{
      team: team,
      project: project
    } do
      # Agent A has a message at :00, Agent B does not
      create_member_with_messages(team, project, "fill-agent-a", [
        {:user, :user, ~U[2026-02-01 12:00:00Z]}
      ])

      create_member_with_messages(team, project, "fill-agent-b", [
        {:user, :user, ~U[2026-02-01 12:00:05Z]}
      ])

      {:ok, result} = ParallelLanes.compute(team.id)

      assert result.rows != []

      # First row (at :00) should have fill-agent-a present, fill-agent-b nil
      first_row = hd(result.rows)
      assert first_row.cells["fill-agent-a"] != nil
      assert first_row.cells["fill-agent-b"] == nil

      # Last row (at :05) should have fill-agent-b present, fill-agent-a nil
      last_row = List.last(result.rows)
      assert last_row.cells["fill-agent-b"] != nil
      assert last_row.cells["fill-agent-a"] == nil
    end
  end

  defp create_send_message_tool_call(team, sender_agent, recipient_agent, timestamp) do
    # Find the sender's session via team member
    team = Ash.load!(team, team_members: [:session])
    sender_member = Enum.find(team.team_members, &(&1.agent_name == sender_agent))

    # Create a SendMessage tool call on the sender's session
    tool_use_id = Ash.UUID.generate()

    Ash.create!(Spotter.Transcripts.ToolCall, %{
      tool_use_id: tool_use_id,
      tool_name: "SendMessage",
      session_id: sender_member.session_id
    })

    # Create the assistant message with SendMessage content block
    Ash.create!(Spotter.Transcripts.Message, %{
      uuid: Ash.UUID.generate(),
      type: :assistant,
      role: :assistant,
      content: %{
        "blocks" => [
          %{
            "type" => "tool_use",
            "id" => tool_use_id,
            "name" => "SendMessage",
            "input" => %{
              "type" => "message",
              "recipient" => recipient_agent,
              "content" => "test inter-agent message"
            }
          }
        ]
      },
      timestamp: timestamp,
      is_sidechain: false,
      tool_use_id: tool_use_id,
      session_id: sender_member.session_id
    })
  end

  defp create_member_with_messages(team, project, agent_name, messages_data) do
    session =
      Ash.create!(Spotter.Transcripts.Session, %{
        session_id: Ash.UUID.generate(),
        project_id: project.id,
        team_name: team.name,
        agent_name: agent_name
      })

    Ash.create!(Spotter.Transcripts.TeamMember, %{
      agent_name: agent_name,
      team_id: team.id,
      session_id: session.id
    })

    for {type, role, timestamp} <- messages_data do
      Ash.create!(Spotter.Transcripts.Message, %{
        uuid: Ash.UUID.generate(),
        type: type,
        role: role,
        content: %{"text" => "test message"},
        timestamp: timestamp,
        is_sidechain: false,
        session_id: session.id
      })
    end

    session
  end
end
