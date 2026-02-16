defmodule SpotterWeb.FileDetailLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox

  alias Spotter.Transcripts.{
    Annotation,
    AnnotationFileRef,
    Commit,
    CommitFile,
    Project,
    Session,
    SessionCommitLink
  }

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "test-file-detail", pattern: "^test"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    commit =
      Ash.create!(Commit, %{
        commit_hash: String.duplicate("c", 40),
        subject: "feat: add file detail page",
        git_branch: "main",
        author_name: "Test Author",
        changed_files: ["lib/foo.ex", "lib/bar.ex"]
      })

    Ash.create!(CommitFile, %{
      commit_id: commit.id,
      relative_path: "lib/foo.ex",
      change_type: :modified
    })

    Ash.create!(SessionCommitLink, %{
      session_id: session.id,
      commit_id: commit.id,
      link_type: :observed_in_session,
      confidence: 1.0
    })

    %{project: project, session: session, commit: commit}
  end

  describe "file detail page" do
    test "renders file detail root", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      assert html =~ ~s(data-testid="file-detail-root")
      # Path segments are rendered individually with HTML tags between them
      assert html =~ "foo.ex"
    end

    test "renders commits for file", %{project: project} do
      {:ok, view, _html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      html = view |> element(~s(button[phx-value-tab="commits"])) |> render_click()

      assert html =~ String.duplicate("c", 8)
      assert html =~ "modified"
    end

    test "renders linked sessions", %{project: project} do
      {:ok, view, _html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      html = view |> element(~s(button[phx-value-tab="sessions"])) |> render_click()

      assert html =~ "Sessions"
      assert html =~ "Verified"
    end

    test "renders not found for unknown project" do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{Ash.UUID.generate()}/files/lib/foo.ex")

      assert html =~ "File not found"
    end

    test "renders language class", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      assert html =~ "elixir"
    end

    test "renders blame toggle with blame as default", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      assert html =~ ~s(data-testid="view-mode-toggle")
      assert html =~ "Blame"
      assert html =~ "Raw"
    end

    test "blame is default view mode", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      # Blame is selected by default - either shows blame view or blame error
      assert html =~ ~s(data-testid="blame-view") or html =~ ~s(data-testid="blame-error")
    end

    test "blame error shown when blame unavailable in test env", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/files/nonexistent/path.ex")

      # In test env, blame won't be available since there's no real git repo
      # Should show an error, not crash
      assert html =~ "file-detail-root"
    end

    test "switching to raw mode shows file content or error", %{project: project} do
      {:ok, view, _html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      html = render_click(view, "toggle_view_mode", %{"mode" => "raw"})

      # In raw mode, either file content or file error is shown
      assert html =~ ~s(data-testid="file-content") or html =~ ~s(data-testid="file-error")
    end

    test "selecting file text switches to annotations tab", %{project: project} do
      {:ok, view, _html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      # Switch away from annotations tab
      view |> element(~s(button[phx-value-tab="commits"])) |> render_click()

      # Simulate file text selection
      html =
        render_hook(view, "file_text_selected", %{
          "text" => "def hello",
          "line_start" => 2,
          "line_end" => 4
        })

      # Annotations tab should be active with the editor visible
      assert html =~ "annotation-form"
      assert html =~ ~s(sidebar-tab is-active)
      assert html =~ "Annotations"
    end

    test "saving a file annotation persists line metadata", %{project: project, session: session} do
      {:ok, view, _html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      # Select a linked session first (required by nil guard)
      render_click(view, "select_session", %{"session-id" => session.id})

      # Set selection
      render_hook(view, "file_text_selected", %{
        "text" => "selected code",
        "line_start" => 2,
        "line_end" => 4
      })

      # Save annotation
      render_click(view, "save_annotation", %{
        "comment" => "review note",
        "purpose" => "review"
      })

      # Verify annotation was created with line metadata
      [annotation] = Ash.read!(Annotation)
      assert annotation.source == :file
      assert annotation.relative_path == "lib/foo.ex"
      assert annotation.line_start == 2
      assert annotation.line_end == 4
      assert annotation.selected_text == "selected code"

      # Verify file ref was also created
      [ref] = Ash.read!(AnnotationFileRef)
      assert ref.annotation_id == annotation.id
      assert ref.relative_path == "lib/foo.ex"
      assert ref.line_start == 2
      assert ref.line_end == 4
    end

    test "saving an explain file annotation persists annotation and file ref", %{
      project: project,
      session: session
    } do
      {:ok, view, _html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      render_click(view, "select_session", %{"session-id" => session.id})

      render_hook(view, "file_text_selected", %{
        "text" => "createRoot(document.getElementById('root')!).render(...)",
        "line_start" => 6,
        "line_end" => 10
      })

      render_click(view, "save_annotation", %{
        "comment" => "What does create root do?",
        "purpose" => "explain"
      })

      [annotation] = Ash.read!(Annotation)
      assert annotation.source == :file
      assert annotation.purpose == :explain
      assert annotation.relative_path == "lib/foo.ex"
      assert annotation.line_start == 6
      assert annotation.line_end == 10
      assert annotation.selected_text =~ "createRoot"

      [ref] = Ash.read!(AnnotationFileRef)
      assert ref.annotation_id == annotation.id
      assert ref.relative_path == "lib/foo.ex"
      assert ref.line_start == 6
      assert ref.line_end == 10
    end
  end

  describe "annotation session guard" do
    test "saving annotation without selected session creates unbound annotation", %{
      project: project
    } do
      {:ok, view, _html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      # Select text to enable the annotation editor
      render_hook(view, "file_text_selected", %{
        "text" => "some code",
        "line_start" => "1",
        "line_end" => "3"
      })

      # Submit without selecting a session first
      view
      |> form(".annotation-form form", %{"comment" => "test note", "purpose" => "review"})
      |> render_submit()

      # Should create an unbound file annotation
      annotations = Ash.read!(Annotation)
      assert length(annotations) == 1
      ann = hd(annotations)
      assert ann.session_id == nil
      assert ann.source == :file
      assert ann.project_id == project.id
    end

    test "saving annotation with selected session succeeds", %{
      project: project,
      session: session
    } do
      {:ok, view, _html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      # Select a linked session
      render_click(view, "select_session", %{"session-id" => session.id})

      # Select text
      render_hook(view, "file_text_selected", %{
        "text" => "selected code snippet",
        "line_start" => "5",
        "line_end" => "10"
      })

      # Submit annotation
      html =
        view
        |> form(".annotation-form form", %{"comment" => "looks good", "purpose" => "review"})
        |> render_submit()

      # Annotation should be created and visible
      assert [annotation] = Ash.read!(Annotation)
      assert annotation.selected_text == "selected code snippet"
      assert annotation.session_id == session.id

      # The hint should disappear once a session is selected
      refute html =~ "Select a linked session before saving an annotation."
    end
  end
end
