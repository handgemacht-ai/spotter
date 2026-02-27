defmodule SpotterWeb.RetrosLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Project, RetroItem, RetroSubmission, Session}

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

  defp create_submission(project, session, opts \\ []) do
    Ash.create!(RetroSubmission, %{
      summary: Keyword.get(opts, :summary, "Retro summary #{System.unique_integer([:positive])}"),
      submitted_at: Keyword.get(opts, :submitted_at, DateTime.utc_now()),
      session_id: session.id,
      project_id: project.id
    })
  end

  defp create_item(submission, opts \\ []) do
    Ash.create!(RetroItem, %{
      retro_submission_id: submission.id,
      category: Keyword.get(opts, :category, :knowledge_gained),
      observation:
        Keyword.get(opts, :observation, "Observation #{System.unique_integer([:positive])}"),
      explanation:
        Keyword.get(opts, :explanation, "Explanation #{System.unique_integer([:positive])}")
    })
  end

  describe "page structure" do
    test "renders heading and project filter chips with retro submission counts" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")

      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_submission(proj_a, sess_a)
      create_submission(proj_b, sess_b)
      create_submission(proj_b, sess_b)

      {:ok, _view, html} = live(build_conn(), "/retros")

      assert html =~ "Retros"
      assert html =~ "alpha (1)"
      assert html =~ "beta (2)"
    end
  end

  describe "auto-select first project" do
    test "auto-selects first project and shows its submissions" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")

      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      _sub_a = create_submission(proj_a, sess_a, summary: "Alpha retro summary")
      _sub_b = create_submission(proj_b, sess_b, summary: "Beta retro summary")

      {:ok, _view, html} = live(build_conn(), "/retros")

      # Auto-selects first project (alpha), so only alpha's submissions appear
      assert html =~ "Alpha retro summary"
      refute html =~ "Beta retro summary"
    end

    test "shows empty state when no submissions exist" do
      create_project("alpha")

      {:ok, _view, html} = live(build_conn(), "/retros")

      assert html =~ "No retro submissions"
    end
  end

  describe "project chip navigation" do
    test "clicking a project chip updates URL and filters submissions" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")

      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_submission(proj_a, sess_a, summary: "Alpha submission")
      create_submission(proj_b, sess_b, summary: "Beta submission")

      {:ok, view, _html} = live(build_conn(), "/retros")

      # Click project beta chip
      html = render_click(view, "filter_project", %{"project-id" => proj_b.id})

      assert html =~ "Beta submission"
      refute html =~ "Alpha submission"
      assert_patched(view, "/retros?project_id=#{proj_b.id}")
    end
  end

  describe "invalid project_id" do
    test "falls back to first project for invalid project_id" do
      project = create_project("alpha")
      session = create_session(project)
      create_submission(project, session, summary: "Fallback submission")

      {:ok, _view, html} = live(build_conn(), "/retros?project_id=#{Ash.UUID.generate()}")

      # Invalid project falls back to first project
      assert html =~ "Fallback submission"
    end

    test "does not crash with non-UUID value" do
      {:ok, _view, html} = live(build_conn(), "/retros?project_id=bogus")

      assert html =~ "Retros"
    end
  end

  describe "submission ordering and display" do
    test "submissions sorted by submitted_at desc" do
      project = create_project("alpha")
      session = create_session(project)

      create_submission(project, session,
        summary: "Older retro",
        submitted_at: ~U[2026-02-25 10:00:00Z]
      )

      create_submission(project, session,
        summary: "Newer retro",
        submitted_at: ~U[2026-02-27 10:00:00Z]
      )

      {:ok, _view, html} = live(build_conn(), "/retros?project_id=#{project.id}")

      # Newer should appear before older in the HTML
      newer_pos = :binary.match(html, "Newer retro") |> elem(0)
      older_pos = :binary.match(html, "Older retro") |> elem(0)

      assert newer_pos < older_pos
    end

    test "each submission shows summary, timestamp, session label, item count" do
      project = create_project("alpha")
      session = create_session(project)

      sub =
        create_submission(project, session,
          summary: "My detailed retro",
          submitted_at: ~U[2026-02-27 14:30:00Z]
        )

      create_item(sub, category: :knowledge_gained)
      create_item(sub, category: :gotcha)

      {:ok, _view, html} = live(build_conn(), "/retros?project_id=#{project.id}")

      # Summary
      assert html =~ "My detailed retro"
      # Timestamp
      assert html =~ "2026-02-27"
      # Session label (short session_id)
      assert html =~ String.slice(session.session_id, 0, 8)
      # Item count
      assert html =~ "2 items"
    end
  end
end
