defmodule Spotter.Transcripts.ResourcesTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Transcripts.{
    Annotation,
    AnnotationFileRef,
    AnnotationMessageRef,
    CoChangeGroup,
    CoChangeGroupCommit,
    CoChangeGroupMemberStat,
    Commit,
    CommitFile,
    FileHeatmap,
    Message,
    Project,
    Session,
    SessionCommitLink,
    SessionRework,
    SpecTestLink,
    Subagent
  }

  setup do
    Sandbox.checkout(Repo)
  end

  describe "Project" do
    test "creates and reads a project" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      assert project.name == "test"
      assert project.pattern == "^test"
      assert project.id != nil

      projects = Ash.read!(Project)
      assert length(projects) == 1
    end

    test "enforces unique name" do
      Ash.create!(Project, %{name: "test", pattern: "^test"})

      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(Project, %{name: "test", pattern: "^test2"})
      end
    end
  end

  describe "Session" do
    test "creates session with project" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      assert session.schema_version == 1
      assert session.transcript_dir == "test-dir"
    end

    test "creates session with resume metadata" do
      project = Ash.create!(Project, %{name: "test-meta", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id,
          custom_title: "My Session",
          summary: "Did some work",
          first_prompt: "Help me",
          source_created_at: ~U[2026-01-15 10:00:00Z],
          source_modified_at: ~U[2026-01-15 11:00:00Z]
        })

      assert session.custom_title == "My Session"
      assert session.summary == "Did some work"
      assert session.first_prompt == "Help me"
      assert session.source_created_at == ~U[2026-01-15 10:00:00.000000Z]
      assert session.source_modified_at == ~U[2026-01-15 11:00:00.000000Z]
    end

    test "updates session resume metadata" do
      project = Ash.create!(Project, %{name: "test-update", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      updated = Ash.update!(session, %{custom_title: "New Title", summary: "New Summary"})
      assert updated.custom_title == "New Title"
      assert updated.summary == "New Summary"
    end
  end

  describe "Message" do
    test "creates message with session" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      message =
        Ash.create!(Message, %{
          uuid: "msg-1",
          type: :user,
          role: :user,
          timestamp: DateTime.utc_now(),
          session_id: session.id,
          content: %{"text" => "hello"},
          raw_payload: %{"type" => "user", "message" => %{"content" => "hello"}}
        })

      assert message.type == :user
      assert message.content == %{"text" => "hello"}
      assert message.raw_payload["type"] == "user"
    end
  end

  describe "Subagent" do
    test "creates subagent with session" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      subagent =
        Ash.create!(Subagent, %{
          agent_id: "abc123",
          session_id: session.id,
          subagent_type: "general-purpose"
        })

      assert subagent.agent_id == "abc123"
      assert subagent.subagent_type == "general-purpose"
    end
  end

  describe "Commit" do
    test "creates and reads a commit" do
      commit = Ash.create!(Commit, %{commit_hash: "a" |> String.duplicate(40)})

      assert commit.commit_hash == String.duplicate("a", 40)
      assert commit.parent_hashes == []
      assert commit.changed_files == []
    end

    test "enforces unique commit_hash" do
      hash = String.duplicate("b", 40)
      Ash.create!(Commit, %{commit_hash: hash})

      # upsert returns existing record
      commit2 = Ash.create!(Commit, %{commit_hash: hash})
      assert commit2.commit_hash == hash
    end
  end

  describe "SessionCommitLink" do
    setup do
      project = Ash.create!(Project, %{name: "test-link", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      commit = Ash.create!(Commit, %{commit_hash: String.duplicate("c", 40)})

      %{session: session, commit: commit}
    end

    test "creates link with confidence", %{session: session, commit: commit} do
      link =
        Ash.create!(SessionCommitLink, %{
          session_id: session.id,
          commit_id: commit.id,
          link_type: :observed_in_session,
          confidence: 1.0,
          evidence: %{"source" => "hook-minimal"}
        })

      assert link.link_type == :observed_in_session
      assert link.confidence == 1.0
    end

    test "enforces unique session+commit+link_type", %{session: session, commit: commit} do
      attrs = %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      }

      Ash.create!(SessionCommitLink, attrs)

      # upsert updates confidence/evidence
      link2 = Ash.create!(SessionCommitLink, Map.put(attrs, :confidence, 0.8))
      assert link2.confidence == 0.8
    end

    test "allows different link_types for same session+commit", %{
      session: session,
      commit: commit
    } do
      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      link2 =
        Ash.create!(SessionCommitLink, %{
          session_id: session.id,
          commit_id: commit.id,
          link_type: :patch_match,
          confidence: 0.7
        })

      assert link2.link_type == :patch_match
    end
  end

  describe "FileHeatmap" do
    setup do
      project = Ash.create!(Project, %{name: "test-heatmap", pattern: "^test"})
      %{project: project}
    end

    test "creates a file heatmap entry", %{project: project} do
      heatmap =
        Ash.create!(FileHeatmap, %{
          project_id: project.id,
          relative_path: "lib/foo.ex",
          change_count_30d: 5,
          heat_score: 42.5,
          last_changed_at: ~U[2026-02-10 12:00:00Z]
        })

      assert heatmap.relative_path == "lib/foo.ex"
      assert heatmap.change_count_30d == 5
      assert heatmap.heat_score == 42.5
    end

    test "upserts by project + relative_path identity", %{project: project} do
      attrs = %{
        project_id: project.id,
        relative_path: "lib/bar.ex",
        change_count_30d: 3,
        heat_score: 20.0
      }

      first = Ash.create!(FileHeatmap, attrs)
      second = Ash.create!(FileHeatmap, %{attrs | change_count_30d: 7, heat_score: 55.0})

      assert first.id == second.id
      assert second.change_count_30d == 7
      assert second.heat_score == 55.0
    end

    test "rejects heat_score outside 0.0-100.0 range", %{project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(FileHeatmap, %{
          project_id: project.id,
          relative_path: "lib/bad.ex",
          heat_score: 101.0
        })
      end

      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(FileHeatmap, %{
          project_id: project.id,
          relative_path: "lib/bad.ex",
          heat_score: -1.0
        })
      end
    end
  end

  describe "SessionRework" do
    setup do
      project = Ash.create!(Project, %{name: "test-rework", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      %{session: session}
    end

    test "creates a session rework record", %{session: session} do
      rework =
        Ash.create!(SessionRework, %{
          tool_use_id: "tu-002",
          file_path: "/home/user/project/lib/foo.ex",
          relative_path: "lib/foo.ex",
          occurrence_index: 2,
          first_tool_use_id: "tu-001",
          event_timestamp: ~U[2026-02-12 10:00:00Z],
          session_id: session.id
        })

      assert rework.tool_use_id == "tu-002"
      assert rework.file_path == "/home/user/project/lib/foo.ex"
      assert rework.relative_path == "lib/foo.ex"
      assert rework.occurrence_index == 2
      assert rework.first_tool_use_id == "tu-001"
      assert rework.detection_source == :transcript_sync
    end

    test "upsert is idempotent for same session_id + tool_use_id", %{session: session} do
      attrs = %{
        tool_use_id: "tu-003",
        file_path: "/home/user/project/lib/bar.ex",
        occurrence_index: 2,
        first_tool_use_id: "tu-001",
        session_id: session.id
      }

      first = Ash.create!(SessionRework, attrs, action: :upsert)

      second =
        Ash.create!(SessionRework, %{attrs | occurrence_index: 3, file_path: "/updated/path.ex"},
          action: :upsert
        )

      assert first.id == second.id
      assert second.occurrence_index == 3
      assert second.file_path == "/updated/path.ex"
    end

    test "allows relative_path to be nil", %{session: session} do
      rework =
        Ash.create!(SessionRework, %{
          tool_use_id: "tu-004",
          file_path: "/absolute/only/path.ex",
          occurrence_index: 2,
          first_tool_use_id: "tu-001",
          session_id: session.id
        })

      assert rework.relative_path == nil
    end

    test "is queryable via Ash read", %{session: session} do
      Ash.create!(SessionRework, %{
        tool_use_id: "tu-005",
        file_path: "lib/a.ex",
        occurrence_index: 2,
        first_tool_use_id: "tu-001",
        session_id: session.id
      })

      Ash.create!(SessionRework, %{
        tool_use_id: "tu-006",
        file_path: "lib/a.ex",
        occurrence_index: 3,
        first_tool_use_id: "tu-001",
        session_id: session.id
      })

      reworks = Ash.read!(SessionRework)
      assert length(reworks) == 2
    end
  end

  describe "CoChangeGroup" do
    setup do
      project = Ash.create!(Project, %{name: "test-cochange", pattern: "^test"})
      %{project: project}
    end

    test "creates a co-change group", %{project: project} do
      group =
        Ash.create!(CoChangeGroup, %{
          project_id: project.id,
          scope: :file,
          group_key: "lib/a.ex|lib/b.ex",
          members: ["lib/a.ex", "lib/b.ex"],
          frequency_30d: 5,
          last_seen_at: ~U[2026-02-10 12:00:00Z]
        })

      assert group.scope == :file
      assert group.group_key == "lib/a.ex|lib/b.ex"
      assert group.members == ["lib/a.ex", "lib/b.ex"]
      assert group.frequency_30d == 5
    end

    test "upserts by project + scope + group_key identity", %{project: project} do
      attrs = %{
        project_id: project.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency_30d: 3
      }

      first = Ash.create!(CoChangeGroup, attrs)
      second = Ash.create!(CoChangeGroup, %{attrs | frequency_30d: 7})

      assert first.id == second.id
      assert second.frequency_30d == 7
    end

    test "rejects invalid scope", %{project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(CoChangeGroup, %{
          project_id: project.id,
          scope: :invalid,
          group_key: "lib/a.ex|lib/b.ex",
          members: ["lib/a.ex", "lib/b.ex"],
          frequency_30d: 1
        })
      end
    end

    test "allows directory scope", %{project: project} do
      group =
        Ash.create!(CoChangeGroup, %{
          project_id: project.id,
          scope: :directory,
          group_key: "lib|test",
          members: ["lib", "test"],
          frequency_30d: 10
        })

      assert group.scope == :directory
    end

    test "same group_key with different scopes creates separate records", %{project: project} do
      file_group =
        Ash.create!(CoChangeGroup, %{
          project_id: project.id,
          scope: :file,
          group_key: "lib/a.ex|lib/b.ex",
          members: ["lib/a.ex", "lib/b.ex"],
          frequency_30d: 3
        })

      dir_group =
        Ash.create!(CoChangeGroup, %{
          project_id: project.id,
          scope: :directory,
          group_key: "lib/a.ex|lib/b.ex",
          members: ["lib/a.ex", "lib/b.ex"],
          frequency_30d: 5
        })

      assert file_group.id != dir_group.id
    end
  end

  describe "CoChangeGroupCommit" do
    setup do
      project = Ash.create!(Project, %{name: "test-gcc", pattern: "^test"})
      %{project: project}
    end

    test "creates a co-change group commit", %{project: project} do
      gcc =
        Ash.create!(CoChangeGroupCommit, %{
          project_id: project.id,
          scope: :file,
          group_key: "lib/a.ex|lib/b.ex",
          commit_hash: String.duplicate("a", 40),
          committed_at: ~U[2026-02-10 12:00:00Z]
        })

      assert gcc.scope == :file
      assert gcc.group_key == "lib/a.ex|lib/b.ex"
      assert gcc.commit_hash == String.duplicate("a", 40)
    end

    test "upserts by project + scope + group_key + commit_hash", %{project: project} do
      attrs = %{
        project_id: project.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex",
        commit_hash: String.duplicate("b", 40),
        committed_at: ~U[2026-02-10 12:00:00Z]
      }

      first = Ash.create!(CoChangeGroupCommit, attrs)
      second = Ash.create!(CoChangeGroupCommit, %{attrs | committed_at: ~U[2026-02-11 12:00:00Z]})

      assert first.id == second.id
      assert second.committed_at == ~U[2026-02-11 12:00:00.000000Z]
    end

    test "allows multiple commits for the same group", %{project: project} do
      base = %{
        project_id: project.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex"
      }

      gcc1 =
        Ash.create!(
          CoChangeGroupCommit,
          Map.merge(base, %{commit_hash: String.duplicate("c", 40)})
        )

      gcc2 =
        Ash.create!(
          CoChangeGroupCommit,
          Map.merge(base, %{commit_hash: String.duplicate("d", 40)})
        )

      assert gcc1.id != gcc2.id
    end

    test "rejects invalid scope", %{project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(CoChangeGroupCommit, %{
          project_id: project.id,
          scope: :invalid,
          group_key: "lib/a.ex|lib/b.ex",
          commit_hash: String.duplicate("e", 40)
        })
      end
    end
  end

  describe "CoChangeGroupMemberStat" do
    setup do
      project = Ash.create!(Project, %{name: "test-gcms", pattern: "^test"})
      %{project: project}
    end

    test "creates a member stat", %{project: project} do
      stat =
        Ash.create!(CoChangeGroupMemberStat, %{
          project_id: project.id,
          scope: :file,
          group_key: "lib/a.ex|lib/b.ex",
          member_path: "lib/a.ex",
          size_bytes: 1024,
          loc: 42,
          measured_commit_hash: String.duplicate("a", 40),
          measured_at: ~U[2026-02-10 12:00:00Z]
        })

      assert stat.member_path == "lib/a.ex"
      assert stat.size_bytes == 1024
      assert stat.loc == 42
    end

    test "upserts by project + scope + group_key + member_path", %{project: project} do
      attrs = %{
        project_id: project.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex",
        member_path: "lib/a.ex",
        size_bytes: 1024,
        loc: 42,
        measured_commit_hash: String.duplicate("b", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      }

      first = Ash.create!(CoChangeGroupMemberStat, attrs)
      second = Ash.create!(CoChangeGroupMemberStat, %{attrs | size_bytes: 2048, loc: 80})

      assert first.id == second.id
      assert second.size_bytes == 2048
      assert second.loc == 80
    end

    test "allows nil metrics", %{project: project} do
      stat =
        Ash.create!(CoChangeGroupMemberStat, %{
          project_id: project.id,
          scope: :file,
          group_key: "lib/a.ex|lib/b.ex",
          member_path: "lib/a.ex"
        })

      assert stat.size_bytes == nil
      assert stat.loc == nil
      assert stat.measured_commit_hash == nil
    end

    test "allows multiple members for the same group", %{project: project} do
      base = %{
        project_id: project.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex"
      }

      s1 =
        Ash.create!(
          CoChangeGroupMemberStat,
          Map.merge(base, %{member_path: "lib/a.ex", size_bytes: 100})
        )

      s2 =
        Ash.create!(
          CoChangeGroupMemberStat,
          Map.merge(base, %{member_path: "lib/b.ex", size_bytes: 200})
        )

      assert s1.id != s2.id
    end
  end

  describe "Annotation" do
    setup do
      project = Ash.create!(Project, %{name: "test-ann", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      %{session: session}
    end

    test "creates terminal annotation with coordinates", %{session: session} do
      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :terminal,
          selected_text: "hello world",
          start_row: 1,
          start_col: 0,
          end_row: 1,
          end_col: 11,
          comment: "interesting"
        })

      assert ann.source == :terminal
      assert ann.start_row == 1
    end

    test "creates transcript annotation with nil coordinates", %{session: session} do
      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "some transcript text",
          comment: "noted"
        })

      assert ann.source == :transcript
      assert ann.start_row == nil
      assert ann.end_col == nil
    end

    test "defaults source to terminal", %{session: session} do
      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          selected_text: "text",
          start_row: 0,
          start_col: 0,
          end_row: 0,
          end_col: 4,
          comment: "default source"
        })

      assert ann.source == :terminal
    end

    test "defaults state to open", %{session: session} do
      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          selected_text: "text",
          comment: "open by default"
        })

      assert ann.state == :open
    end

    test "close action transitions state to closed", %{session: session} do
      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          selected_text: "text",
          comment: "will be closed"
        })

      assert ann.state == :open

      closed = Ash.update!(ann, %{}, action: :close)
      assert closed.state == :closed
    end

    test "closing an already-closed annotation is idempotent", %{session: session} do
      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          selected_text: "text",
          comment: "close twice"
        })

      closed = Ash.update!(ann, %{}, action: :close)
      assert closed.state == :closed

      closed_again = Ash.update!(closed, %{}, action: :close)
      assert closed_again.state == :closed
    end
  end

  describe "AnnotationMessageRef" do
    setup do
      project = Ash.create!(Project, %{name: "test-ref", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      msg1 =
        Ash.create!(Message, %{
          uuid: "msg-1",
          type: :user,
          role: :user,
          timestamp: DateTime.utc_now(),
          session_id: session.id,
          content: %{"text" => "hello"}
        })

      msg2 =
        Ash.create!(Message, %{
          uuid: "msg-2",
          type: :assistant,
          role: :assistant,
          timestamp: DateTime.utc_now(),
          session_id: session.id,
          content: %{"text" => "world"}
        })

      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "hello world",
          comment: "test refs"
        })

      %{session: session, annotation: ann, msg1: msg1, msg2: msg2}
    end

    test "creates refs with ordinal ordering", %{annotation: ann, msg1: msg1, msg2: msg2} do
      ref1 =
        Ash.create!(AnnotationMessageRef, %{
          annotation_id: ann.id,
          message_id: msg1.id,
          ordinal: 0
        })

      ref2 =
        Ash.create!(AnnotationMessageRef, %{
          annotation_id: ann.id,
          message_id: msg2.id,
          ordinal: 1
        })

      assert ref1.ordinal == 0
      assert ref2.ordinal == 1

      loaded = Ash.load!(ann, message_refs: :message)
      refs = Enum.sort_by(loaded.message_refs, & &1.ordinal)
      assert length(refs) == 2
      assert Enum.at(refs, 0).message.uuid == "msg-1"
      assert Enum.at(refs, 1).message.uuid == "msg-2"
    end

    test "enforces unique annotation+message", %{annotation: ann, msg1: msg1} do
      Ash.create!(AnnotationMessageRef, %{
        annotation_id: ann.id,
        message_id: msg1.id,
        ordinal: 0
      })

      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(AnnotationMessageRef, %{
          annotation_id: ann.id,
          message_id: msg1.id,
          ordinal: 1
        })
      end
    end
  end

  describe "CommitFile" do
    test "creates a commit file entry" do
      commit = Ash.create!(Commit, %{commit_hash: String.duplicate("f", 40)})

      cf =
        Ash.create!(CommitFile, %{
          commit_id: commit.id,
          relative_path: "lib/foo.ex",
          change_type: :added
        })

      assert cf.relative_path == "lib/foo.ex"
      assert cf.change_type == :added
    end

    test "upserts by commit + relative_path identity" do
      commit = Ash.create!(Commit, %{commit_hash: String.duplicate("g", 40)})

      first =
        Ash.create!(CommitFile, %{
          commit_id: commit.id,
          relative_path: "lib/bar.ex",
          change_type: :added
        })

      second =
        Ash.create!(CommitFile, %{
          commit_id: commit.id,
          relative_path: "lib/bar.ex",
          change_type: :modified
        })

      assert first.id == second.id
      assert second.change_type == :modified
    end

    test "allows multiple files per commit" do
      commit = Ash.create!(Commit, %{commit_hash: String.duplicate("h", 40)})

      cf1 = Ash.create!(CommitFile, %{commit_id: commit.id, relative_path: "lib/a.ex"})
      cf2 = Ash.create!(CommitFile, %{commit_id: commit.id, relative_path: "lib/b.ex"})

      assert cf1.id != cf2.id
    end
  end

  describe "AnnotationFileRef" do
    setup do
      project = Ash.create!(Project, %{name: "test-fileref", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :file,
          selected_text: "def foo",
          comment: "check this function"
        })

      %{project: project, session: session, annotation: ann}
    end

    test "creates file annotation with line range", %{annotation: ann, project: project} do
      ref =
        Ash.create!(AnnotationFileRef, %{
          annotation_id: ann.id,
          project_id: project.id,
          relative_path: "lib/foo.ex",
          line_start: 10,
          line_end: 15
        })

      assert ref.relative_path == "lib/foo.ex"
      assert ref.line_start == 10
      assert ref.line_end == 15
    end

    test "rejects line_end < line_start", %{annotation: ann, project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(AnnotationFileRef, %{
          annotation_id: ann.id,
          project_id: project.id,
          relative_path: "lib/foo.ex",
          line_start: 20,
          line_end: 10
        })
      end
    end

    test "rejects non-positive line numbers", %{annotation: ann, project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(AnnotationFileRef, %{
          annotation_id: ann.id,
          project_id: project.id,
          relative_path: "lib/foo.ex",
          line_start: 0,
          line_end: 5
        })
      end
    end

    test "annotation with source :file is loadable with file_refs", %{
      annotation: ann,
      project: project
    } do
      Ash.create!(AnnotationFileRef, %{
        annotation_id: ann.id,
        project_id: project.id,
        relative_path: "lib/foo.ex",
        line_start: 1,
        line_end: 5
      })

      loaded = Ash.load!(ann, :file_refs)
      assert length(loaded.file_refs) == 1
      assert hd(loaded.file_refs).relative_path == "lib/foo.ex"
    end
  end

  describe "SpecTestLink" do
    setup do
      project = Ash.create!(Project, %{name: "test-stl", pattern: "^test"})
      %{project: project}
    end

    test "creates a spec-test link", %{project: project} do
      link =
        Ash.create!(SpecTestLink, %{
          project_id: project.id,
          commit_hash: String.duplicate("a", 40),
          requirement_spec_key: "REQ-001",
          test_key: "test/foo_test.exs::describes Foo::handles edge case"
        })

      assert link.requirement_spec_key == "REQ-001"
      assert link.test_key == "test/foo_test.exs::describes Foo::handles edge case"
      assert link.confidence == 1.0
      assert link.source == :agent
      assert link.metadata == %{}
    end

    test "upserts by project + commit_hash + requirement_spec_key + test_key", %{
      project: project
    } do
      attrs = %{
        project_id: project.id,
        commit_hash: String.duplicate("b", 40),
        requirement_spec_key: "REQ-002",
        test_key: "test/bar_test.exs::test bar"
      }

      first = Ash.create!(SpecTestLink, attrs)
      second = Ash.create!(SpecTestLink, Map.merge(attrs, %{confidence: 0.8, source: :inferred}))

      assert first.id == second.id
      assert second.confidence == 0.8
      assert second.source == :inferred
    end

    test "allows different test_keys for the same requirement", %{project: project} do
      base = %{
        project_id: project.id,
        commit_hash: String.duplicate("c", 40),
        requirement_spec_key: "REQ-003"
      }

      l1 = Ash.create!(SpecTestLink, Map.put(base, :test_key, "test/a_test.exs::test a"))
      l2 = Ash.create!(SpecTestLink, Map.put(base, :test_key, "test/b_test.exs::test b"))

      assert l1.id != l2.id
    end

    test "rejects confidence outside 0.0-1.0 range", %{project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(SpecTestLink, %{
          project_id: project.id,
          commit_hash: String.duplicate("d", 40),
          requirement_spec_key: "REQ-004",
          test_key: "test/d_test.exs::test d",
          confidence: 1.5
        })
      end

      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(SpecTestLink, %{
          project_id: project.id,
          commit_hash: String.duplicate("d", 40),
          requirement_spec_key: "REQ-004",
          test_key: "test/d_test.exs::test d",
          confidence: -0.1
        })
      end
    end

    test "rejects invalid source", %{project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(SpecTestLink, %{
          project_id: project.id,
          commit_hash: String.duplicate("e", 40),
          requirement_spec_key: "REQ-005",
          test_key: "test/e_test.exs::test e",
          source: :unknown
        })
      end
    end

    test "stores custom metadata", %{project: project} do
      link =
        Ash.create!(SpecTestLink, %{
          project_id: project.id,
          commit_hash: String.duplicate("f", 40),
          requirement_spec_key: "REQ-006",
          test_key: "test/f_test.exs::test f",
          metadata: %{"reason" => "exact match on spec text"}
        })

      assert link.metadata == %{"reason" => "exact match on spec text"}
    end
  end

  describe "Annotation with :file source" do
    setup do
      project = Ash.create!(Project, %{name: "test-file-ann", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      %{session: session, project: project}
    end

    test "creates annotation with source :file", %{session: session} do
      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :file,
          selected_text: "some code",
          comment: "review this"
        })

      assert ann.source == :file
    end

    test "creates file annotation without session_id", %{project: project} do
      ann =
        Ash.create!(Annotation, %{
          source: :file,
          selected_text: "def foo(bar)",
          comment: "needs refactoring",
          project_id: project.id
        })

      assert ann.source == :file
      assert ann.session_id == nil
      assert ann.project_id == project.id
    end

    test "rejects terminal annotation without session_id" do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(Annotation, %{
          source: :terminal,
          selected_text: "some text",
          comment: "missing session"
        })
      end
    end

    test "rejects transcript annotation without session_id" do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(Annotation, %{
          source: :transcript,
          selected_text: "some text",
          comment: "missing session"
        })
      end
    end

    test "session-bound file annotation still works", %{session: session} do
      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :file,
          selected_text: "bound to session",
          comment: "has session"
        })

      assert ann.session_id == session.id
      assert ann.source == :file
    end
  end
end
