defmodule SpotterWeb.CommitDetailLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox

  alias Spotter.Transcripts.{
    CoChangeGroup,
    Commit,
    Message,
    Project,
    ProjectPeriodSummary,
    ProjectRollingSummary,
    Session,
    SessionCommitLink
  }

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "test-commit-detail", pattern: "^test"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    commit =
      Ash.create!(Commit, %{
        commit_hash: String.duplicate("a", 40),
        subject: "feat: add commit detail",
        git_branch: "main",
        author_name: "Test Author",
        changed_files: ["lib/foo.ex", "lib/bar.ex"]
      })

    Ash.create!(SessionCommitLink, %{
      session_id: session.id,
      commit_id: commit.id,
      link_type: :observed_in_session,
      confidence: 1.0
    })

    %{project: project, session: session, commit: commit}
  end

  describe "commit detail page" do
    test "renders commit metadata", %{commit: commit} do
      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ ~s(data-testid="commit-detail-root")
      assert html =~ String.duplicate("a", 40)
      assert html =~ "feat: add commit detail"
      assert html =~ "main"
      assert html =~ "Test Author"
    end

    test "renders changed files list", %{commit: commit} do
      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ "lib/foo.ex"
      assert html =~ "lib/bar.ex"
      assert html =~ "2 files changed"
    end

    test "renders diff panel", %{commit: commit} do
      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ ~s(data-testid="diff-panel")
      assert html =~ ~s(data-testid="diff-content")
      assert html =~ "language-diff"
    end

    test "renders linked sessions", %{commit: commit} do
      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ "Linked Sessions (1)"
      assert html =~ "Verified"
    end

    test "selecting a session loads transcript", %{commit: commit, session: session} do
      Ash.create!(Message, %{
        uuid: Ash.UUID.generate(),
        type: :assistant,
        role: :assistant,
        timestamp: DateTime.utc_now(),
        session_id: session.id,
        content: %{"blocks" => [%{"type" => "text", "text" => "Hello from commit session"}]}
      })

      {:ok, view, _html} = live(build_conn(), "/history/commits/#{commit.id}")

      html =
        view
        |> element(".commit-detail-session-btn")
        |> render_click()

      assert html =~ "Hello from commit session"
    end

    test "renders not found for unknown commit" do
      {:ok, _view, html} = live(build_conn(), "/history/commits/#{Ash.UUID.generate()}")

      assert html =~ "Commit not found"
    end
  end

  describe "summary sections" do
    test "renders rolling summary when available", %{project: project, commit: commit} do
      Ash.create!(ProjectRollingSummary, %{
        project_id: project.id,
        bucket_kind: :day,
        timezone: "Etc/UTC",
        default_branch: "main",
        lookback_days: 14,
        included_bucket_start_dates: [],
        summary_text: "Active work on timezone features",
        computed_at: DateTime.utc_now()
      })

      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ "Active work on timezone features"
      assert html =~ "Project Rollup"
    end

    test "renders period summary when available", %{project: project, commit: commit} do
      bucket_date = Date.utc_today()

      Ash.create!(ProjectPeriodSummary, %{
        project_id: project.id,
        bucket_kind: :day,
        bucket_start_date: bucket_date,
        timezone: "Etc/UTC",
        default_branch: "main",
        included_session_ids: [],
        included_commit_hashes: [],
        summary_text: "Focused on distillation pipeline",
        computed_at: DateTime.utc_now()
      })

      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ "Focused on distillation pipeline"
      assert html =~ "Bucket Summary"
    end

    test "renders session distilled summary when available", %{
      project: project,
      commit: commit
    } do
      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test-sessions",
          cwd: "/home/user/project",
          project_id: project.id
        })

      Ash.update!(session, %{
        distilled_status: :completed,
        distilled_summary: "Implemented commit detail summaries"
      })

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ "Implemented commit detail summaries"
    end

    test "shows placeholder when no summaries computed", %{commit: commit} do
      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ "No rolling summary computed yet."
      assert html =~ "No bucket summary computed yet."
    end
  end

  describe "breadcrumb navigation" do
    test "shows history link in breadcrumb", %{commit: commit} do
      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ ~s(href="/history")
      assert html =~ "History"
    end
  end

  describe "file links" do
    test "changed files render as links when linked session exists", %{
      project: project,
      commit: commit
    } do
      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ "/projects/#{project.id}/files/lib/foo.ex"
      assert html =~ "/projects/#{project.id}/files/lib/bar.ex"
    end

    test "co-change members render as links when linked session exists", %{
      project: project,
      commit: commit
    } do
      Ash.create!(CoChangeGroup, %{
        scope: :file,
        group_key: "lib/foo.ex+lib/baz.ex",
        members: ["lib/foo.ex", "lib/baz.ex"],
        frequency_30d: 5,
        project_id: project.id
      })

      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ "/projects/#{project.id}/files/lib/foo.ex"
      assert html =~ "/projects/#{project.id}/files/lib/baz.ex"
    end

    test "diff container has DiffHighlighter hook", %{commit: commit} do
      {:ok, _view, html} = live(build_conn(), "/history/commits/#{commit.id}")

      assert html =~ ~s(phx-hook="DiffHighlighter")
    end
  end
end
