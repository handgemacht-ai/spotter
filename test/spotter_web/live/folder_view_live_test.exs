defmodule SpotterWeb.FolderViewLiveTest do
  use Spotter.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Spotter.Transcripts.{Annotation, AnnotationFileRef, Project, Session}

  @moduletag timeout: 30_000
  @endpoint SpotterWeb.Endpoint

  setup do
    project = Ash.create!(Project, %{name: "folder-view-test", pattern: "^folder-view"})

    repo_root =
      Path.join(System.tmp_dir!(), "folder_view_test_#{System.unique_integer([:positive])}")

    skill_dir = Path.join(repo_root, ".claude/skills/product")
    File.mkdir_p!(skill_dir)
    File.write!(Path.join(skill_dir, "SKILL.md"), "# Product Skill\n\nUse this for product work.")

    File.write!(
      Path.join(skill_dir, "references.md"),
      "# References\n\n- Item one\n- Item two"
    )

    System.cmd("git", ["init"], cd: repo_root)

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-sessions",
        cwd: repo_root,
        project_id: project.id
      })

    on_exit(fn -> File.rm_rf!(repo_root) end)

    %{project: project, session: session, repo_root: repo_root}
  end

  describe "mount renders folder content" do
    test "renders file sections for files in folder", %{project: project} do
      {:ok, _view, html} =
        live(
          build_conn(),
          "/projects/#{project.id}/folders/.claude/skills/product"
        )

      assert html =~ "SKILL.md"
      assert html =~ "references.md"
      assert html =~ "Product Skill"
    end

    test "renders folder path in page header", %{project: project} do
      {:ok, _view, html} =
        live(
          build_conn(),
          "/projects/#{project.id}/folders/.claude/skills/product"
        )

      assert html =~ ".claude/skills/product"
    end

    test "renders empty state for empty folder", %{project: project, repo_root: repo_root} do
      empty_dir = Path.join(repo_root, ".claude/empty-folder")
      File.mkdir_p!(empty_dir)

      {:ok, _view, html} =
        live(
          build_conn(),
          "/projects/#{project.id}/folders/.claude/empty-folder"
        )

      assert html =~ "empty"
    end
  end

  describe "folder_text_selected event" do
    test "sets selection assigns and shows annotation form", %{project: project} do
      {:ok, view, _html} =
        live(
          build_conn(),
          "/projects/#{project.id}/folders/.claude/skills/product"
        )

      html =
        render_hook(view, "folder_text_selected", %{
          "file_path" => ".claude/skills/product/SKILL.md",
          "selected_text" => "Use this for product work.",
          "line_start" => 3,
          "line_end" => 3
        })

      assert html =~ "annotation"
      assert html =~ "Use this for product work."
    end
  end

  describe "save_annotation" do
    test "creates Annotation and AnnotationFileRef with correct file path", %{
      project: project
    } do
      {:ok, view, _html} =
        live(
          build_conn(),
          "/projects/#{project.id}/folders/.claude/skills/product"
        )

      render_hook(view, "folder_text_selected", %{
        "file_path" => ".claude/skills/product/SKILL.md",
        "selected_text" => "Use this for product work.",
        "line_start" => 3,
        "line_end" => 3
      })

      render_click(view, "save_annotation", %{
        "comment" => "This needs more detail",
        "purpose" => "review"
      })

      [annotation] = Ash.read!(Annotation)
      assert annotation.source == :file
      assert annotation.selected_text == "Use this for product work."
      assert annotation.comment == "This needs more detail"
      assert annotation.purpose == :review
      assert annotation.project_id == project.id
      assert annotation.relative_path == ".claude/skills/product/SKILL.md"
      assert annotation.line_start == 3
      assert annotation.line_end == 3

      [ref] = Ash.read!(AnnotationFileRef)
      assert ref.annotation_id == annotation.id
      assert ref.relative_path == ".claude/skills/product/SKILL.md"
      assert ref.project_id == project.id
      assert ref.line_start == 3
      assert ref.line_end == 3
    end
  end

  describe "delete_annotation" do
    test "removes annotation from list", %{project: project, session: session} do
      annotation =
        Ash.create!(Annotation, %{
          source: :file,
          relative_path: ".claude/skills/product/SKILL.md",
          line_start: 1,
          line_end: 2,
          selected_text: "Product Skill",
          session_id: session.id,
          comment: "to delete",
          purpose: :review,
          project_id: project.id
        })

      Ash.create!(AnnotationFileRef, %{
        annotation_id: annotation.id,
        relative_path: ".claude/skills/product/SKILL.md",
        line_start: 1,
        line_end: 2,
        project_id: project.id
      })

      {:ok, view, html} =
        live(
          build_conn(),
          "/projects/#{project.id}/folders/.claude/skills/product"
        )

      assert html =~ "to delete"

      html = render_click(view, "delete_annotation", %{"id" => annotation.id})

      refute html =~ "to delete"
      assert Ash.read!(Annotation) == []
    end
  end

  describe "annotations sidebar" do
    test "existing annotations for folder files are shown on mount", %{
      project: project,
      session: session
    } do
      annotation =
        Ash.create!(Annotation, %{
          source: :file,
          relative_path: ".claude/skills/product/SKILL.md",
          line_start: 1,
          line_end: 1,
          selected_text: "Product Skill",
          session_id: session.id,
          comment: "existing sidebar note",
          purpose: :review,
          project_id: project.id
        })

      Ash.create!(AnnotationFileRef, %{
        annotation_id: annotation.id,
        relative_path: ".claude/skills/product/SKILL.md",
        line_start: 1,
        line_end: 1,
        project_id: project.id
      })

      {:ok, _view, html} =
        live(
          build_conn(),
          "/projects/#{project.id}/folders/.claude/skills/product"
        )

      assert html =~ "existing sidebar note"
      assert html =~ "Annotations (1)"
    end

    test "annotations count updates after saving", %{project: project} do
      {:ok, view, html} =
        live(
          build_conn(),
          "/projects/#{project.id}/folders/.claude/skills/product"
        )

      assert html =~ "Annotations (0)"

      render_hook(view, "folder_text_selected", %{
        "file_path" => ".claude/skills/product/SKILL.md",
        "selected_text" => "some text",
        "line_start" => 1,
        "line_end" => 1
      })

      html =
        render_click(view, "save_annotation", %{
          "comment" => "new note",
          "purpose" => "review"
        })

      assert html =~ "Annotations (1)"
    end
  end

  describe "clear_selection" do
    test "hides annotation form", %{project: project} do
      {:ok, view, _html} =
        live(
          build_conn(),
          "/projects/#{project.id}/folders/.claude/skills/product"
        )

      render_hook(view, "folder_text_selected", %{
        "file_path" => ".claude/skills/product/SKILL.md",
        "selected_text" => "some text",
        "line_start" => 1,
        "line_end" => 1
      })

      html = render_click(view, "clear_selection", %{})

      refute html =~ "annotation-form" or html =~ "annotation_editor"
    end
  end
end
