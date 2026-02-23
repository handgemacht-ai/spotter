defmodule Spotter.Test.OtelHelpersTest do
  use ExUnit.Case, async: false

  alias Spotter.Test.OtelHelpers

  require OpenTelemetry.Tracer, as: Tracer
  require Record

  # Extract the :span record from the OTel library so we can inspect fields
  Record.defrecord(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  describe "setup_otel_test/1" do
    test "configures span export so spans are receivable as messages" do
      OtelHelpers.setup_otel_test(%{})

      Tracer.with_span "test.setup_span" do
        :ok
      end

      # After setup, we should receive span records as messages
      assert_receive {:span, span_record}, 1_000
      assert span(span_record, :name) == "test.setup_span"

      # TELEMETRY: span has valid trace_id and span_id (non-zero integers)
      assert is_integer(span(span_record, :trace_id))
      assert span(span_record, :trace_id) != 0
      assert is_integer(span(span_record, :span_id))
      assert span(span_record, :span_id) != 0
    end
  end

  describe "assert_span_recorded/2" do
    setup do
      OtelHelpers.setup_otel_test(%{})
      :ok
    end

    test "passes when a span with the given name was recorded" do
      Tracer.with_span "recorded.span" do
        :ok
      end

      assert OtelHelpers.assert_span_recorded("recorded.span")
    end

    test "fails when no span with the given name exists" do
      Tracer.with_span "other.span" do
        :ok
      end

      assert_raise ExUnit.AssertionError, fn ->
        OtelHelpers.assert_span_recorded("nonexistent.span", timeout: 200)
      end
    end
  end

  describe "assert_span_attributes/3" do
    setup do
      OtelHelpers.setup_otel_test(%{})
      :ok
    end

    test "passes when span has matching attribute subset" do
      Tracer.with_span "attrs.span" do
        Tracer.set_attribute("user.id", "u-42")
        Tracer.set_attribute("user.role", "admin")
      end

      # Partial match — only check one attribute
      assert OtelHelpers.assert_span_attributes("attrs.span", %{"user.id" => "u-42"})
    end

    test "fails when expected attribute is missing" do
      Tracer.with_span "attrs.span.missing" do
        Tracer.set_attribute("user.id", "u-42")
      end

      assert_raise ExUnit.AssertionError, fn ->
        OtelHelpers.assert_span_attributes(
          "attrs.span.missing",
          %{"nonexistent.attr" => "value"},
          timeout: 200
        )
      end
    end

    test "TELEMETRY: attributes are extractable from the span record" do
      Tracer.with_span "attrs.telemetry" do
        Tracer.set_attribute("metric.count", 5)
        Tracer.set_attribute("metric.name", "requests")
      end

      assert OtelHelpers.assert_span_attributes("attrs.telemetry", %{
               "metric.count" => 5,
               "metric.name" => "requests"
             })
    end
  end

  describe "assert_span_status/3" do
    setup do
      OtelHelpers.setup_otel_test(%{})
      :ok
    end

    test "passes when span status matches :error" do
      Tracer.with_span "status.error.span" do
        Tracer.set_status(:error, "something failed")
      end

      assert OtelHelpers.assert_span_status("status.error.span", :error)
    end

    test "fails when span status does not match" do
      Tracer.with_span "status.ok.span" do
        :ok
      end

      assert_raise ExUnit.AssertionError, fn ->
        OtelHelpers.assert_span_status("status.ok.span", :error, timeout: 200)
      end
    end
  end

  describe "assert_child_span/3" do
    setup do
      OtelHelpers.setup_otel_test(%{})
      :ok
    end

    test "passes when child span's parent_span_id matches parent's span_id" do
      Tracer.with_span "parent.span" do
        Tracer.with_span "child.span" do
          :ok
        end
      end

      assert OtelHelpers.assert_child_span("parent.span", "child.span")
    end

    test "TELEMETRY: parent_span_id is correctly set for nested spans" do
      Tracer.with_span "tel.parent" do
        Tracer.with_span "tel.child" do
          :ok
        end
      end

      # The assertion itself validates the parent-child relationship
      assert OtelHelpers.assert_child_span("tel.parent", "tel.child")
    end

    test "fails when spans are not in parent-child relationship" do
      Tracer.with_span "standalone.a" do
        :ok
      end

      Tracer.with_span "standalone.b" do
        :ok
      end

      assert_raise ExUnit.AssertionError, fn ->
        OtelHelpers.assert_child_span("standalone.a", "standalone.b", timeout: 200)
      end
    end
  end

  describe "refute_span_recorded/2" do
    setup do
      OtelHelpers.setup_otel_test(%{})
      :ok
    end

    test "passes when no span with the given name was recorded" do
      # Don't create any spans
      assert OtelHelpers.refute_span_recorded("absent.span", timeout: 200)
    end

    test "passes when a different span exists but the target does not" do
      Tracer.with_span "existing.span" do
        :ok
      end

      assert OtelHelpers.refute_span_recorded("absent.other.span", timeout: 200)
    end

    test "fails when the span actually exists" do
      Tracer.with_span "present.span" do
        :ok
      end

      assert_raise ExUnit.AssertionError, fn ->
        OtelHelpers.refute_span_recorded("present.span", timeout: 500)
      end
    end
  end

  describe "collect_spans/2" do
    setup do
      OtelHelpers.setup_otel_test(%{})
      :ok
    end

    test "collects all spans created within the timeout" do
      Tracer.with_span "collect.one" do
        :ok
      end

      Tracer.with_span "collect.two" do
        :ok
      end

      Tracer.with_span "collect.three" do
        :ok
      end

      spans = OtelHelpers.collect_spans(timeout: 500)
      names = Enum.map(spans, fn s -> span(s, :name) end)

      assert length(spans) >= 3
      assert "collect.one" in names
      assert "collect.two" in names
      assert "collect.three" in names
    end

    test "returns empty list when no spans are created" do
      spans = OtelHelpers.collect_spans(timeout: 200)
      assert spans == []
    end

    test "TELEMETRY: collected spans have valid trace_id and span_id" do
      Tracer.with_span "collect.valid" do
        :ok
      end

      spans = OtelHelpers.collect_spans(timeout: 500)
      assert spans != []

      for s <- spans do
        assert is_integer(span(s, :trace_id))
        assert span(s, :trace_id) != 0
        assert is_integer(span(s, :span_id))
        assert span(s, :span_id) != 0
      end
    end
  end
end
