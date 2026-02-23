defmodule Spotter.Observability.ParallelLanesTelemetryTest do
  use ExUnit.Case, async: false

  require OpenTelemetry.Tracer, as: Tracer
  require Record

  alias Spotter.Observability.ParallelLanesTelemetry
  alias Spotter.Test.OtelHelpers

  Record.defrecord(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  # After refactor, handler only attaches to these 2 events
  @expected_events [
    [:spotter, :parallel_lanes, :compute, :stop],
    [:spotter, :parallel_lanes, :compute, :error]
  ]

  # These events should NOT have handlers after refactor
  @removed_events [
    [:spotter, :parallel_lanes, :compute, :start],
    [:spotter, :parallel_lanes, :compute, :exception],
    [:spotter, :parallel_lanes, :mode_switch, :start],
    [:spotter, :parallel_lanes, :mode_switch, :stop],
    [:spotter, :parallel_lanes, :mode_switch, :exception]
  ]

  setup do
    _ = :telemetry.detach("spotter.observability.parallel_lanes_telemetry")
    OtelHelpers.setup_otel_test(%{})
    :ok
  end

  describe "dead code removal" do
    test "handler only attaches to compute :stop and :error events" do
      ParallelLanesTelemetry.setup()

      for event <- @expected_events do
        handlers = :telemetry.list_handlers(event)

        matching =
          Enum.filter(handlers, fn h ->
            h.id == "spotter.observability.parallel_lanes_telemetry"
          end)

        assert matching != [],
               "Expected handler attached for #{inspect(event)}, found none"
      end
    end

    test "no handlers attached for removed events (mode_switch, compute :start/:exception)" do
      ParallelLanesTelemetry.setup()

      for event <- @removed_events do
        handlers = :telemetry.list_handlers(event)

        matching =
          Enum.filter(handlers, fn h ->
            h.id == "spotter.observability.parallel_lanes_telemetry"
          end)

        assert matching == [],
               "Expected NO handler for #{inspect(event)}, but found #{length(matching)}"
      end
    end
  end

  describe "no double span" do
    setup do
      ParallelLanesTelemetry.setup()
      :ok
    end

    test "business logic with_span produces exactly 1 span, not 2" do
      # Simulate what parallel_lanes.compute/1 does:
      # Business logic wraps in with_span, then emits telemetry :stop
      Tracer.with_span "spotter.parallel_lanes.compute" do
        Tracer.set_attribute("spotter.team_id", "team-no-double")

        :telemetry.execute(
          [:spotter, :parallel_lanes, :compute, :stop],
          %{duration: 1_000_000},
          %{lane_count: 3, overlap_count: 1, team_id: "team-no-double"}
        )
      end

      spans = OtelHelpers.collect_spans(timeout: 500)

      compute_spans =
        Enum.filter(spans, fn s -> span(s, :name) == "spotter.parallel_lanes.compute" end)

      assert length(compute_spans) == 1,
             "Expected exactly 1 compute span, got #{length(compute_spans)}"
    end
  end

  describe "stop handler does not end span" do
    setup do
      ParallelLanesTelemetry.setup()
      :ok
    end

    test "stop event does not prematurely end the parent span" do
      # Start a span manually (simulating business logic's with_span)
      Tracer.with_span "spotter.parallel_lanes.compute" do
        # Fire the stop telemetry event mid-span
        :telemetry.execute(
          [:spotter, :parallel_lanes, :compute, :stop],
          %{duration: 500_000},
          %{lane_count: 2, overlap_count: 0, team_id: "team-stop"}
        )

        # If stop handler called end_span(), setting attributes here would
        # go to a noop span. We verify the span is still active by setting
        # an attribute after the telemetry event.
        Tracer.set_attribute("after_stop", "still_active")
      end

      # The span should have the attribute set AFTER the stop event
      OtelHelpers.assert_span_attributes("spotter.parallel_lanes.compute", %{
        "after_stop" => "still_active"
      })
    end
  end

  describe "error handler records error" do
    setup do
      ParallelLanesTelemetry.setup()
      :ok
    end

    test "error event records structured error info on the active span" do
      Tracer.with_span "spotter.parallel_lanes.compute" do
        :telemetry.execute(
          [:spotter, :parallel_lanes, :compute, :error],
          %{},
          %{team_id: "t1", reason: "not_found"}
        )
      end

      OtelHelpers.assert_span_status("spotter.parallel_lanes.compute", :error)
    end

    test "error event sets error attributes from ErrorReport" do
      Tracer.with_span "spotter.parallel_lanes.compute" do
        :telemetry.execute(
          [:spotter, :parallel_lanes, :compute, :error],
          %{},
          %{team_id: "t1", reason: %RuntimeError{message: "compute blew up"}}
        )
      end

      OtelHelpers.assert_span_attributes("spotter.parallel_lanes.compute", %{
        "error.type" => "parallel_lanes_compute_error",
        "error.source" => "telemetry.parallel_lanes"
      })
    end
  end

  describe "setup/0 idempotency" do
    test "calling setup twice does not duplicate handlers" do
      assert :ok = ParallelLanesTelemetry.setup()
      assert :ok = ParallelLanesTelemetry.setup()

      handlers = :telemetry.list_handlers([:spotter, :parallel_lanes, :compute, :stop])

      matching =
        Enum.filter(handlers, fn h ->
          h.id == "spotter.observability.parallel_lanes_telemetry"
        end)

      assert length(matching) == 1,
             "Expected exactly 1 handler after double setup, got #{length(matching)}"
    end
  end
end
