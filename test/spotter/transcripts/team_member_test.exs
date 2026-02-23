defmodule Spotter.Transcripts.TeamMemberTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Spotter.Repo)
    Sandbox.mode(Spotter.Repo, {:shared, self()})

    project = Ash.create!(Spotter.Transcripts.Project, %{name: "test-project", pattern: "^test"})
    team = Ash.create!(Spotter.Transcripts.Team, %{name: "test-team", project_id: project.id})

    session =
      Ash.create!(Spotter.Transcripts.Session, %{
        session_id: Ash.UUID.generate(),
        project_id: project.id
      })

    %{project: project, team: team, session: session}
  end

  describe "create" do
    test "can create a TeamMember with agent_name, team_id, and session_id", %{
      team: team,
      session: session
    } do
      member =
        Ash.create!(Spotter.Transcripts.TeamMember, %{
          agent_name: "backend-architect",
          team_id: team.id,
          session_id: session.id
        })

      assert member.agent_name == "backend-architect"
      assert member.team_id == team.id
      assert member.session_id == session.id
      assert member.id != nil
    end

    test "agent_name is required", %{team: team, session: session} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(Spotter.Transcripts.TeamMember, %{
          team_id: team.id,
          session_id: session.id
        })
      end
    end

    test "team_id is required", %{session: session} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(Spotter.Transcripts.TeamMember, %{
          agent_name: "orphan-member",
          session_id: session.id
        })
      end
    end

    test "session_id is required", %{team: team} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(Spotter.Transcripts.TeamMember, %{
          agent_name: "orphan-member",
          team_id: team.id
        })
      end
    end
  end

  describe "upsert" do
    test "same team_id+session_id returns the same record", %{team: team, session: session} do
      first =
        Ash.create!(
          Spotter.Transcripts.TeamMember,
          %{agent_name: "architect", team_id: team.id, session_id: session.id},
          upsert?: true,
          upsert_identity: :unique_member_per_team
        )

      second =
        Ash.create!(
          Spotter.Transcripts.TeamMember,
          %{agent_name: "architect-updated", team_id: team.id, session_id: session.id},
          upsert?: true,
          upsert_identity: :unique_member_per_team
        )

      assert first.id == second.id
    end
  end

  describe "read" do
    test "can read team members back", %{team: team, session: session} do
      Ash.create!(Spotter.Transcripts.TeamMember, %{
        agent_name: "readable-member",
        team_id: team.id,
        session_id: session.id
      })

      members = Ash.read!(Spotter.Transcripts.TeamMember)

      assert members != []
      assert Enum.any?(members, fn m -> m.agent_name == "readable-member" end)
    end
  end

  describe "relationships" do
    test "can load team members through Team has_many", %{team: team, session: session} do
      Ash.create!(Spotter.Transcripts.TeamMember, %{
        agent_name: "linked-member",
        team_id: team.id,
        session_id: session.id
      })

      team = Ash.load!(team, :team_members)

      assert team.team_members != []
      assert Enum.any?(team.team_members, fn m -> m.agent_name == "linked-member" end)
    end
  end
end
