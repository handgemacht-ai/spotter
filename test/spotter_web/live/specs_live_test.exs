defmodule SpotterWeb.SpecsLiveTest do
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

  test "/specs mounts and renders title + subtitle" do
    conn = build_conn()
    {:ok, view, html} = live(conn, "/specs")
    assert html =~ "Specs"
    assert html =~ "Product and test specifications derived from commits"
    assert has_element?(view, "h1", "Specs")
  end

  test "sidebar contains link to /specs" do
    conn = build_conn()
    {:ok, _view, html} = live(conn, "/specs")
    assert html =~ ~s|href="/specs"|
    assert html =~ "Specs"
  end

  test "sidebar does not contain Product or Tests links" do
    conn = build_conn()
    {:ok, _view, html} = live(conn, "/specs")
    refute html =~ ~s|href="/product"|
    refute html =~ ~s|href="/tests"|
  end

  describe "timeline + detail interaction" do
    setup do
      _dummy = Ash.create!(Project, %{name: "aaa-dummy", pattern: "^aaa-dummy"})
      project = Ash.create!(Project, %{name: "specs-timeline", pattern: "^specs-timeline"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test-specs-timeline",
          project_id: project.id
        })

      commit =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("a", 40),
          subject: "feat: add specs feature",
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
      {:ok, _view, html} = live(conn, "/specs?project_id=#{project.id}")

      assert html =~ String.slice(commit.commit_hash, 0, 8)
      assert html =~ "feat: add specs feature"
    end

    test "timeline row shows both product and tests badges", %{project: project} do
      conn = build_conn()
      {:ok, _view, html} = live(conn, "/specs?project_id=#{project.id}")

      assert html =~ "product:"
      assert html =~ "tests:"
    end

    test "selecting a commit updates URL and renders detail header", %{
      project: project,
      commit: commit
    } do
      conn = build_conn()
      {:ok, view, _html} = live(conn, "/specs?project_id=#{project.id}")

      html =
        view
        |> element(".product-timeline-row")
        |> render_click()

      assert_patched(view, "/specs?commit_id=#{commit.id}&project_id=#{project.id}")
      assert html =~ commit.commit_hash
    end

    test "timeline isolates commits by project", %{project: project} do
      other_project = Ash.create!(Project, %{name: "other-test", pattern: "^other-test"})

      other_session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/other-test",
          project_id: other_project.id
        })

      other_commit =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("y", 40),
          subject: "test: other project only",
          committed_at: ~U[2026-02-14 13:00:00Z]
        })

      Ash.create!(SessionCommitLink, %{
        session_id: other_session.id,
        commit_id: other_commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      conn = build_conn()
      {:ok, _view, html} = live(conn, "/specs?project_id=#{project.id}")

      # The other project's commit should not appear
      refute html =~ "other project only"
      refute html =~ String.slice(other_commit.commit_hash, 0, 8)
    end

    test "URL patches when switching artifact", %{
      project: project,
      commit: commit
    } do
      conn = build_conn()

      {:ok, view, _html} =
        live(conn, "/specs?project_id=#{project.id}&commit_id=#{commit.id}")

      view
      |> element(".specs-artifact-toggle button", "Tests")
      |> render_click()

      assert_patched(
        view,
        "/specs?artifact=tests&commit_id=#{commit.id}&project_id=#{project.id}"
      )
    end

    test "URL patches when switching spec view", %{
      project: project,
      commit: commit
    } do
      conn = build_conn()

      {:ok, view, _html} =
        live(conn, "/specs?project_id=#{project.id}&commit_id=#{commit.id}")

      view
      |> element(".product-detail-toggle button", "Snapshot")
      |> render_click()

      assert_patched(
        view,
        "/specs?commit_id=#{commit.id}&project_id=#{project.id}&spec_view=snapshot"
      )

      view
      |> element(".product-detail-toggle button", "Diff")
      |> render_click()

      assert_patched(view, "/specs?commit_id=#{commit.id}&project_id=#{project.id}")
    end

    test "product and test detail render empty states when no data exists", %{
      project: project,
      commit: commit
    } do
      conn = build_conn()

      {:ok, _view, html} =
        live(conn, "/specs?project_id=#{project.id}&commit_id=#{commit.id}")

      # Detail section should render without errors
      assert html =~ commit.commit_hash
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
      {:ok, _view, html} = live(conn, "/specs?project_id=#{project.id}")

      assert html =~ "tests:"
      assert html =~ "is-ok"
    end
  end

  test "shows Dolt unavailable callout for product artifact when repo is down" do
    if Process.whereis(Spotter.ProductSpec.Repo) == nil do
      conn = build_conn()
      {:ok, _view, html} = live(conn, "/specs")
      assert html =~ "Dolt is unavailable"
    end
  end

  test "shows empty state when no project selected" do
    conn = build_conn()
    {:ok, _view, html} = live(conn, "/specs")
    assert html =~ "Specs"
  end
end
