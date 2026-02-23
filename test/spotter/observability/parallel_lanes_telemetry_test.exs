defmodule Spotter.Observability.ParallelLanesTelemetryTest do
  use ExUnit.Case, async: false

  alias Spotter.Observability.ParallelLanesTelemetry

  @compute_events [
    [:spotter, :parallel_lanes, :compute, :start],
    [:spotter, :parallel_lanes, :compute, :stop],
    [:spotter, :parallel_lanes, :compute, :exception]
  ]

  @mode_switch_events [
    [:spotter, :parallel_lanes, :mode_switch, :start],
    [:spotter, :parallel_lanes, :mode_switch, :stop],
    [:spotter, :parallel_lanes, :mode_switch, :exception]
  ]

  @all_events @compute_events ++ @mode_switch_events

  setup do
    # Detach any leftover handlers from previous tests
    _ = :telemetry.detach("spotter.observability.parallel_lanes_telemetry")
    :ok
  end

  describe "setup/0 attaches handlers" do
    test "attaches handlers for all expected telemetry events" do
      assert :ok = ParallelLanesTelemetry.setup()

      for event <- @all_events do
        handlers = :telemetry.list_handlers(event)

        matching =
          Enum.filter(handlers, fn h ->
            h.id == "spotter.observability.parallel_lanes_telemetry"
          end)

        assert matching != [],
               "Expected handler attached for #{inspect(event)}, found none"
      end
    end
  end

  describe "compute span lifecycle" do
    setup do
      ParallelLanesTelemetry.setup()
      :ok
    end

    test "start then stop does not crash" do
      :telemetry.execute(
        [:spotter, :parallel_lanes, :compute, :start],
        %{system_time: System.system_time()},
        %{lane_count: 3, overlap_count: 1, team_id: "team-abc"}
      )

      :telemetry.execute(
        [:spotter, :parallel_lanes, :compute, :stop],
        %{duration: 1_500_000},
        %{lane_count: 3, overlap_count: 1, team_id: "team-abc"}
      )
    end
  end

  describe "compute exception handling" do
    setup do
      ParallelLanesTelemetry.setup()
      :ok
    end

    test "exception event does not crash" do
      :telemetry.execute(
        [:spotter, :parallel_lanes, :compute, :exception],
        %{duration: 500_000},
        %{
          kind: :error,
          reason: %RuntimeError{message: "compute failed"},
          stacktrace: [],
          lane_count: 2,
          overlap_count: 0,
          team_id: "team-xyz"
        }
      )
    end
  end

  describe "mode_switch span lifecycle" do
    setup do
      ParallelLanesTelemetry.setup()
      :ok
    end

    test "start then stop does not crash" do
      :telemetry.execute(
        [:spotter, :parallel_lanes, :mode_switch, :start],
        %{system_time: System.system_time()},
        %{from_mode: :transcript, to_mode: :parallel_lanes, session_id: "sess-123"}
      )

      :telemetry.execute(
        [:spotter, :parallel_lanes, :mode_switch, :stop],
        %{duration: 200_000},
        %{from_mode: :transcript, to_mode: :parallel_lanes, session_id: "sess-123"}
      )
    end
  end

  describe "setup/0 idempotency" do
    test "calling setup twice does not duplicate handlers" do
      assert :ok = ParallelLanesTelemetry.setup()
      assert :ok = ParallelLanesTelemetry.setup()

      # Pick one event and check there's exactly one handler with our ID
      handlers = :telemetry.list_handlers([:spotter, :parallel_lanes, :compute, :start])

      matching =
        Enum.filter(handlers, fn h ->
          h.id == "spotter.observability.parallel_lanes_telemetry"
        end)

      assert length(matching) == 1,
             "Expected exactly 1 handler after double setup, got #{length(matching)}"
    end
  end
end
