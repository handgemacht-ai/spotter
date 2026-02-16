defmodule Spotter.Services.SpecTestLinksTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.SpecTestLinks
  alias Spotter.Transcripts.{Project, SpecTestLink}

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-links-svc", pattern: "^test"})
    commit_hash = String.duplicate("a", 40)

    Ash.create!(SpecTestLink, %{
      project_id: project.id,
      commit_hash: commit_hash,
      requirement_spec_key: "REQ-001",
      test_key: "test_a"
    })

    Ash.create!(SpecTestLink, %{
      project_id: project.id,
      commit_hash: commit_hash,
      requirement_spec_key: "REQ-001",
      test_key: "test_b"
    })

    Ash.create!(SpecTestLink, %{
      project_id: project.id,
      commit_hash: commit_hash,
      requirement_spec_key: "REQ-002",
      test_key: "test_a"
    })

    %{project: project, commit_hash: commit_hash}
  end

  describe "linked_test_counts/2" do
    test "returns counts grouped by requirement_spec_key", %{
      project: project,
      commit_hash: commit_hash
    } do
      counts = SpecTestLinks.linked_test_counts(project.id, commit_hash)
      assert counts["REQ-001"] == 2
      assert counts["REQ-002"] == 1
    end

    test "returns empty map for unknown project" do
      counts = SpecTestLinks.linked_test_counts(Ash.UUID.generate(), String.duplicate("z", 40))
      assert counts == %{}
    end
  end

  describe "linked_requirement_counts/2" do
    test "returns counts grouped by test_key", %{
      project: project,
      commit_hash: commit_hash
    } do
      counts = SpecTestLinks.linked_requirement_counts(project.id, commit_hash)
      assert counts["test_a"] == 2
      assert counts["test_b"] == 1
    end

    test "returns empty map for unknown commit" do
      counts =
        SpecTestLinks.linked_requirement_counts(Ash.UUID.generate(), String.duplicate("z", 40))

      assert counts == %{}
    end
  end
end
