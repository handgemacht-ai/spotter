defmodule Spotter.Test.FakeClaudeStreamingError do
  @moduledoc false

  def start_session(_opts), do: {:ok, :fake_session}

  def send_message(_session, _message) do
    raise "simulated streaming failure"
  end

  def close_session(_session), do: :ok
end

defmodule Spotter.Transcripts.Jobs.ExplainAnnotationFlowTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Observability.FlowHub
  alias Spotter.Transcripts.{Annotation, Project, Session}
  alias Spotter.Transcripts.Jobs.ExplainAnnotation

  setup do
    Sandbox.checkout(Spotter.Repo)

    original_mod = Application.get_env(:spotter, :claude_streaming_module)
    Application.put_env(:spotter, :claude_streaming_module, Spotter.Test.FakeClaudeStreaming)

    on_exit(fn ->
      if original_mod do
        Application.put_env(:spotter, :claude_streaming_module, original_mod)
      else
        Application.delete_env(:spotter, :claude_streaming_module)
      end
    end)

    if :ets.whereis(FlowHub) != :undefined do
      :ets.delete_all_objects(FlowHub)
    end

    project =
      Ash.create!(Project, %{name: "test-explain-flow", pattern: "^test"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    annotation =
      Ash.create!(Annotation, %{
        session_id: session.id,
        project_id: project.id,
        purpose: :explain,
        selected_text: "x = 1",
        comment: "why does this work?"
      })

    %{session: session, annotation: annotation}
  end

  test "emits agent_run FlowHub events linked to session and oban", %{
    session: session,
    annotation: annotation
  } do
    job = %Oban.Job{id: 123, args: %{"annotation_id" => annotation.id}}

    assert :ok == ExplainAnnotation.perform(job)

    %{events: events} = FlowHub.snapshot(minutes: 5)

    # Verify agent.run.start event
    start_event = Enum.find(events, &(&1.kind == "agent.run.start"))
    assert start_event != nil
    assert "oban:123" in start_event.flow_keys
    assert "session:#{session.session_id}" in start_event.flow_keys
    assert Enum.any?(start_event.flow_keys, &String.starts_with?(&1, "agent_run:explain-"))

    # Verify at least one agent.output.delta event
    delta_events = Enum.filter(events, &(&1.kind == "agent.output.delta"))
    assert delta_events != []
    assert hd(delta_events).payload["text"] == "Hello"

    # Verify agent.run.stop event
    stop_event = Enum.find(events, &(&1.kind == "agent.run.stop"))
    assert stop_event != nil
    assert stop_event.status == :ok
  end

  test "emits structured error payload on streaming failure", %{
    annotation: annotation
  } do
    # Switch to error-producing fake
    Application.put_env(
      :spotter,
      :claude_streaming_module,
      Spotter.Test.FakeClaudeStreamingError
    )

    Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

    job = %Oban.Job{id: 456, args: %{"annotation_id" => annotation.id}}

    assert {:error, _reason} = ExplainAnnotation.perform(job)

    %{events: events} = FlowHub.snapshot(minutes: 5)

    stop_event =
      Enum.find(events, fn e -> e.kind == "agent.run.stop" and e.status == :error end)

    assert stop_event != nil
    assert stop_event.payload["error.type"] == "annotation_explain_failed"
    assert is_binary(stop_event.payload["error.message"])
    assert stop_event.payload["error.message"] != ""
    assert stop_event.payload["error.source"] == "transcripts.jobs.explain_annotation"
    assert is_binary(stop_event.payload["run_id"])

    # Verify start event still emitted normally
    start_event = Enum.find(events, &(&1.kind == "agent.run.start"))
    assert start_event != nil
    assert start_event.status == :running
  end
end
