defmodule Spotter.Transcripts.TeamTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Spotter.Repo)
    Sandbox.mode(Spotter.Repo, {:shared, self()})

    project = Ash.create!(Spotter.Transcripts.Project, %{name: "test-project", pattern: "^test"})
    %{project: project}
  end

  describe "create" do
    test "can create a Team with name and project_id", %{project: project} do
      team = Ash.create!(Spotter.Transcripts.Team, %{name: "my-team", project_id: project.id})

      assert team.name == "my-team"
      assert team.project_id == project.id
      assert team.id != nil
    end

    test "name is required", %{project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(Spotter.Transcripts.Team, %{project_id: project.id})
      end
    end

    test "project_id is required" do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(Spotter.Transcripts.Team, %{name: "orphan-team"})
      end
    end
  end

  describe "upsert" do
    test "same name+project_id returns the same record", %{project: project} do
      first =
        Ash.create!(Spotter.Transcripts.Team, %{name: "dup-team", project_id: project.id},
          upsert?: true,
          upsert_identity: :unique_team_per_project
        )

      second =
        Ash.create!(Spotter.Transcripts.Team, %{name: "dup-team", project_id: project.id},
          upsert?: true,
          upsert_identity: :unique_team_per_project
        )

      assert first.id == second.id
    end
  end

  describe "read" do
    test "can read teams back", %{project: project} do
      Ash.create!(Spotter.Transcripts.Team, %{name: "readable-team", project_id: project.id})

      teams = Ash.read!(Spotter.Transcripts.Team)

      assert teams != []
      assert Enum.any?(teams, fn t -> t.name == "readable-team" end)
    end
  end

  describe "relationships" do
    test "has_many team_members", %{project: project} do
      team = Ash.create!(Spotter.Transcripts.Team, %{name: "rel-team", project_id: project.id})

      team = Ash.load!(team, :team_members)

      assert team.team_members == []
    end
  end

  describe "Session team_name and agent_name" do
    test "can create a Session with team_name and agent_name", %{project: project} do
      session =
        Ash.create!(Spotter.Transcripts.Session, %{
          session_id: Ash.UUID.generate(),
          project_id: project.id,
          team_name: "my-team",
          agent_name: "backend-architect"
        })

      assert session.team_name == "my-team"
      assert session.agent_name == "backend-architect"
    end

    test "can create a Session without team_name and agent_name", %{project: project} do
      session =
        Ash.create!(Spotter.Transcripts.Session, %{
          session_id: Ash.UUID.generate(),
          project_id: project.id
        })

      assert session.team_name == nil
      assert session.agent_name == nil
    end

    test "can update a Session to set team_name and agent_name", %{project: project} do
      session =
        Ash.create!(Spotter.Transcripts.Session, %{
          session_id: Ash.UUID.generate(),
          project_id: project.id
        })

      updated = Ash.update!(session, %{team_name: "updated-team", agent_name: "qa-tester"})

      assert updated.team_name == "updated-team"
      assert updated.agent_name == "qa-tester"
    end
  end
end
