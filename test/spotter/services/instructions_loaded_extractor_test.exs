defmodule Spotter.Services.InstructionsLoadedExtractorTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Services.InstructionsLoadedExtractor
  alias Spotter.Transcripts.{InstructionsLoadedEvent, Project, Session}

  require Ash.Query

  setup do
    Sandbox.checkout(Spotter.Repo)

    project =
      Ash.create!(Project, %{name: "instructions-test", pattern: "^instructions-test$"})

    session_id = Ash.UUID.generate()

    Ash.create!(Session, %{
      session_id: session_id,
      project_id: project.id,
      cwd: "/home/user/instructions-test"
    })

    %{project: project, session_id: session_id}
  end

  test "extracts InstructionsLoaded event with metrics", %{
    project: project,
    session_id: session_id
  } do
    topic = "instructions_telemetry:project:#{project.id}"
    Phoenix.PubSub.subscribe(Spotter.PubSub, topic)

    payload = %{
      "hook_event_name" => "InstructionsLoaded",
      "session_id" => session_id,
      "file_path" => "/home/user/.claude/CLAUDE.md",
      "memory_type" => "project",
      "load_reason" => "session_start",
      "spotter_instruction_metrics" => %{
        "bytes_loaded" => 1234,
        "lines_loaded" => 56,
        "size_status" => "ok"
      },
      "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert {:ok, _pid} = InstructionsLoadedExtractor.extract_and_persist(payload, "raw-evt-1")

    events = Ash.read!(InstructionsLoadedEvent)
    assert length(events) == 1

    event = hd(events)
    assert event.file_path == "/home/user/.claude/CLAUDE.md"
    assert event.bytes_loaded == 1234
    assert event.lines_loaded == 56
    assert event.size_status == "ok"
    assert event.memory_type == "project"

    expected_project_id = project.id
    assert_receive {:instructions_telemetry_updated, %{project_id: ^expected_project_id}}, 2_000
  end

  test "ignores non-InstructionsLoaded events" do
    payload = %{
      "hook_event_name" => "PostToolUse",
      "session_id" => "some-session",
      "file_path" => "/tmp/test"
    }

    assert {:ok, nil} = InstructionsLoadedExtractor.extract_and_persist(payload, "raw-evt-2")
    assert Ash.read!(InstructionsLoadedEvent) == []
  end

  test "ignores events without file_path" do
    payload = %{
      "hook_event_name" => "InstructionsLoaded",
      "session_id" => "some-session"
    }

    assert {:ok, nil} = InstructionsLoadedExtractor.extract_and_persist(payload, "raw-evt-3")
    assert Ash.read!(InstructionsLoadedEvent) == []
  end

  test "upserts duplicate events idempotently", %{session_id: session_id} do
    payload = %{
      "hook_event_name" => "InstructionsLoaded",
      "session_id" => session_id,
      "file_path" => "/home/user/.claude/CLAUDE.md",
      "spotter_instruction_metrics" => %{
        "bytes_loaded" => 100,
        "lines_loaded" => 10,
        "size_status" => "ok"
      }
    }

    {:ok, _} = InstructionsLoadedExtractor.extract_and_persist(payload, "raw-evt-dup")
    {:ok, _} = InstructionsLoadedExtractor.extract_and_persist(payload, "raw-evt-dup")

    events = Ash.read!(InstructionsLoadedEvent)
    assert length(events) == 1
  end
end
