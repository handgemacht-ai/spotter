defmodule Spotter.Services.SubagentLifecycleIngestorTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Services.SubagentLifecycleIngestor
  alias Spotter.Transcripts.{Project, RawHookEvent, Session, Subagent}

  require Ash.Query

  setup do
    Sandbox.checkout(Spotter.Repo)

    project = Ash.create!(Project, %{name: "lifecycle-test", pattern: "^lifecycle-test$"})
    session_id = Ash.UUID.generate()

    session =
      Ash.create!(Session, %{
        session_id: session_id,
        project_id: project.id,
        cwd: "/home/user/lifecycle-test"
      })

    %{project: project, session: session, session_id: session_id}
  end

  defp make_event(captured_at) do
    %RawHookEvent{
      id: Ash.UUID.generate(),
      captured_at: captured_at
    }
  end

  describe "SubagentStart" do
    test "creates subagent with type and started_at", %{session_id: session_id} do
      now = DateTime.utc_now()

      payload = %{
        "hook_event_name" => "SubagentStart",
        "session_id" => session_id,
        "agent_id" => "agent-abc",
        "agent_type" => "research"
      }

      assert {:ok, %{status: :created}} =
               SubagentLifecycleIngestor.ingest(payload, make_event(now))

      [subagent] = Ash.read!(Subagent)
      assert subagent.agent_id == "agent-abc"
      assert subagent.subagent_type == "research"
      assert subagent.started_at == now
    end

    test "duplicate SubagentStart remains single row", %{session_id: session_id} do
      now = DateTime.utc_now()
      later = DateTime.add(now, 5, :second)

      payload = %{
        "hook_event_name" => "SubagentStart",
        "session_id" => session_id,
        "agent_id" => "agent-dup",
        "agent_type" => "research"
      }

      assert {:ok, %{status: :created}} =
               SubagentLifecycleIngestor.ingest(payload, make_event(now))

      assert {:ok, %{status: :updated}} =
               SubagentLifecycleIngestor.ingest(payload, make_event(later))

      subagents = Ash.read!(Subagent)
      assert length(subagents) == 1
      # started_at keeps earliest
      assert hd(subagents).started_at == now
    end
  end

  describe "SubagentStop" do
    test "sets ended_at and does not clear existing type", %{session_id: session_id} do
      start_time = DateTime.utc_now()
      stop_time = DateTime.add(start_time, 10, :second)

      start_payload = %{
        "hook_event_name" => "SubagentStart",
        "session_id" => session_id,
        "agent_id" => "agent-stop-test",
        "agent_type" => "code-explorer"
      }

      stop_payload = %{
        "hook_event_name" => "SubagentStop",
        "session_id" => session_id,
        "agent_id" => "agent-stop-test"
      }

      {:ok, _} = SubagentLifecycleIngestor.ingest(start_payload, make_event(start_time))
      {:ok, _} = SubagentLifecycleIngestor.ingest(stop_payload, make_event(stop_time))

      [subagent] = Ash.read!(Subagent)
      assert subagent.subagent_type == "code-explorer"
      assert subagent.ended_at == stop_time
      assert subagent.started_at == start_time
    end
  end

  describe "ignored events" do
    test "non-lifecycle event returns ignored", %{session_id: session_id} do
      payload = %{
        "hook_event_name" => "PostToolUse",
        "session_id" => session_id,
        "agent_id" => "agent-x"
      }

      assert {:ok, %{status: :ignored}} =
               SubagentLifecycleIngestor.ingest(payload, make_event(DateTime.utc_now()))

      assert Ash.read!(Subagent) == []
    end

    test "missing agent_id returns ignored", %{session_id: session_id} do
      payload = %{
        "hook_event_name" => "SubagentStart",
        "session_id" => session_id
      }

      assert {:ok, %{status: :ignored}} =
               SubagentLifecycleIngestor.ingest(payload, make_event(DateTime.utc_now()))
    end
  end
end
