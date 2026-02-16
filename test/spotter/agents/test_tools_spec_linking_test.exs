defmodule Spotter.Agents.TestToolsSpecLinkingTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Agents.TestTools
  alias Spotter.Repo
  alias Spotter.Transcripts.{Project, SpecTestLink}

  setup do
    Sandbox.checkout(Repo)
    project = Ash.create!(Project, %{name: "test-spec-link", pattern: "^test"})
    %{project: project}
  end

  describe "fetch_spec_requirements/2" do
    test "returns empty list when no spec run exists", %{project: project} do
      result = TestTools.fetch_spec_requirements(project.id, String.duplicate("a", 40))
      assert result == []
    end

    test "returns empty list when ProductSpec repo is down", %{project: project} do
      # ProductSpec.Repo may not be running in test — this exercises the rescue path
      result = TestTools.fetch_spec_requirements(project.id, String.duplicate("b", 40))
      assert result == []
    end
  end

  describe "upsert_links/3" do
    test "creates valid links", %{project: project} do
      links = [
        %{
          "requirement_spec_key" => "REQ-001",
          "test_key" => "ExUnit::test/foo_test.exs::FooTest::returns ok",
          "confidence" => 0.9
        },
        %{
          "requirement_spec_key" => "REQ-002",
          "test_key" => "ExUnit::test/bar_test.exs::BarTest::handles error"
        }
      ]

      result = TestTools.upsert_links(project.id, String.duplicate("a", 40), links)
      assert result.ok == 2
      assert result.skipped == 0

      stored = Ash.read!(SpecTestLink)
      assert length(stored) == 2
    end

    test "skips links with empty keys", %{project: project} do
      links = [
        %{"requirement_spec_key" => "", "test_key" => "some_test"},
        %{"requirement_spec_key" => "REQ-001", "test_key" => ""},
        %{"requirement_spec_key" => nil, "test_key" => "some_test"}
      ]

      result = TestTools.upsert_links(project.id, String.duplicate("c", 40), links)
      assert result.ok == 0
      assert result.skipped == 3
    end

    test "upserts duplicate links without error", %{project: project} do
      commit_hash = String.duplicate("d", 40)

      links = [
        %{"requirement_spec_key" => "REQ-001", "test_key" => "test_a"},
        %{"requirement_spec_key" => "REQ-001", "test_key" => "test_a", "confidence" => 0.5}
      ]

      result = TestTools.upsert_links(project.id, commit_hash, links)
      assert result.ok == 2
      assert result.skipped == 0

      stored = Ash.read!(SpecTestLink)
      assert length(stored) == 1
      assert hd(stored).confidence == 0.5
    end

    test "defaults confidence to 1.0", %{project: project} do
      links = [%{"requirement_spec_key" => "REQ-X", "test_key" => "test_y"}]

      TestTools.upsert_links(project.id, String.duplicate("e", 40), links)

      [link] = Ash.read!(SpecTestLink)
      assert link.confidence == 1.0
    end
  end
end
