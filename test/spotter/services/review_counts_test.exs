defmodule Spotter.Services.ReviewCountsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.ReviewCounts
  alias Spotter.Transcripts.{Annotation, Project, Session}

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id
    })
  end

  defp create_annotation(session, state) do
    Ash.create!(Annotation, %{
      session_id: session.id,
      selected_text: "test text",
      comment: "test comment",
      state: state
    })
  end

  # -- list_project_open_counts/0 ---------------------------------------------

  describe "list_project_open_counts/0" do
    test "returns empty list when no projects exist" do
      assert ReviewCounts.list_project_open_counts() == []
    end

    test "returns projects with zero counts when no sessions exist" do
      create_project("alpha")

      result = ReviewCounts.list_project_open_counts()
      assert length(result) == 1
      assert hd(result).open_count == 0
    end

    test "returns projects with zero counts when sessions exist but no annotations" do
      project = create_project("alpha")
      create_session(project)

      result = ReviewCounts.list_project_open_counts()
      assert length(result) == 1
      assert hd(result).open_count == 0
    end

    test "counts only open annotations" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)
      create_annotation(session, :open)
      create_annotation(session, :closed)

      result = ReviewCounts.list_project_open_counts()
      assert length(result) == 1
      assert hd(result).open_count == 2
    end

    test "returns correct shape for each element" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      [entry] = ReviewCounts.list_project_open_counts()
      assert entry.project_id == project.id
      assert entry.project_name == "alpha"
      assert entry.open_count == 1
    end

    test "sorts projects by name ascending" do
      create_project("zeta")
      create_project("alpha")
      create_project("mid")

      names = ReviewCounts.list_project_open_counts() |> Enum.map(& &1.project_name)
      assert names == ["alpha", "mid", "zeta"]
    end

    test "counts across multiple projects" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")

      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_annotation(sess_a, :open)
      create_annotation(sess_b, :open)
      create_annotation(sess_b, :open)
      create_annotation(sess_b, :closed)

      result = ReviewCounts.list_project_open_counts()
      counts = Map.new(result, &{&1.project_name, &1.open_count})

      assert counts["alpha"] == 1
      assert counts["beta"] == 2
    end

    test "includes projects with zero open annotations alongside non-zero ones" do
      proj_a = create_project("alpha")
      create_project("beta")

      sess_a = create_session(proj_a)
      create_annotation(sess_a, :open)
      # proj_b has no sessions/annotations

      result = ReviewCounts.list_project_open_counts()
      counts = Map.new(result, &{&1.project_name, &1.open_count})

      assert counts["alpha"] == 1
      assert counts["beta"] == 0
    end
  end

  # -- total_open_count/0 ------------------------------------------------------

  describe "total_open_count/0" do
    test "returns 0 when no projects exist" do
      assert ReviewCounts.total_open_count() == 0
    end

    test "returns 0 when all annotations are closed" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :closed)

      assert ReviewCounts.total_open_count() == 0
    end

    test "returns total open count across all projects" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")

      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_annotation(sess_a, :open)
      create_annotation(sess_b, :open)
      create_annotation(sess_b, :open)
      create_annotation(sess_b, :closed)

      assert ReviewCounts.total_open_count() == 3
    end
  end
end
