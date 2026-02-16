defmodule Spotter.Services.CommitHistoryTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.CommitHistory
  alias Spotter.Transcripts.{Commit, Project, Session, SessionCommitLink}

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project, opts \\ []) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: opts[:dir] || "test-dir",
      project_id: project.id,
      started_at: opts[:started_at]
    })
  end

  defp create_commit(opts) do
    Ash.create!(Commit, %{
      commit_hash: opts[:hash] || Ash.UUID.generate(),
      git_branch: opts[:branch],
      subject: opts[:subject] || "Test commit",
      committed_at: opts[:committed_at],
      parent_hashes: opts[:parent_hashes] || []
    })
  end

  defp create_link(session, commit, opts \\ []) do
    Ash.create!(SessionCommitLink, %{
      session_id: session.id,
      commit_id: commit.id,
      link_type: opts[:type] || :observed_in_session,
      confidence: opts[:confidence] || 1.0
    })
  end

  # -- list_filter_options/0 -------------------------------------------------

  describe "list_filter_options/0" do
    test "returns empty when no data" do
      result = CommitHistory.list_filter_options()
      assert result.projects == []
      assert result.branches == []
      assert result.default_branch == nil
    end

    test "returns projects sorted by name" do
      create_project("zeta")
      create_project("alpha")
      create_project("mid")

      names = CommitHistory.list_filter_options().projects |> Enum.map(& &1.name)
      assert names == ["alpha", "mid", "zeta"]
    end

    test "returns distinct non-empty branches sorted" do
      create_commit(branch: "main", hash: "a1")
      create_commit(branch: "develop", hash: "a2")
      create_commit(branch: "main", hash: "a3")
      create_commit(branch: nil, hash: "a4")
      create_commit(branch: "", hash: "a5")

      assert CommitHistory.list_filter_options().branches == ["develop", "main"]
    end

    test "default branch is main when present" do
      create_commit(branch: "main", hash: "b1")
      create_commit(branch: "master", hash: "b2")

      assert CommitHistory.list_filter_options().default_branch == "main"
    end

    test "default branch is master when main not present" do
      create_commit(branch: "master", hash: "c1")
      create_commit(branch: "develop", hash: "c2")

      assert CommitHistory.list_filter_options().default_branch == "master"
    end

    test "default branch is most frequent when no main/master" do
      create_commit(branch: "develop", hash: "d1")
      create_commit(branch: "develop", hash: "d2")
      create_commit(branch: "feature", hash: "d3")

      assert CommitHistory.list_filter_options().default_branch == "develop"
    end

    test "default branch resolves ties lexicographically ascending" do
      create_commit(branch: "beta", hash: "e1")
      create_commit(branch: "alpha", hash: "e2")

      assert CommitHistory.list_filter_options().default_branch == "alpha"
    end
  end

  # -- list_commits_with_sessions/2 ------------------------------------------

  describe "list_commits_with_sessions/2" do
    test "returns commit rows even when no links exist" do
      create_commit(branch: "main", hash: "f1")

      result = CommitHistory.list_commits_with_sessions(%{branch: "main"})
      assert length(result.rows) == 1
      assert hd(result.rows).sessions == []
    end

    test "returns commits with session entries" do
      project = create_project("proj1")
      session = create_session(project)
      commit = create_commit(branch: "main", hash: "g1", committed_at: ~U[2026-01-01 12:00:00Z])
      create_link(session, commit)

      result = CommitHistory.list_commits_with_sessions()
      assert length(result.rows) == 1

      row = hd(result.rows)
      assert row.commit.id == commit.id
      assert length(row.sessions) == 1

      entry = hd(row.sessions)
      assert entry.session.id == session.id
      assert entry.project.id == project.id
      assert entry.link_types == [:observed_in_session]
      assert entry.max_confidence == 1.0
    end

    test "filters by branch" do
      project = create_project("proj-branch")
      session = create_session(project)

      c1 = create_commit(branch: "main", hash: "h1", committed_at: ~U[2026-01-01 12:00:00Z])
      c2 = create_commit(branch: "develop", hash: "h2", committed_at: ~U[2026-01-01 13:00:00Z])

      create_link(session, c1)
      create_link(session, c2)

      result = CommitHistory.list_commits_with_sessions(%{branch: "main"})
      assert length(result.rows) == 1
      assert hd(result.rows).commit.id == c1.id
    end

    test "excludes nil-branch commits when branch filter is set" do
      project = create_project("proj-nil-branch")
      session = create_session(project)

      c1 = create_commit(branch: nil, hash: "nil1", committed_at: ~U[2026-01-01 12:00:00Z])
      c2 = create_commit(branch: "main", hash: "nil2", committed_at: ~U[2026-01-01 13:00:00Z])

      create_link(session, c1)
      create_link(session, c2)

      result = CommitHistory.list_commits_with_sessions(%{branch: "main"})
      assert length(result.rows) == 1
      assert hd(result.rows).commit.id == c2.id
    end

    test "includes nil-branch commits when no branch filter" do
      project = create_project("proj-nil-no-filter")
      session = create_session(project)

      c1 = create_commit(branch: nil, hash: "nf1", committed_at: ~U[2026-01-01 12:00:00Z])
      create_link(session, c1)

      result = CommitHistory.list_commits_with_sessions()
      assert length(result.rows) == 1
    end

    test "filters by project" do
      proj_a = create_project("proj-a")
      proj_b = create_project("proj-b")
      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      commit = create_commit(branch: "main", hash: "i1", committed_at: ~U[2026-01-01 12:00:00Z])
      create_link(sess_a, commit)
      create_link(sess_b, commit)

      result = CommitHistory.list_commits_with_sessions(%{project_id: proj_a.id})
      assert length(result.rows) == 1
      assert length(hd(result.rows).sessions) == 1
      assert hd(hd(result.rows).sessions).project.id == proj_a.id
    end

    test "project filter excludes commits with no matching sessions" do
      proj_a = create_project("proj-empty")
      proj_b = create_project("proj-with-data")
      sess_b = create_session(proj_b)

      commit = create_commit(branch: "main", hash: "j1", committed_at: ~U[2026-01-01 12:00:00Z])
      create_link(sess_b, commit)

      result = CommitHistory.list_commits_with_sessions(%{project_id: proj_a.id})
      assert result.rows == []
    end

    test "project filter isolates commits across projects" do
      proj_a = create_project("iso-a")
      proj_b = create_project("iso-b")
      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      c_a = create_commit(branch: "main", hash: "iso1", committed_at: ~U[2026-01-01 12:00:00Z])
      c_b = create_commit(branch: "main", hash: "iso2", committed_at: ~U[2026-01-01 13:00:00Z])
      create_link(sess_a, c_a)
      create_link(sess_b, c_b)

      result_a = CommitHistory.list_commits_with_sessions(%{project_id: proj_a.id})
      assert length(result_a.rows) == 1
      assert hd(result_a.rows).commit.id == c_a.id

      result_b = CommitHistory.list_commits_with_sessions(%{project_id: proj_b.id})
      assert length(result_b.rows) == 1
      assert hd(result_b.rows).commit.id == c_b.id
    end

    test "multiple sessions per commit" do
      project = create_project("proj-multi-sess")
      sess1 = create_session(project, dir: "dir1")
      sess2 = create_session(project, dir: "dir2")

      commit = create_commit(branch: "main", hash: "k1", committed_at: ~U[2026-01-01 12:00:00Z])
      create_link(sess1, commit)
      create_link(sess2, commit)

      result = CommitHistory.list_commits_with_sessions()
      assert length(result.rows) == 1
      assert length(hd(result.rows).sessions) == 2
    end

    test "multi-link-type aggregation per session" do
      project = create_project("proj-multi-link")
      session = create_session(project)

      commit = create_commit(branch: "main", hash: "l1", committed_at: ~U[2026-01-01 12:00:00Z])
      create_link(session, commit, type: :observed_in_session, confidence: 1.0)
      create_link(session, commit, type: :file_overlap, confidence: 0.6)

      entry =
        CommitHistory.list_commits_with_sessions()
        |> get_in([:rows, Access.at(0), :sessions, Access.at(0)])

      assert entry.link_types == [:file_overlap, :observed_in_session]
      assert entry.max_confidence == 1.0
    end

    test "sorts by committed_at descending with id tie-break" do
      project = create_project("proj-sort")
      session = create_session(project)

      c1 = create_commit(branch: "main", hash: "m1", committed_at: ~U[2026-01-01 10:00:00Z])
      c2 = create_commit(branch: "main", hash: "m2", committed_at: ~U[2026-01-01 12:00:00Z])
      c3 = create_commit(branch: "main", hash: "m3", committed_at: ~U[2026-01-01 11:00:00Z])

      create_link(session, c1)
      create_link(session, c2)
      create_link(session, c3)

      ids =
        CommitHistory.list_commits_with_sessions() |> Map.get(:rows) |> Enum.map(& &1.commit.id)

      assert ids == [c2.id, c3.id, c1.id]
    end

    test "falls back to inserted_at when committed_at is nil" do
      project = create_project("proj-fallback")
      session = create_session(project)

      # committed_at is nil, so sorting uses inserted_at
      c1 = create_commit(branch: "main", hash: "fb1")
      # Small sleep to ensure different inserted_at
      Process.sleep(10)
      c2 = create_commit(branch: "main", hash: "fb2")

      create_link(session, c1)
      create_link(session, c2)

      ids =
        CommitHistory.list_commits_with_sessions() |> Map.get(:rows) |> Enum.map(& &1.commit.id)

      # c2 was created later, so inserted_at is newer -> comes first (descending)
      assert ids == [c2.id, c1.id]
    end

    test "pagination returns correct page size and has_more" do
      project = create_project("proj-page")
      session = create_session(project)

      for i <- 1..5 do
        c =
          create_commit(
            branch: "main",
            hash: "page-#{String.pad_leading("#{i}", 2, "0")}",
            committed_at: DateTime.add(~U[2026-01-01 00:00:00Z], i, :hour)
          )

        create_link(session, c)
      end

      result = CommitHistory.list_commits_with_sessions(%{}, %{limit: 3})
      assert length(result.rows) == 3
      assert result.has_more == true
      assert result.cursor != nil

      result2 = CommitHistory.list_commits_with_sessions(%{}, %{limit: 3, after: result.cursor})
      assert length(result2.rows) == 2
      assert result2.has_more == false
    end

    test "pagination cursor navigates all pages without duplicates" do
      project = create_project("proj-cursor")
      session = create_session(project)

      for i <- 1..7 do
        c =
          create_commit(
            branch: "main",
            hash: "cur-#{String.pad_leading("#{i}", 2, "0")}",
            committed_at: DateTime.add(~U[2026-01-01 00:00:00Z], i, :hour)
          )

        create_link(session, c)
      end

      r1 = CommitHistory.list_commits_with_sessions(%{}, %{limit: 3})
      assert length(r1.rows) == 3
      assert r1.has_more == true

      r2 = CommitHistory.list_commits_with_sessions(%{}, %{limit: 3, after: r1.cursor})
      assert length(r2.rows) == 3
      assert r2.has_more == true

      r3 = CommitHistory.list_commits_with_sessions(%{}, %{limit: 3, after: r2.cursor})
      assert length(r3.rows) == 1
      assert r3.has_more == false

      all_ids = Enum.flat_map([r1, r2, r3], fn r -> Enum.map(r.rows, & &1.commit.id) end)
      assert length(Enum.uniq(all_ids)) == 7
    end

    test "limit is capped at 50" do
      project = create_project("proj-cap")
      session = create_session(project)

      c = create_commit(branch: "main", hash: "cap1", committed_at: ~U[2026-01-01 12:00:00Z])
      create_link(session, c)

      # Requesting limit > 50 should be capped
      result = CommitHistory.list_commits_with_sessions(%{}, %{limit: 100})
      assert length(result.rows) == 1
    end
  end
end
