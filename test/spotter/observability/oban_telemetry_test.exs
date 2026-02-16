defmodule Spotter.Observability.ObanTelemetryTest do
  use ExUnit.Case, async: false

  alias Spotter.Observability.FlowEvent
  alias Spotter.Observability.FlowHub
  alias Spotter.Observability.ObanTelemetry

  setup do
    if :ets.whereis(FlowHub) != :undefined do
      :ets.delete_all_objects(FlowHub)
    end

    ObanTelemetry.setup()
    :ok
  end

  defp fake_job(overrides \\ %{}) do
    Map.merge(
      %{
        id: 42,
        worker: "Spotter.Workers.EnrichCommit",
        queue: :default,
        attempt: 1,
        args: %{"session_id" => "sess-1", "commit_hash" => "abc123"}
      },
      overrides
    )
  end

  describe "job start" do
    test "emits a running flow event" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      :telemetry.execute(
        [:oban, :job, :start],
        %{system_time: System.system_time()},
        %{job: fake_job(), conf: %{}}
      )

      assert_receive {:flow_event, %FlowEvent{kind: "oban.job.start", status: :running}}, 1000

      %{events: events} = FlowHub.snapshot()
      event = Enum.find(events, &(&1.kind == "oban.job.start"))
      assert event != nil
      assert "oban:42" in event.flow_keys
      assert "session:sess-1" in event.flow_keys
      assert "commit:abc123" in event.flow_keys
      assert event.payload["worker"] == "Spotter.Workers.EnrichCommit"
    end
  end

  describe "job stop" do
    test "emits ok status for success" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      :telemetry.execute(
        [:oban, :job, :stop],
        %{duration: 5_000_000, memory: 1024, queue_time: 100, reductions: 500},
        %{job: fake_job(), conf: %{}, state: :success, result: :ok}
      )

      assert_receive {:flow_event, %FlowEvent{kind: "oban.job.stop", status: :ok} = event}, 1000
      assert event.payload["state"] == "success"
      assert is_number(event.payload["duration_ms"])
    end

    test "emits error status for failure" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      :telemetry.execute(
        [:oban, :job, :stop],
        %{duration: 1_000_000, memory: 512, queue_time: 50, reductions: 200},
        %{job: fake_job(), conf: %{}, state: :failure, result: nil}
      )

      assert_receive {:flow_event, %FlowEvent{kind: "oban.job.stop", status: :error}}, 1000
    end

    test "emits ok status for cancelled/snoozed" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      :telemetry.execute(
        [:oban, :job, :stop],
        %{duration: 100_000, memory: 256, queue_time: 10, reductions: 50},
        %{job: fake_job(), conf: %{}, state: :cancelled, result: nil}
      )

      assert_receive {:flow_event, %FlowEvent{kind: "oban.job.stop", status: :ok}}, 1000
    end
  end

  describe "job exception" do
    test "emits error status with exception details" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 2_000_000, memory: 2048, queue_time: 200, reductions: 1000},
        %{
          job: fake_job(),
          conf: %{},
          state: :failure,
          kind: :error,
          reason: %RuntimeError{message: "something went wrong"},
          result: nil,
          stacktrace: []
        }
      )

      assert_receive {:flow_event,
                      %FlowEvent{kind: "oban.job.exception", status: :error} = event},
                     1000

      assert event.payload["kind"] == "error"
      assert event.payload["reason"] =~ "something went wrong"
      assert event.payload["error_kind"] == "error"
      assert event.payload["error_reason"] =~ "something went wrong"
      assert event.payload["error_stack"] == nil
    end

    test "includes bounded stack trace when stacktrace is present" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      stacktrace = [
        {MyModule, :my_fun, 2, [file: ~c"lib/my_module.ex", line: 42]},
        {OtherModule, :call, 1, [file: ~c"lib/other.ex", line: 10]}
      ]

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 1_000_000, memory: 1024, queue_time: 100, reductions: 500},
        %{
          job: fake_job(),
          conf: %{},
          state: :failure,
          kind: :error,
          reason: %RuntimeError{message: "boom"},
          result: nil,
          stacktrace: stacktrace
        }
      )

      assert_receive {:flow_event,
                      %FlowEvent{kind: "oban.job.exception", status: :error} = event},
                     1000

      assert event.payload["error_stack"] != nil
      assert event.payload["error_stack"] =~ "my_module.ex"
      assert event.payload["error_stack"] =~ "other.ex"
    end

    test "handles exit kind with non-exception reason" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 500_000, memory: 512, queue_time: 50, reductions: 200},
        %{
          job: fake_job(),
          conf: %{},
          state: :failure,
          kind: :exit,
          reason: {:function_clause, [{SomeModule, :run, 1, []}]},
          result: nil,
          stacktrace: []
        }
      )

      assert_receive {:flow_event,
                      %FlowEvent{kind: "oban.job.exception", status: :error} = event},
                     1000

      assert event.payload["error_kind"] == "exit"
      assert event.payload["error_reason"] =~ "function_clause"
    end
  end

  describe "flow key derivation" do
    test "derives keys from job args with atom keys" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      job = fake_job(%{args: %{session_id: "s2", project_id: "p1"}})

      :telemetry.execute(
        [:oban, :job, :start],
        %{system_time: System.system_time()},
        %{job: job, conf: %{}}
      )

      assert_receive {:flow_event, %FlowEvent{} = event}, 1000
      assert "session:s2" in event.flow_keys
      assert "project:p1" in event.flow_keys
    end
  end

  describe "trace context propagation" do
    test "copies otel_traceparent from job args into FlowEvent trace_id" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      job =
        fake_job(%{
          args: %{
            "session_id" => "sess-1",
            "otel_traceparent" => "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
            "otel_trace_id" => "0af7651916cd43dd8448eb211c80319c"
          }
        })

      :telemetry.execute(
        [:oban, :job, :start],
        %{system_time: System.system_time()},
        %{job: job, conf: %{}}
      )

      assert_receive {:flow_event, %FlowEvent{kind: "oban.job.start"} = event}, 1000
      assert event.trace_id == "0af7651916cd43dd8448eb211c80319c"
    end
  end

  describe "commit-analysis enrichment" do
    test "includes project_id and commit_hash for commit-analysis workers" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      job =
        fake_job(%{
          worker: "Spotter.Transcripts.Jobs.AnalyzeCommitHotspots",
          args: %{
            "project_id" => "proj-1",
            "commit_hash" => "abc123"
          }
        })

      :telemetry.execute(
        [:oban, :job, :start],
        %{system_time: System.system_time()},
        %{job: job, conf: %{}}
      )

      assert_receive {:flow_event, %FlowEvent{kind: "oban.job.start"} = event}, 1000
      assert event.payload["project_id"] == "proj-1"
      assert event.payload["commit_hash"] == "abc123"
    end

    test "does not include commit-analysis fields for non-analysis workers" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      job =
        fake_job(%{
          worker: "Spotter.Workers.EnrichCommit",
          args: %{"project_id" => "proj-2", "commit_hash" => "def456"}
        })

      :telemetry.execute(
        [:oban, :job, :start],
        %{system_time: System.system_time()},
        %{job: job, conf: %{}}
      )

      assert_receive {:flow_event, %FlowEvent{kind: "oban.job.start"} = event}, 1000
      refute Map.has_key?(event.payload, "project_id")
      refute Map.has_key?(event.payload, "commit_hash")
    end

    test "exception payload includes failure fields from job meta for analysis workers" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      job =
        fake_job(%{
          worker: "Spotter.Transcripts.Jobs.AnalyzeCommitTests",
          args: %{"project_id" => "proj-3", "commit_hash" => "ghi789"},
          meta: %{
            "reason_code" => "test_spec_repo_unavailable",
            "stage" => "preflight",
            "retryable" => true
          }
        })

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 1_000_000, memory: 512, queue_time: 50, reductions: 200},
        %{
          job: job,
          conf: %{},
          state: :failure,
          kind: :error,
          reason: %RuntimeError{message: "dolt unavailable"},
          result: nil,
          stacktrace: []
        }
      )

      assert_receive {:flow_event,
                      %FlowEvent{kind: "oban.job.exception", status: :error} = event},
                     1000

      assert event.payload["project_id"] == "proj-3"
      assert event.payload["commit_hash"] == "ghi789"
      assert event.payload["reason_code"] == "test_spec_repo_unavailable"
      assert event.payload["stage"] == "preflight"
      assert event.payload["retryable"] == true
    end
  end

  describe "setup/0" do
    test "can be called multiple times without duplicate handlers" do
      assert :ok = ObanTelemetry.setup()
      assert :ok = ObanTelemetry.setup()

      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      :telemetry.execute(
        [:oban, :job, :start],
        %{system_time: System.system_time()},
        %{job: fake_job(), conf: %{}}
      )

      # Should only receive one event, not two
      assert_receive {:flow_event, %FlowEvent{}}, 1000
      refute_receive {:flow_event, %FlowEvent{}}, 200
    end
  end
end
