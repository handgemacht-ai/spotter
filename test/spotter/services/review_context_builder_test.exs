defmodule Spotter.Services.ReviewContextBuilderTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.ReviewContextBuilder
  alias Spotter.Transcripts.{Annotation, AnnotationMessageRef, Message, Project, Session}

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project_with_session do
    project =
      Ash.create!(Project, %{
        name: "ctx-test-#{System.unique_integer([:positive])}",
        pattern: "^test"
      })

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    {project, session}
  end

  test "builds context with open annotations" do
    {project, session} = create_project_with_session()

    Ash.create!(Annotation, %{
      session_id: session.id,
      source: :terminal,
      selected_text: "code to review",
      comment: "needs attention"
    })

    {:ok, context} = ReviewContextBuilder.build(project.id)

    assert context =~ "Project Review: #{project.name}"
    assert context =~ "1 open annotations"
    assert context =~ "[terminal]"
    assert context =~ "code to review"
    assert context =~ "needs attention"
  end

  test "builds context with transcript annotation and message refs" do
    {project, session} = create_project_with_session()

    msg =
      Ash.create!(Message, %{
        uuid: "msg-ref-1",
        type: :user,
        role: :user,
        timestamp: DateTime.utc_now(),
        session_id: session.id,
        content: %{"text" => "hello"}
      })

    ann =
      Ash.create!(Annotation, %{
        session_id: session.id,
        source: :transcript,
        selected_text: "transcript snippet",
        comment: "look here"
      })

    Ash.create!(AnnotationMessageRef, %{
      annotation_id: ann.id,
      message_id: msg.id,
      ordinal: 0
    })

    {:ok, context} = ReviewContextBuilder.build(project.id)

    assert context =~ "[transcript]"
    assert context =~ "Messages: msg-ref-1"
  end

  test "builds minimal context with no annotations" do
    {project, _session} = create_project_with_session()

    {:ok, context} = ReviewContextBuilder.build(project.id)

    assert context =~ "Project Review: #{project.name}"
    assert context =~ "No open annotations"
  end

  test "excludes closed annotations" do
    {project, session} = create_project_with_session()

    ann =
      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "closed",
        comment: "done"
      })

    Ash.update!(ann, %{}, action: :close)

    Ash.create!(Annotation, %{
      session_id: session.id,
      selected_text: "still open",
      comment: "review me"
    })

    {:ok, context} = ReviewContextBuilder.build(project.id)

    assert context =~ "still open"
    refute context =~ "Text: closed"
  end

  test "truncates long selected text" do
    {project, session} = create_project_with_session()

    long_text = String.duplicate("x", 500)

    Ash.create!(Annotation, %{
      session_id: session.id,
      selected_text: long_text,
      comment: "too long"
    })

    {:ok, context} = ReviewContextBuilder.build(project.id)

    assert context =~ "..."
    refute context =~ long_text
  end

  test "returns error for invalid project id" do
    assert {:error, _} = ReviewContextBuilder.build(Ash.UUID.generate())
  end
end
