defmodule Spotter.Transcripts.TeamPipelineIntegrationTest do
  use Spotter.DataCase, async: false

  alias Spotter.Transcripts.Jobs.SyncTranscripts
  alias Spotter.Transcripts.ParallelLanes
  alias Spotter.Transcripts.{Project, Team, TeamMember}

  require Ash.Query

  @fixtures_dir Path.join([__DIR__, "..", "..", "fixtures", "transcripts", "team-overlap"])
                |> Path.expand()

  @lead_file Path.join(@fixtures_dir, "00000000-0000-0000-0000-000000000001.jsonl")
  @tester_file Path.join(@fixtures_dir, "00000000-0000-0000-0000-000000000002.jsonl")
  @impl_file Path.join(@fixtures_dir, "00000000-0000-0000-0000-000000000003.jsonl")

  setup do
    project = Ash.create!(Project, %{name: "test-pipeline", pattern: "^test"})

    %{project: project}
  end

  describe "team fixture pipeline integration" do
    test "syncs 3-member team fixtures and produces correct lanes and overlap regions" do
      # Step 1: Sync all 3 fixture files through the real pipeline
      # Note: sync_session_file/1 falls back to find_project_by_cwd! which
      # matches the DB project's pattern against the fixture cwd basename.
      for file <- [@lead_file, @tester_file, @impl_file] do
        result = SyncTranscripts.sync_session_file(file)

        assert result.status == :ok,
               "Expected sync of #{Path.basename(file)} to succeed, got: #{inspect(result)}"
      end

      # Step 2: Assert 1 Team created with name "impl-test-team"
      teams = Team |> Ash.Query.filter(name == "impl-test-team") |> Ash.read!()
      assert length(teams) == 1
      team = hd(teams)
      assert team.name == "impl-test-team"

      # Step 3: Assert 3 TeamMembers linked to the team
      members = TeamMember |> Ash.Query.filter(team_id == ^team.id) |> Ash.read!()
      assert length(members) == 3
      member_names = Enum.map(members, & &1.agent_name) |> Enum.sort()
      assert member_names == ["implementer", "qa-tester", "team-lead"]

      # Step 4: Compute parallel lanes
      {:ok, result} = ParallelLanes.compute(team.id)

      # Step 5: Assert 3 lanes returned, sorted by started_at
      assert length(result.lanes) == 3

      lane_names = Enum.map(result.lanes, & &1.agent_name)
      assert lane_names == ["team-lead", "qa-tester", "implementer"]

      # Step 6: Assert lane timestamps match fixture data
      [lead_lane, tester_lane, impl_lane] = result.lanes

      assert lead_lane.started_at == ~U[2026-02-20 10:00:00.000Z]
      assert lead_lane.ended_at == ~U[2026-02-20 10:30:00.000Z]

      assert tester_lane.started_at == ~U[2026-02-20 10:05:00.000Z]
      assert tester_lane.ended_at == ~U[2026-02-20 10:20:00.000Z]

      assert impl_lane.started_at == ~U[2026-02-20 10:10:00.000Z]
      assert impl_lane.ended_at == ~U[2026-02-20 10:30:00.000Z]

      # Step 7: Compute overlap regions
      regions = ParallelLanes.overlap_regions(result.lanes)

      assert regions != []

      # Step 8: Assert :full region exists (all 3 agents, ~10:10-10:20)
      full_region = Enum.find(regions, &(&1.type == :full))
      assert full_region != nil
      assert full_region.agent_count == 3
      assert Enum.sort(full_region.agents) == ["implementer", "qa-tester", "team-lead"]
      assert full_region.start == ~U[2026-02-20 10:10:00.000Z]
      assert full_region.end == ~U[2026-02-20 10:20:00.000Z]

      # Step 9: Assert partial overlap regions
      partial_regions = Enum.filter(regions, &(&1.type == :partial))
      assert length(partial_regions) == 2

      early_partial =
        Enum.find(partial_regions, fn r ->
          DateTime.compare(r.start, ~U[2026-02-20 10:05:00.000Z]) == :eq
        end)

      assert early_partial != nil
      assert early_partial.agent_count == 2
      assert Enum.sort(early_partial.agents) == ["qa-tester", "team-lead"]
      assert early_partial.end == ~U[2026-02-20 10:10:00.000Z]

      late_partial =
        Enum.find(partial_regions, fn r ->
          DateTime.compare(r.start, ~U[2026-02-20 10:20:00.000Z]) == :eq
        end)

      assert late_partial != nil
      assert late_partial.agent_count == 2
      assert Enum.sort(late_partial.agents) == ["implementer", "team-lead"]
      assert late_partial.end == ~U[2026-02-20 10:30:00.000Z]

      # Step 10: Assert no overlap before 10:05 (team-lead only period)
      early_regions =
        Enum.filter(regions, fn r ->
          DateTime.compare(r.start, ~U[2026-02-20 10:05:00.000Z]) == :lt
        end)

      assert early_regions == []

      # Step 11: Assert total region count (partial + full + partial = 3)
      assert length(regions) == 3
    end
  end
end
