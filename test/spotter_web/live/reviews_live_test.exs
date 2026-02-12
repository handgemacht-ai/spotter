defmodule SpotterWeb.ReviewsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Annotation, Project, Session}

  @endpoint SpotterWeb.Endpoint

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

  defp create_annotation(session, state) do
    Ash.create!(Annotation, %{
      session_id: session.id,
      selected_text: "text-#{System.unique_integer([:positive])}",
      comment: "comment",
      state: state
    })
  end

  describe "page structure" do
    test "renders heading and filter label" do
      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "<h1>Reviews</h1>"
      assert html =~ "Project"
    end

    test "renders All chip with total count" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)
      create_annotation(session, :open)
      create_annotation(session, :closed)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "All (2)"
    end

    test "renders per-project chips with name and count" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")

      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_annotation(sess_a, :open)
      create_annotation(sess_b, :open)
      create_annotation(sess_b, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "alpha (1)"
      assert html =~ "beta (2)"
    end

    test "renders All (0) when no projects exist" do
      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "All (0)"
    end

    test "includes project with zero open annotations in chips" do
      proj_a = create_project("alpha")
      create_project("beta")

      sess_a = create_session(proj_a)
      create_annotation(sess_a, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "alpha (1)"
      assert html =~ "beta (0)"
    end
  end

  describe "all-project mode" do
    test "hides action buttons and shows helper text" do
      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "Select a project to open or close a review session."
      refute html =~ "Open conversation"
      refute html =~ "Close review session"
    end

    test "renders empty state copy" do
      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "No open annotations for the selected scope."
    end

    test "shows annotations from all projects" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")
      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_annotation(sess_a, :open)
      create_annotation(sess_b, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "alpha"
      assert html =~ "beta"
    end
  end

  describe "project-scoped mode" do
    test "shows action buttons in project mode" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "Open conversation"
      assert html =~ "Close review session"
    end

    test "renders empty state when project has no open annotations" do
      project = create_project("alpha")

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "No open annotations for the selected scope."
    end

    test "excludes closed annotations" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :closed)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "No open annotations for the selected scope."
    end
  end

  describe "project chip navigation" do
    test "clicking a project chip updates URL and filters" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")
      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_annotation(sess_a, :open)
      create_annotation(sess_b, :open)

      {:ok, view, _html} = live(build_conn(), "/reviews")

      # Click project alpha chip
      html =
        render_click(view, "filter_project", %{"project-id" => proj_a.id})

      # Should show alpha's annotation and action buttons
      assert html =~ "Open conversation"
      assert_patched(view, "/reviews?project_id=#{proj_a.id}")
    end

    test "clicking All chip returns to all-project mode" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      html = render_click(view, "filter_project", %{"project-id" => "all"})

      assert html =~ "Select a project to open or close a review session."
      assert_patched(view, "/reviews")
    end
  end

  describe "invalid project_id" do
    test "falls back to all-project mode" do
      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{Ash.UUID.generate()}")

      assert html =~ "Select a project to open or close a review session."
      assert html =~ "No open annotations for the selected scope."
    end

    test "does not crash with non-UUID value" do
      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=bogus")

      assert html =~ "Reviews"
    end
  end

  describe "sidebar badge" do
    test "shows badge with positive count" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      conn = build_conn() |> get("/reviews")
      html = html_response(conn, 200)

      assert html =~ "sidebar-badge"
    end

    test "hides badge when count is zero" do
      conn = build_conn() |> get("/reviews")
      html = html_response(conn, 200)

      refute html =~ "sidebar-badge"
    end
  end
end
