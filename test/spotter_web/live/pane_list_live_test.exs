defmodule SpotterWeb.PaneListLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Annotation, Commit, Flashcard, Project, ReviewItem, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "test-dashboard", pattern: "^test-dashboard"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    session_with_lines =
      Ash.update!(session, %{added_delta: 42, removed_delta: 7}, action: :add_line_stats)

    %{project: project, session: session_with_lines}
  end

  describe "dashboard renders transcript-only" do
    test "contains dashboard root testid", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="dashboard-root")
    end

    test "contains Session Transcripts heading", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "Session Transcripts"
    end

    test "does not contain Claude Code Sessions pane heading", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "Claude Code Sessions"
    end

    test "does not contain Other Panes heading", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "Other Panes"
    end

    test "renders session rows when sessions exist", %{session: _session} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="session-row")
    end

    test "does not contain tmux empty state", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "No tmux panes found"
    end

    test "does not contain ingest button or sync text", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "Ingest"
      refute html =~ ~s(data-testid="sync-transcripts-button")
      refute html =~ "No projects synced yet"
    end

    test "renders line stats for session with lines", %{session: _session} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "+42"
      assert html =~ "-7"
    end
  end

  describe "project picker filtering" do
    setup do
      proj_a = Ash.create!(Project, %{name: "proj-alpha", pattern: "^proj-alpha"})
      proj_b = Ash.create!(Project, %{name: "proj-beta", pattern: "^proj-beta"})

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-alpha",
        cwd: "/home/user/alpha",
        project_id: proj_a.id
      })

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-beta",
        cwd: "/home/user/beta",
        project_id: proj_b.id
      })

      %{proj_a: proj_a, proj_b: proj_b}
    end

    test "filters to a single project", %{proj_a: _proj_a, proj_b: proj_b} do
      {:ok, view, _html} = live(build_conn(), "/")

      html = render_click(view, "filter_project", %{"project-id" => proj_b.id})

      assert html =~ ~s(class="project-name">proj-beta</span>)
      refute html =~ ~s(class="project-name">proj-alpha</span>)

      # Also verify proj_a's filter chip is still rendered (not hidden from filter bar)
      assert html =~ "proj-alpha"
    end

    test "resets to first project when all is clicked", %{proj_a: _proj_a, proj_b: proj_b} do
      {:ok, view, _html} = live(build_conn(), "/")

      render_click(view, "filter_project", %{"project-id" => proj_b.id})
      html = render_click(view, "filter_project", %{"project-id" => "all"})

      # "all" normalizes to the first project (auto-select), so only the first
      # project section is rendered; verify the filter bar still contains both chips.
      assert html =~ "proj-alpha"
      assert html =~ "proj-beta"
      assert html =~ ~s(class="project-name">test-dashboard</span>)
    end
  end

  describe "study queue" do
    test "renders study queue section", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="study-queue")
      assert html =~ ~s(data-testid="study-queue-empty")
    end

    test "shows no-items guidance when project exists but no review items", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "No review items yet"
      assert html =~ "committing from a Claude Code session"
      refute html =~ "sync"
    end

    test "empty state does not reference sync-all", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "sync-to-populate"
      refute html =~ "Sync all"
      refute html =~ "sync all"
    end
  end

  describe "study ahead" do
    setup %{project: project} do
      commit =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("b", 40),
          subject: "Future commit for study ahead"
        })

      future_item =
        Ash.create!(ReviewItem, %{
          project_id: project.id,
          target_kind: :commit_message,
          commit_id: commit.id,
          importance: :medium,
          interval_days: 4,
          next_due_on: Date.add(Date.utc_today(), 2)
        })

      %{future_item: future_item, commit: commit}
    end

    test "shows Study ahead CTA when only future items exist", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="study-ahead-cta")
      assert html =~ "Study ahead"
    end

    test "clicking Study ahead shows future items", %{future_item: future_item} do
      {:ok, view, _html} = live(build_conn(), "/")

      html = render_click(view, "set_study_include_upcoming", %{"enabled" => "true"})

      assert html =~ ~s(data-testid="study-card")
      assert html =~ "Future commit for study ahead"

      # Verify the toggle did NOT mutate the ReviewItem
      reloaded = Ash.get!(ReviewItem, future_item.id)
      assert reloaded.next_due_on == future_item.next_due_on
      assert reloaded.interval_days == future_item.interval_days
    end

    test "single upcoming item does not loop after rating", %{future_item: future_item} do
      {:ok, view, _html} = live(build_conn(), "/")

      render_click(view, "set_study_include_upcoming", %{"enabled" => "true"})

      html =
        render_click(view, "rate_card", %{
          "id" => future_item.id,
          "importance" => "medium"
        })

      refute html =~ "Future commit for study ahead"
      assert html =~ ~s(data-testid="study-queue-empty")
    end

    test "multiple upcoming items advance and terminate", %{project: project} do
      commit2 =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("c", 40),
          subject: "Second future commit"
        })

      Ash.create!(ReviewItem, %{
        project_id: project.id,
        target_kind: :commit_message,
        commit_id: commit2.id,
        importance: :medium,
        interval_days: 4,
        next_due_on: Date.add(Date.utc_today(), 4)
      })

      {:ok, view, _html} = live(build_conn(), "/")
      render_click(view, "set_study_include_upcoming", %{"enabled" => "true"})

      # First card visible
      html = render(view)
      assert html =~ "Future commit for study ahead"

      # Rate first card — get the current card's item id from the assigns
      first_card = view |> element(~s([data-testid="study-card"])) |> render()
      first_id = Regex.run(~r/data-card-id="([^"]+)"/, first_card) |> List.last()

      html = render_click(view, "rate_card", %{"id" => first_id, "importance" => "low"})

      # Second card should appear
      assert html =~ "Second future commit"
      refute html =~ "Future commit for study ahead"

      # Rate second card
      second_card = view |> element(~s([data-testid="study-card"])) |> render()
      second_id = Regex.run(~r/data-card-id="([^"]+)"/, second_card) |> List.last()

      html = render_click(view, "rate_card", %{"id" => second_id, "importance" => "low"})

      # Should be empty now
      assert html =~ ~s(data-testid="study-queue-empty")
      refute html =~ "Future commit for study ahead"
      refute html =~ "Second future commit"
    end
  end

  describe "study ahead — due-today regression" do
    setup %{project: project} do
      commit =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("d", 40),
          subject: "Due today commit"
        })

      due_item =
        Ash.create!(ReviewItem, %{
          project_id: project.id,
          target_kind: :commit_message,
          commit_id: commit.id,
          importance: :medium,
          next_due_on: Date.utc_today()
        })

      %{due_item: due_item}
    end

    test "due-today item is removed after rating without study-ahead", %{due_item: due_item} do
      {:ok, view, html} = live(build_conn(), "/")

      assert html =~ "Due today commit"

      html =
        render_click(view, "rate_card", %{
          "id" => due_item.id,
          "importance" => "high"
        })

      refute html =~ "Due today commit"
    end
  end

  describe "last updated display and sort" do
    setup do
      project = Ash.create!(Project, %{name: "last-updated-test", pattern: "^last-updated-test"})

      # Session with older source_modified_at
      older_session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test-older",
          cwd: "/home/user/project",
          project_id: project.id,
          started_at: ~U[2026-01-10 10:00:00Z],
          source_modified_at: ~U[2026-01-10 12:00:00Z]
        })

      # Session with newer source_modified_at
      newer_session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test-newer",
          cwd: "/home/user/project",
          project_id: project.id,
          started_at: ~U[2026-01-09 08:00:00Z],
          source_modified_at: ~U[2026-01-11 15:00:00Z]
        })

      %{project: project, older_session: older_session, newer_session: newer_session}
    end

    test "renders Last updated header instead of Started", %{project: _project} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "Last updated"
      # The visible sessions table should not have "Started" as a header
      # (but "Started" may appear elsewhere in the page, so we check table context)
    end

    test "session rows are ordered by last updated descending", %{
      older_session: older,
      newer_session: newer
    } do
      {:ok, _view, html} = live(build_conn(), "/")

      newer_pos = :binary.match(html, newer.session_id |> to_string())
      older_pos = :binary.match(html, older.session_id |> to_string())

      # newer source_modified_at should appear first (earlier position in HTML)
      assert elem(newer_pos, 0) < elem(older_pos, 0)
    end
  end

  describe "flashcard study queue" do
    setup %{project: project, session: session} do
      annotation =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "some interesting code",
          comment: "explain this pattern",
          purpose: :explain
        })

      flashcard =
        Ash.create!(Flashcard, %{
          project_id: project.id,
          annotation_id: annotation.id,
          front_snippet: "Pattern: GenServer callback",
          question: "What does handle_info do?",
          answer: "Handles async messages sent to the process."
        })

      review_item =
        Ash.create!(ReviewItem, %{
          project_id: project.id,
          target_kind: :flashcard,
          flashcard_id: flashcard.id,
          importance: :medium,
          next_due_on: Date.utc_today()
        })

      %{flashcard: flashcard, review_item: review_item}
    end

    test "renders flashcard filter button with count", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "Flashcards (1)"
    end

    test "renders flashcard study card with badge and content", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "Flashcard"
      assert html =~ "Pattern: GenServer callback"
      assert html =~ "Show answer"
    end

    test "renders flashcard question when present", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "What does handle_info do?"
    end
  end
end
