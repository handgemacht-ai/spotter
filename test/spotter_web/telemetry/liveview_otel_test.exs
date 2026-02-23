defmodule SpotterWeb.Telemetry.LiveviewOtelTest do
  use ExUnit.Case, async: false

  require OpenTelemetry.Tracer, as: Tracer
  require Record

  alias Spotter.Test.OtelHelpers
  alias SpotterWeb.Telemetry.LiveviewOtel

  Record.defrecord(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  @handler_id "spotter.telemetry.liveview_otel"

  # Fake socket for metadata
  defp fake_socket(opts \\ []) do
    %{
      view: Keyword.get(opts, :view, SpotterWeb.SomeLive),
      transport_pid: Keyword.get(opts, :transport_pid, self())
    }
  end

  setup do
    _ = :telemetry.detach(@handler_id)
    # Also detach the old atom handler_id in case it's still around
    _ = :telemetry.detach(LiveviewOtel)
    OtelHelpers.setup_otel_test(%{})
    :ok
  end

  describe "mount span lifecycle" do
    setup do
      LiveviewOtel.setup()
      :ok
    end

    test "emits span spotter.liveview.mount with correct attributes" do
      :telemetry.execute(
        [:phoenix, :live_view, :mount, :start],
        %{system_time: System.system_time()},
        %{socket: fake_socket()}
      )

      :telemetry.execute(
        [:phoenix, :live_view, :mount, :stop],
        %{duration: 100_000},
        %{socket: fake_socket()}
      )

      OtelHelpers.assert_span_recorded("spotter.liveview.mount")

      OtelHelpers.assert_span_attributes("spotter.liveview.mount", %{
        "spotter.liveview.module" => "SpotterWeb.SomeLive",
        "spotter.liveview.connected" => true
      })
    end
  end

  describe "handle_params span lifecycle" do
    setup do
      LiveviewOtel.setup()
      :ok
    end

    test "emits span spotter.liveview.handle_params with correct attributes" do
      :telemetry.execute(
        [:phoenix, :live_view, :handle_params, :start],
        %{system_time: System.system_time()},
        %{socket: fake_socket()}
      )

      :telemetry.execute(
        [:phoenix, :live_view, :handle_params, :stop],
        %{duration: 50_000},
        %{socket: fake_socket()}
      )

      OtelHelpers.assert_span_recorded("spotter.liveview.handle_params")

      OtelHelpers.assert_span_attributes("spotter.liveview.handle_params", %{
        "spotter.liveview.module" => "SpotterWeb.SomeLive"
      })
    end
  end

  describe "handle_event span lifecycle" do
    setup do
      LiveviewOtel.setup()
      :ok
    end

    test "emits span spotter.liveview.handle_event with event attribute" do
      :telemetry.execute(
        [:phoenix, :live_view, :handle_event, :start],
        %{system_time: System.system_time()},
        %{socket: fake_socket(), event: "click_button"}
      )

      :telemetry.execute(
        [:phoenix, :live_view, :handle_event, :stop],
        %{duration: 30_000},
        %{socket: fake_socket(), event: "click_button"}
      )

      OtelHelpers.assert_span_recorded("spotter.liveview.handle_event")

      OtelHelpers.assert_span_attributes("spotter.liveview.handle_event", %{
        "spotter.liveview.event" => "click_button"
      })
    end
  end

  describe "no cross-event context leak" do
    setup do
      LiveviewOtel.setup()
      :ok
    end

    test "handle_params span is NOT a child of mount span" do
      # Simulate mount lifecycle
      :telemetry.execute(
        [:phoenix, :live_view, :mount, :start],
        %{system_time: System.system_time()},
        %{socket: fake_socket()}
      )

      :telemetry.execute(
        [:phoenix, :live_view, :mount, :stop],
        %{duration: 100_000},
        %{socket: fake_socket()}
      )

      # Simulate handle_params lifecycle (same process, like a real LiveView socket)
      :telemetry.execute(
        [:phoenix, :live_view, :handle_params, :start],
        %{system_time: System.system_time()},
        %{socket: fake_socket()}
      )

      :telemetry.execute(
        [:phoenix, :live_view, :handle_params, :stop],
        %{duration: 50_000},
        %{socket: fake_socket()}
      )

      spans = OtelHelpers.collect_spans(timeout: 500)

      mount_span = Enum.find(spans, fn s -> span(s, :name) == "spotter.liveview.mount" end)

      params_span =
        Enum.find(spans, fn s -> span(s, :name) == "spotter.liveview.handle_params" end)

      assert mount_span != nil, "Expected mount span to exist"
      assert params_span != nil, "Expected handle_params span to exist"

      # handle_params should NOT be a child of mount (no leaked parent context)
      assert span(params_span, :parent_span_id) != span(mount_span, :span_id),
             "handle_params span should NOT be a child of mount span (context leak detected)"
    end
  end

  describe "exception sets error status" do
    setup do
      LiveviewOtel.setup()
      :ok
    end

    test "mount exception sets span status to :error" do
      :telemetry.execute(
        [:phoenix, :live_view, :mount, :start],
        %{system_time: System.system_time()},
        %{socket: fake_socket()}
      )

      :telemetry.execute(
        [:phoenix, :live_view, :mount, :exception],
        %{duration: 10_000},
        %{
          socket: fake_socket(),
          kind: :error,
          reason: %RuntimeError{message: "mount crashed"},
          stacktrace: []
        }
      )

      OtelHelpers.assert_span_status("spotter.liveview.mount", :error)
    end
  end

  describe "handler_id is string" do
    test "handler uses a string ID, not an atom" do
      LiveviewOtel.setup()

      handlers = :telemetry.list_handlers([:phoenix, :live_view, :mount, :start])

      liveview_handler =
        Enum.find(handlers, fn h ->
          h.id == @handler_id or h.id == LiveviewOtel
        end)

      assert liveview_handler != nil, "Expected LiveviewOtel handler to be attached"

      assert is_binary(liveview_handler.id),
             "Expected handler_id to be a string, got: #{inspect(liveview_handler.id)}"
    end
  end

  describe "setup/0 idempotency" do
    test "calling setup twice does not duplicate handlers" do
      assert :ok = LiveviewOtel.setup()
      assert :ok = LiveviewOtel.setup()

      handlers = :telemetry.list_handlers([:phoenix, :live_view, :mount, :start])

      matching =
        Enum.filter(handlers, fn h ->
          is_binary(h.id) and String.contains?(h.id, "liveview")
        end)

      assert length(matching) == 1,
             "Expected exactly 1 handler after double setup, got #{length(matching)}"
    end
  end
end
