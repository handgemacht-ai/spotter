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
