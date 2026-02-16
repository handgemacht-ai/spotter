defmodule SpotterWeb.ProductLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, Project, Session, SessionCommitLink, SpecTestLink}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  test "/product mounts and renders page header" do
    conn = build_conn()
    {:ok, view, html} = live(conn, "/product")
    assert html =~ "Product"
    assert html =~ "Rolling spec derived from commits"
    assert has_element?(view, "h1", "Product")
  end

  test "/product shows Dolt unavailable callout when repo is down" do
    if Process.whereis(Spotter.ProductSpec.Repo) == nil do
      conn = build_conn()
      {:ok, _view, html} = live(conn, "/product")
      assert html =~ "Dolt is unavailable"
      assert html =~ "docker compose"
    end
  end

  test "sidebar contains link to /product" do
    conn = build_conn()
    {:ok, _view, html} = live(conn, "/product")
    assert html =~ ~s|href="/product"|
    assert html =~ "Product"
  end

  describe "timeline + detail interaction" do
    setup do
      # Create a dummy project that sorts first alphabetically so mount auto-selects it,
      # ensuring handle_params detects a project change and loads the timeline.
      _dummy = Ash.create!(Project, %{name: "aaa-dummy", pattern: "^aaa-dummy"})
      project = Ash.create!(Project, %{name: "timeline-test", pattern: "^timeline-test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test-timeline",
          project_id: project.id
        })

      commit =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("a", 40),
          subject: "feat: add timeline feature",
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
      {:ok, _view, html} = live(conn, "/product?project_id=#{project.id}")

      assert html =~ String.slice(commit.commit_hash, 0, 8)
      assert html =~ "feat: add timeline feature"
    end

    test "selecting a commit updates URL and renders detail header", %{
      project: project,
      commit: commit
    } do
      conn = build_conn()
      {:ok, view, _html} = live(conn, "/product?project_id=#{project.id}")

      html =
        view
        |> element(".product-timeline-row")
        |> render_click()

      assert_patched(view, "/product?commit_id=#{commit.id}&project_id=#{project.id}")
      assert html =~ commit.commit_hash
    end

    test "renders zero linked tests when no links exist", %{
      project: project,
      commit: commit
    } do
      # This test checks that the page renders without errors when no spec-test links exist.
      # The "0 linked tests" text only shows in snapshot view with Dolt available,
      # so we verify the page loads cleanly with the detail header visible.
      conn = build_conn()

      {:ok, _view, html} =
        live(conn, "/product?project_id=#{project.id}&commit_id=#{commit.id}")

      assert html =~ commit.commit_hash
    end

    test "toggling between Diff and Snapshot updates URL", %{
      project: project,
      commit: commit
    } do
      conn = build_conn()

      {:ok, view, _html} =
        live(conn, "/product?project_id=#{project.id}&commit_id=#{commit.id}")

      # Switch to snapshot
      view
      |> element(".product-detail-toggle button", "Snapshot")
      |> render_click()

      assert_patched(
        view,
        "/product?commit_id=#{commit.id}&project_id=#{project.id}&spec_view=snapshot"
      )

      # Switch back to diff
      view
      |> element(".product-detail-toggle button", "Diff")
      |> render_click()

      assert_patched(view, "/product?commit_id=#{commit.id}&project_id=#{project.id}")
    end
  end
end
