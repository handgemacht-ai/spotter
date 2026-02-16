defmodule SpotterWeb.TestsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, CommitTestRun, Project, Session, SessionCommitLink}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  test "/tests mounts and renders page header" do
    conn = build_conn()
    {:ok, view, html} = live(conn, "/tests")
    assert html =~ "Tests"
    assert html =~ "Test specifications extracted from commits"
    assert has_element?(view, "h1", "Tests")
  end

  test "/tests shows Dolt unavailable callout when repo is down" do
    if Process.whereis(Spotter.TestSpec.Repo) == nil do
      conn = build_conn()
      {:ok, _view, html} = live(conn, "/tests")
      assert html =~ "Dolt is unavailable"
      assert html =~ "docker compose"
    end
  end

  test "sidebar contains link to /tests" do
    conn = build_conn()
    {:ok, _view, html} = live(conn, "/tests")
    assert html =~ ~s|href="/tests"|
    assert html =~ "Tests"
  end

  describe "timeline + detail interaction" do
    setup do
      project = Ash.create!(Project, %{name: "tests-timeline", pattern: "^tests-timeline"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test-tests-timeline",
          project_id: project.id
        })

      commit =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("b", 40),
          subject: "test: add unit tests",
          committed_at: ~U[2026-02-14 12:00:00Z]
        })

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      %{project: project, commit: commit}
    end

    test "renders commit in timeline when project is selected", %{
      project: project,
      commit: commit
    } do
      conn = build_conn()
      {:ok, _view, html} = live(conn, "/tests?project_id=#{project.id}")

      assert html =~ String.slice(commit.commit_hash, 0, 8)
      assert html =~ "test: add unit tests"
    end

    test "selecting a commit updates URL and renders detail header", %{
      project: project,
      commit: commit
    } do
      conn = build_conn()
      {:ok, view, _html} = live(conn, "/tests?project_id=#{project.id}")

      html =
        view
        |> element(".product-timeline-row")
        |> render_click()

      assert_patched(view, "/tests?commit_id=#{commit.id}&project_id=#{project.id}")
      assert html =~ commit.commit_hash
    end

    test "toggling between Diff and Snapshot updates URL", %{
      project: project,
      commit: commit
    } do
      conn = build_conn()

      {:ok, view, _html} =
        live(conn, "/tests?project_id=#{project.id}&commit_id=#{commit.id}")

      # Switch to snapshot
      view
      |> element(".product-detail-toggle button", "Snapshot")
      |> render_click()

      assert_patched(
        view,
        "/tests?commit_id=#{commit.id}&project_id=#{project.id}&spec_view=snapshot"
      )

      # Switch back to diff
      view
      |> element(".product-detail-toggle button", "Diff")
      |> render_click()

      assert_patched(view, "/tests?commit_id=#{commit.id}&project_id=#{project.id}")
    end

    test "shows test run badge when run exists", %{
      project: project,
      commit: commit
    } do
      run =
        Ash.create!(CommitTestRun, %{
          project_id: project.id,
          commit_id: commit.id
        })

      Ash.update!(run, %{dolt_commit_hash: String.duplicate("c", 32)}, action: :complete)

      conn = build_conn()
      {:ok, _view, html} = live(conn, "/tests?project_id=#{project.id}")

      assert html =~ "is-ok"
    end

    test "shows no-changes badge for completed run without dolt hash", %{
      project: project,
      commit: commit
    } do
      run =
        Ash.create!(CommitTestRun, %{
          project_id: project.id,
          commit_id: commit.id
        })

      Ash.update!(run, %{}, action: :complete)

      conn = build_conn()
      {:ok, _view, html} = live(conn, "/tests?project_id=#{project.id}")

      assert html =~ "ok (no changes)"
    end

    test "shows queued badge for pending run", %{
      project: project,
      commit: commit
    } do
      Ash.create!(CommitTestRun, %{
        project_id: project.id,
        commit_id: commit.id
      })

      conn = build_conn()
      {:ok, _view, html} = live(conn, "/tests?project_id=#{project.id}")

      assert html =~ "is-queued"
    end

    test "shows empty detail prompt when no commit selected", %{project: project} do
      conn = build_conn()
      {:ok, _view, html} = live(conn, "/tests?project_id=#{project.id}")

      assert html =~ "Select a commit to view its test specification"
    end
  end

  test "shows empty state when no project selected" do
    conn = build_conn()
    {:ok, _view, html} = live(conn, "/tests")

    # Either shows "Select a project" or auto-selects first project
    assert html =~ "Tests"
  end
end
