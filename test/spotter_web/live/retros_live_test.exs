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

  defp create_item(submission, opts) do
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
      # Session link with href
      assert html =~ ~s(href="/sessions/#{session.session_id}")
      # Item count
      assert html =~ "2 items"
    end
  end

  describe "session links" do
    test "session label links to session detail page" do
      project = create_project("alpha")
      session = create_session(project)
      create_submission(project, session, summary: "Link test")

      {:ok, _view, html} = live(build_conn(), "/retros?project_id=#{project.id}")

      assert html =~ ~s(href="/sessions/#{session.session_id}")
    end

    test "session link shows meaningful label from SessionPresenter" do
      project = create_project("alpha")

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id,
          custom_title: "Fix worktree scoping"
        })

      create_submission(project, session, summary: "Label test")

      {:ok, _view, html} = live(build_conn(), "/retros?project_id=#{project.id}")

      # Should show custom_title, not truncated session_id
      assert html =~ "Fix worktree scoping"
    end
  end

  describe "expandable submission cards" do
    test "clicking a submission card expands it to show items" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Expand me")
      create_item(sub, category: :knowledge_gained, observation: "Learned something important")

      {:ok, view, html} = live(build_conn(), "/retros?project_id=#{project.id}")

      # Items not visible in collapsed state
      refute html =~ "Learned something important"

      # Click to expand
      html = render_click(view, "toggle_submission", %{"id" => sub.id})

      # Items now visible
      assert html =~ "Learned something important"
    end

    test "expanded card shows all items with category badges" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Badge test")

      create_item(sub, category: :knowledge_gained, observation: "Knowledge obs")
      create_item(sub, category: :gotcha, observation: "Gotcha obs")
      create_item(sub, category: :effective_strategy, observation: "Strategy obs")
      create_item(sub, category: :requirements_clarity, observation: "Requirements obs")
      create_item(sub, category: :struggle, observation: "Struggle obs")

      {:ok, view, _html} = live(build_conn(), "/retros?project_id=#{project.id}")

      html = render_click(view, "toggle_submission", %{"id" => sub.id})

      # All items visible
      assert html =~ "Knowledge obs"
      assert html =~ "Gotcha obs"
      assert html =~ "Strategy obs"
      assert html =~ "Requirements obs"
      assert html =~ "Struggle obs"

      # Each category has a distinct badge
      assert html =~ "knowledge_gained"
      assert html =~ "gotcha"
      assert html =~ "effective_strategy"
      assert html =~ "requirements_clarity"
      assert html =~ "struggle"
    end

    test "clicking expanded card collapses it" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Toggle test")
      create_item(sub, category: :knowledge_gained, observation: "Visible then hidden")

      {:ok, view, _html} = live(build_conn(), "/retros?project_id=#{project.id}")

      # Expand
      html = render_click(view, "toggle_submission", %{"id" => sub.id})
      assert html =~ "Visible then hidden"

      # Collapse
      html = render_click(view, "toggle_submission", %{"id" => sub.id})
      refute html =~ "Visible then hidden"
    end

    test "collapsed state shows summary, item count, and category distribution" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Distribution test")

      create_item(sub, category: :knowledge_gained)
      create_item(sub, category: :knowledge_gained)
      create_item(sub, category: :gotcha)

      {:ok, _view, html} = live(build_conn(), "/retros?project_id=#{project.id}")

      # Summary visible in collapsed state
      assert html =~ "Distribution test"
      # Item count
      assert html =~ "3 items"
      # Category distribution badges visible in collapsed state
      assert html =~ "knowledge_gained"
      assert html =~ "gotcha"
    end

    test "items show observation and explanation text" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Content test")

      create_item(sub,
        category: :effective_strategy,
        observation: "Pair programming worked well",
        explanation: "It caught bugs early in the process"
      )

      {:ok, view, _html} = live(build_conn(), "/retros?project_id=#{project.id}")

      html = render_click(view, "toggle_submission", %{"id" => sub.id})

      assert html =~ "Pair programming worked well"
      assert html =~ "It caught bugs early in the process"
    end
  end

  describe "rating buttons" do
    test "each item in expanded card shows three rating buttons" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Rate me")
      create_item(sub, category: :knowledge_gained, observation: "Rate this item")

      {:ok, view, _html} = live(build_conn(), "/retros?project_id=#{project.id}")

      html = render_click(view, "toggle_submission", %{"id" => sub.id})

      assert html =~ "Useful"
      assert html =~ "Undecided"
      assert html =~ "Not useful"
    end

    test "clicking a rating button updates the item rating" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Rate me")
      item = create_item(sub, category: :knowledge_gained, observation: "Rate this")

      {:ok, view, _html} = live(build_conn(), "/retros?project_id=#{project.id}")

      # Expand the card
      render_click(view, "toggle_submission", %{"id" => sub.id})

      # Click "useful" rating
      _html = render_click(view, "rate_item", %{"item-id" => item.id, "rating" => "useful"})

      # Rating should be persisted — reload from DB to verify
      updated_item = Ash.get!(RetroItem, item.id)
      assert updated_item.rating == :useful
    end

    test "current rating button is visually highlighted" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Highlight test")
      item = create_item(sub, category: :gotcha, observation: "Check highlight")

      {:ok, view, _html} = live(build_conn(), "/retros?project_id=#{project.id}")

      # Expand and rate as useful
      render_click(view, "toggle_submission", %{"id" => sub.id})
      html = render_click(view, "rate_item", %{"item-id" => item.id, "rating" => "useful"})

      # The useful button should have is-active class
      assert html =~
               "rating-btn is-active rating-useful"
    end

    test "default rating is undecided" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Default test")
      _item = create_item(sub, category: :knowledge_gained, observation: "Default rating")

      {:ok, view, _html} = live(build_conn(), "/retros?project_id=#{project.id}")

      html = render_click(view, "toggle_submission", %{"id" => sub.id})

      # Undecided button should be highlighted by default
      assert html =~
               "rating-btn is-active rating-undecided"
    end

    test "rating persists after page reload" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Persist test")
      item = create_item(sub, category: :struggle, observation: "Persistent rating")

      {:ok, view, _html} = live(build_conn(), "/retros?project_id=#{project.id}")

      # Expand and rate
      render_click(view, "toggle_submission", %{"id" => sub.id})
      render_click(view, "rate_item", %{"item-id" => item.id, "rating" => "not_useful"})

      # Reload the page entirely
      {:ok, view2, _html} = live(build_conn(), "/retros?project_id=#{project.id}")
      html = render_click(view2, "toggle_submission", %{"id" => sub.id})

      # not_useful should still be highlighted
      assert html =~
               "rating-btn is-active rating-not_useful"
    end

    test "rating distribution summary on submission card header" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Distribution test")
      item1 = create_item(sub, category: :knowledge_gained, observation: "Item 1")
      item2 = create_item(sub, category: :gotcha, observation: "Item 2")
      item3 = create_item(sub, category: :struggle, observation: "Item 3")

      # Rate items
      Ash.update!(item1, %{rating: :useful}, action: :rate)
      Ash.update!(item2, %{rating: :useful}, action: :rate)
      Ash.update!(item3, %{rating: :not_useful}, action: :rate)

      {:ok, _view, html} = live(build_conn(), "/retros?project_id=#{project.id}")

      # Rating distribution should be visible on the collapsed card
      assert html =~ "2 Useful"
      assert html =~ "1 Not useful"
    end
  end

  describe "negative-path tests" do
    test "invalid rating value does not crash the LiveView" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Invalid rating test")
      item = create_item(sub, category: :knowledge_gained, observation: "Obs")

      {:ok, view, _html} = live(build_conn(), "/retros?project_id=#{project.id}")
      render_click(view, "toggle_submission", %{"id" => sub.id})

      html = render_click(view, "rate_item", %{"item-id" => item.id, "rating" => "super_useful"})

      assert html =~ "Failed to save rating"

      # Verify rating unchanged
      reloaded = Ash.get!(RetroItem, item.id)
      assert reloaded.rating == :undecided
    end

    test "unknown item-id does not crash the LiveView" do
      project = create_project("alpha")
      session = create_session(project)
      sub = create_submission(project, session, summary: "Unknown item test")
      create_item(sub, category: :gotcha, observation: "Obs")

      {:ok, view, _html} = live(build_conn(), "/retros?project_id=#{project.id}")
      render_click(view, "toggle_submission", %{"id" => sub.id})

      html =
        render_click(view, "rate_item", %{
          "item-id" => "00000000-0000-0000-0000-000000000000",
          "rating" => "useful"
        })

      assert html =~ "Failed to save rating"
    end
  end
end
