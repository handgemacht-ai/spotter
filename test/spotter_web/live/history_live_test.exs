defmodule SpotterWeb.HistoryLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, Project, Session, SessionCommitLink}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project, opts \\ []) do
    Ash.create!(Session, %{
      session_id: opts[:session_id] || Ash.UUID.generate(),
      slug: opts[:slug],
      transcript_dir: opts[:dir] || "test-dir",
      project_id: project.id,
      started_at: opts[:started_at]
    })
  end

  defp create_commit(opts) do
    Ash.create!(Commit, %{
      commit_hash: opts[:hash] || Ash.UUID.generate(),
      git_branch: opts[:branch],
      subject: opts[:subject],
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

  describe "default branch selection" do
    test "preselects main when both main and master exist" do
      project = create_project("defbranch")
      session = create_session(project)

      c1 = create_commit(branch: "main", hash: "db1", committed_at: ~U[2026-01-01 12:00:00Z])
      c2 = create_commit(branch: "master", hash: "db2", committed_at: ~U[2026-01-01 11:00:00Z])
      create_link(session, c1)
      create_link(session, c2)

      {:ok, _view, html} = live(build_conn(), "/history")

      # main commit should be visible (default branch = main)
      assert html =~ String.slice("db1", 0, 8)
      # master commit should not be visible when main is preselected
      refute html =~ String.slice("db2", 0, 8)
    end
  end

  describe "branch filter behavior" do
    test "selecting a branch shows only matching commits" do
      project = create_project("branchfilter")
      session = create_session(project)

      c1 =
        create_commit(
          branch: "main",
          hash: "bf-main-hash",
          committed_at: ~U[2026-01-01 12:00:00Z],
          subject: "commit on main"
        )

      c2 =
        create_commit(
          branch: "develop",
          hash: "bf-dev-hash",
          committed_at: ~U[2026-01-01 13:00:00Z],
          subject: "commit on develop"
        )

      create_link(session, c1)
      create_link(session, c2)

      {:ok, view, _html} = live(build_conn(), "/history")

      # Switch to develop branch
      html = render_click(view, "filter_branch", %{"branch" => "develop"})

      assert html =~ "bf-dev-h"
      refute html =~ "bf-main-"
    end
  end

  describe "project filter behavior" do
    test "filtering by project shows only sessions from that project" do
      proj_a = create_project("proj-alpha")
      proj_b = create_project("proj-beta")
      sess_a = create_session(proj_a, slug: "alpha-session")
      sess_b = create_session(proj_b, slug: "beta-session")

      commit =
        create_commit(
          branch: nil,
          hash: "pf-commit",
          committed_at: ~U[2026-01-01 12:00:00Z],
          subject: "shared commit"
        )

      create_link(sess_a, commit)
      create_link(sess_b, commit)

      # No branch filter (show all)
      {:ok, view, _html} = live(build_conn(), "/history?branch=")

      # Both sessions visible initially
      html = render(view)
      assert html =~ "alpha-session"
      assert html =~ "beta-session"

      # Filter to proj_a
      html = render_click(view, "filter_project", %{"project-id" => proj_a.id})

      assert html =~ "alpha-session"
      refute html =~ "beta-session"
    end
  end

  describe "multiple sessions per commit" do
    test "renders both sessions under one commit" do
      project = create_project("multisess")
      sess1 = create_session(project, slug: "session-one")
      sess2 = create_session(project, slug: "session-two")

      commit =
        create_commit(
          branch: nil,
          hash: "ms-commit",
          committed_at: ~U[2026-01-01 12:00:00Z],
          subject: "multi-session commit"
        )

      create_link(sess1, commit)
      create_link(sess2, commit)

      {:ok, _view, html} = live(build_conn(), "/history?branch=")

      assert html =~ "session-one"
      assert html =~ "session-two"
      # Only one commit row
      assert count_occurrences(html, "ms-commi") == 1
    end
  end

  describe "multiple link types" do
    test "renders badges for multiple link types on one session" do
      project = create_project("multilink")
      session = create_session(project, slug: "linked-sess")

      commit =
        create_commit(
          branch: nil,
          hash: "ml-commit",
          committed_at: ~U[2026-01-01 12:00:00Z],
          subject: "multi-link commit"
        )

      create_link(session, commit, type: :observed_in_session, confidence: 1.0)
      create_link(session, commit, type: :file_overlap, confidence: 0.6)

      {:ok, _view, html} = live(build_conn(), "/history?branch=")

      # One session entry, two badges (max_confidence is 1.0 for both)
      assert count_occurrences(html, "linked-sess") == 1
      assert html =~ "Verified"
      assert html =~ "Inferred 100%"
    end
  end

  describe "pagination" do
    test "first page shows up to 50 commits and load more appends" do
      project = create_project("paginate")
      session = create_session(project)

      for i <- 1..53 do
        c =
          create_commit(
            branch: nil,
            hash: "pg-#{String.pad_leading("#{i}", 3, "0")}",
            committed_at: DateTime.add(~U[2026-01-01 00:00:00Z], i, :hour),
            subject: "Commit #{i}"
          )

        create_link(session, c)
      end

      {:ok, view, html} = live(build_conn(), "/history?branch=")

      # First page has 50 commits
      assert count_occurrences(html, "pg-") == 50
      assert html =~ "Load more"

      # Load more appends remaining
      html = render_click(view, "load_more")
      assert count_occurrences(html, "pg-") == 53
      refute html =~ "Load more"
    end
  end

  describe "empty state" do
    test "renders exact empty state copy when no matches" do
      # Create a project with data but filter to a project with none
      proj_a = create_project("empty-proj-a")
      proj_b = create_project("empty-proj-b")
      sess_a = create_session(proj_a)

      commit =
        create_commit(
          branch: nil,
          hash: "es-commit",
          committed_at: ~U[2026-01-01 12:00:00Z]
        )

      create_link(sess_a, commit)

      {:ok, view, _html} = live(build_conn(), "/history?branch=")

      # Filter to project with no data
      html = render_click(view, "filter_project", %{"project-id" => proj_b.id})

      assert html =~ "No commits found for the selected filters."
    end
  end

  describe "edge cases" do
    test "nil subject renders fallback" do
      project = create_project("nilsubj")
      session = create_session(project)

      commit =
        create_commit(
          branch: nil,
          hash: "ns-commit",
          committed_at: ~U[2026-01-01 12:00:00Z],
          subject: nil
        )

      create_link(session, commit)

      {:ok, _view, html} = live(build_conn(), "/history?branch=")

      assert html =~ "(no subject)"
    end

    test "nil committed_at still renders commit using inserted_at" do
      project = create_project("nildate")
      session = create_session(project)

      commit =
        create_commit(
          branch: nil,
          hash: "nd-commit",
          committed_at: nil,
          subject: "no date commit"
        )

      create_link(session, commit)

      {:ok, _view, html} = live(build_conn(), "/history?branch=")

      assert html =~ "nd-commi"
      assert html =~ "no date commit"
    end

    test "invalid query params do not crash" do
      {:ok, _view, html} =
        live(build_conn(), "/history?project_id=bogus&branch=nonexistent&after=invalid")

      # Page renders without crashing
      assert html =~ "Commit History"
    end
  end

  defp count_occurrences(string, substring) do
    string
    |> String.split(substring)
    |> length()
    |> Kernel.-(1)
  end
end
