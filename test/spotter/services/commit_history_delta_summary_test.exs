defmodule Spotter.Services.CommitHistoryDeltaSummaryTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.ProductSpec.RollingSpecRun
  alias Spotter.Repo
  alias Spotter.Services.CommitHistoryDeltaSummary
  alias Spotter.Transcripts.{Commit, CommitTestRun, Project, Session, SessionCommitLink}

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
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

  defp create_commit(opts) do
    Ash.create!(Commit, %{
      commit_hash: opts[:hash] || Ash.UUID.generate(),
      git_branch: opts[:branch],
      subject: opts[:subject] || "test commit",
      committed_at: opts[:committed_at] || ~U[2026-01-01 12:00:00Z],
      parent_hashes: opts[:parent_hashes] || []
    })
  end

  defp create_link(session, commit) do
    Ash.create!(SessionCommitLink, %{
      session_id: session.id,
      commit_id: commit.id,
      link_type: :observed_in_session,
      confidence: 1.0
    })
  end

  defp create_spec_run(project, commit, opts \\ []) do
    Ash.create!(RollingSpecRun, %{
      project_id: project.id,
      commit_hash: commit.commit_hash,
      status: opts[:status] || :ok,
      dolt_commit_hash: opts[:dolt_commit_hash]
    })
  end

  defp create_test_run(project, commit, opts \\ []) do
    Ash.create!(CommitTestRun, %{
      project_id: project.id,
      commit_id: commit.id,
      status: opts[:status] || :completed
    })
  end

  defp make_row(commit) do
    %{commit: commit, sessions: []}
  end

  describe "summaries_for_commits/3" do
    test "returns empty map for empty commit list" do
      assert %{} == CommitHistoryDeltaSummary.summaries_for_commits("fake-id", [])
    end

    test "returns nil sides when no runs exist" do
      project = create_project("delta-no-runs")
      session = create_session(project)
      commit = create_commit(hash: "dnr-001")
      create_link(session, commit)

      rows = [make_row(commit)]
      result = CommitHistoryDeltaSummary.summaries_for_commits(project.id, rows)

      assert Map.has_key?(result, commit.id)
      assert result[commit.id].product == nil
      assert result[commit.id].tests == nil
    end

    test "returns nil for product when spec run is not :ok status" do
      project = create_project("delta-pending")
      session = create_session(project)
      commit = create_commit(hash: "dp-001")
      create_link(session, commit)
      create_spec_run(project, commit, status: :pending)

      rows = [make_row(commit)]
      result = CommitHistoryDeltaSummary.summaries_for_commits(project.id, rows)

      assert result[commit.id].product == nil
    end

    test "returns nil for tests when test run is not :completed status" do
      project = create_project("delta-running")
      session = create_session(project)
      commit = create_commit(hash: "dr-001")
      create_link(session, commit)
      create_test_run(project, commit, status: :running)

      rows = [make_row(commit)]
      result = CommitHistoryDeltaSummary.summaries_for_commits(project.id, rows)

      assert result[commit.id].tests == nil
    end

    test "handles multiple commits with mixed run states" do
      project = create_project("delta-mixed")
      session = create_session(project)

      c1 = create_commit(hash: "dm-001", committed_at: ~U[2026-01-01 12:00:00Z])
      c2 = create_commit(hash: "dm-002", committed_at: ~U[2026-01-01 13:00:00Z])
      create_link(session, c1)
      create_link(session, c2)

      # c1 has ok spec run, c2 has no runs
      create_spec_run(project, c1, status: :ok)

      rows = [make_row(c1), make_row(c2)]
      result = CommitHistoryDeltaSummary.summaries_for_commits(project.id, rows)

      # Both commits should be in results
      assert Map.has_key?(result, c1.id)
      assert Map.has_key?(result, c2.id)

      # c2 should have nil sides
      assert result[c2.id].product == nil
      assert result[c2.id].tests == nil
    end

    test "returns summary map for every commit in input" do
      project = create_project("delta-all")
      session = create_session(project)

      commits =
        for i <- 1..3 do
          c =
            create_commit(
              hash: "da-#{i}",
              committed_at: DateTime.add(~U[2026-01-01 00:00:00Z], i, :hour)
            )

          create_link(session, c)
          c
        end

      rows = Enum.map(commits, &make_row/1)
      result = CommitHistoryDeltaSummary.summaries_for_commits(project.id, rows)

      assert map_size(result) == 3

      for commit <- commits do
        assert Map.has_key?(result, commit.id)
        summary = result[commit.id]
        assert is_map(summary)
        assert Map.has_key?(summary, :product)
        assert Map.has_key?(summary, :tests)
      end
    end
  end
end
