defmodule Spotter.Services.FileDetailTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.FileDetail

  alias Spotter.Services.GitRunner

  alias Spotter.Transcripts.{
    Annotation,
    AnnotationFileRef,
    Commit,
    CommitFile,
    Project,
    Session,
    SessionCommitLink
  }

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project_session_commit do
    project =
      Ash.create!(Project, %{
        name: "file-detail-test-#{System.unique_integer([:positive])}",
        pattern: "^test"
      })

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        cwd: "/tmp/test-project",
        project_id: project.id
      })

    commit =
      Ash.create!(Commit, %{
        commit_hash: String.duplicate("b", 40),
        subject: "feat: add file detail",
        changed_files: ["lib/foo.ex", "lib/bar.ex"]
      })

    Ash.create!(CommitFile, %{
      commit_id: commit.id,
      relative_path: "lib/foo.ex",
      change_type: :modified
    })

    Ash.create!(CommitFile, %{
      commit_id: commit.id,
      relative_path: "lib/bar.ex",
      change_type: :added
    })

    Ash.create!(SessionCommitLink, %{
      session_id: session.id,
      commit_id: commit.id,
      link_type: :observed_in_session,
      confidence: 1.0
    })

    {project, session, commit}
  end

  test "load_project returns project by id" do
    {project, _session, _commit} = create_project_session_commit()

    assert {:ok, loaded} = FileDetail.load_project(project.id)
    assert loaded.id == project.id
  end

  test "load_project returns error for unknown id" do
    assert {:error, :not_found} = FileDetail.load_project(Ash.UUID.generate())
  end

  test "load_commits_for_file returns commits via CommitFile" do
    {_project, _session, commit} = create_project_session_commit()

    rows = FileDetail.load_commits_for_file("lib/foo.ex")

    assert rows != []
    assert Enum.any?(rows, fn r -> r.commit.id == commit.id and r.change_type == :modified end)
  end

  test "load_commits_for_file returns empty for unknown path" do
    assert FileDetail.load_commits_for_file("nonexistent/file.ex") == []
  end

  test "load_sessions_for_file returns linked sessions" do
    {_project, session, _commit} = create_project_session_commit()

    sessions = FileDetail.load_sessions_for_file("lib/foo.ex")

    assert sessions != []
    assert Enum.any?(sessions, &(&1.session.id == session.id))
  end

  test "load_sessions_for_file returns empty for unknown path" do
    assert FileDetail.load_sessions_for_file("nonexistent/file.ex") == []
  end

  test "load_file_annotations returns annotations for project/path" do
    {project, session, _commit} = create_project_session_commit()

    annotation =
      Ash.create!(Annotation, %{
        session_id: session.id,
        source: :file,
        selected_text: "defmodule Foo",
        comment: "Review this module"
      })

    Ash.create!(AnnotationFileRef, %{
      annotation_id: annotation.id,
      project_id: project.id,
      relative_path: "lib/foo.ex",
      line_start: 1,
      line_end: 5
    })

    annotations = FileDetail.load_file_annotations(project.id, "lib/foo.ex")

    assert length(annotations) == 1
    assert hd(annotations).id == annotation.id
  end

  test "load_file_annotations returns empty when no refs" do
    {project, _session, _commit} = create_project_session_commit()

    assert FileDetail.load_file_annotations(project.id, "lib/nonexistent.ex") == []
  end

  test "language_class detects elixir" do
    assert FileDetail.language_class("lib/foo.ex") == "elixir"
    assert FileDetail.language_class("test/bar_test.exs") == "elixir"
  end

  test "language_class detects common languages" do
    assert FileDetail.language_class("app.js") == "javascript"
    assert FileDetail.language_class("index.ts") == "typescript"
    assert FileDetail.language_class("main.py") == "python"
    assert FileDetail.language_class("style.css") == "css"
  end

  test "language_class falls back to extension" do
    assert FileDetail.language_class("file.zig") == "zig"
  end

  describe "list_directory/2 gitignore filtering" do
    setup do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "file_detail_gitignore_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)

      {:ok, _} = GitRunner.run(["init"], cd: tmp_dir)
      {:ok, _} = GitRunner.run(["config", "user.email", "test@test.com"], cd: tmp_dir)
      {:ok, _} = GitRunner.run(["config", "user.name", "Test"], cd: tmp_dir)

      # Write .gitignore first so ignored dirs stay untracked
      File.write!(Path.join(tmp_dir, ".gitignore"), "node_modules/\n_build/\ndeps/\n")

      # Create tracked files and dirs
      File.write!(Path.join(tmp_dir, "README.md"), "# Hello")
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.write!(Path.join(tmp_dir, "lib/app.ex"), "defmodule App, do: nil")

      # Create ignored dirs (untracked due to .gitignore)
      File.mkdir_p!(Path.join(tmp_dir, "node_modules/pkg"))
      File.write!(Path.join(tmp_dir, "node_modules/pkg/index.js"), "")
      File.mkdir_p!(Path.join(tmp_dir, "_build"))
      File.write!(Path.join(tmp_dir, "_build/out"), "")
      File.mkdir_p!(Path.join(tmp_dir, "deps"))

      # Initial commit with tracked files only
      {:ok, _} = GitRunner.run(["add", "."], cd: tmp_dir)
      {:ok, _} = GitRunner.run(["commit", "-m", "init"], cd: tmp_dir)

      project =
        Ash.create!(Project, %{
          name: "gitignore-test-#{System.unique_integer([:positive])}",
          pattern: "^test"
        })

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        cwd: tmp_dir,
        project_id: project.id
      })

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir, project: project}
    end

    test "filters gitignored directories from listing", %{project: project} do
      assert {:ok, entries} = FileDetail.list_directory(project.id, nil, filter_gitignored: true)
      names = Enum.map(entries, & &1.name)

      assert "lib" in names
      assert "README.md" in names
      assert ".gitignore" in names
      refute "node_modules" in names
      refute "_build" in names
      refute "deps" in names
    end

    test "shows all entries without filter_gitignored opt-in", %{project: project} do
      assert {:ok, entries} = FileDetail.list_directory(project.id, nil)
      names = Enum.map(entries, & &1.name)

      assert "lib" in names
      assert "node_modules" in names
      assert "_build" in names
      assert "deps" in names
    end
  end
end
