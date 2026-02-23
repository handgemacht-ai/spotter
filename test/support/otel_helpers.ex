defmodule Spotter.Test.OtelHelpers do
  @moduledoc """
  Test helpers for asserting on OpenTelemetry spans.

  Uses `:otel_exporter_pid` to route finished spans to the test process
  as `{:span, record}` messages, then provides assertion helpers to
  inspect span names, attributes, status, and parent-child relationships.
  """

  import ExUnit.Assertions

  require Record

  Record.defrecord(
    :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  Record.defrecord(
    :status,
    Record.extract(:status, from_lib: "opentelemetry_api/include/opentelemetry.hrl")
  )

  @default_timeout 1_000

  @doc """
  Configures the OTel simple processor to export spans to `self()`.
  Call in test setup blocks.
  """
  @spec setup_otel_test(map()) :: :ok
  def setup_otel_test(_context) do
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
    :otel_ctx.clear()
    :ok
  end

  @doc """
  Asserts that a span with the given `name` was recorded.
  """
  def assert_span_recorded(name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    spans = collect_spans(timeout: timeout)

    {matched, rest} = Enum.split_with(spans, fn s -> span(s, :name) == name end)

    # Re-queue all spans so subsequent assertions can find them
    Enum.each(rest ++ matched, fn s -> send(self(), {:span, s}) end)

    assert matched != [],
           "Expected span #{inspect(name)} to be recorded within #{timeout}ms"

    true
  end

  @doc """
  Asserts that a span with `name` has all `expected_attrs` (partial match).
  """
  def assert_span_attributes(name, expected_attrs, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    span_record = receive_span_by_name(name, timeout)

    actual_attrs = extract_attributes_map(span_record)

    Enum.each(expected_attrs, fn {key, value} ->
      assert Map.get(actual_attrs, key) == value,
             "Expected span #{inspect(name)} to have attribute #{inspect(key)} = #{inspect(value)}, " <>
               "got: #{inspect(Map.get(actual_attrs, key))}. All attributes: #{inspect(actual_attrs)}"
    end)

    true
  end

  @doc """
  Asserts that a span with `name` has the given status code.
  """
  def assert_span_status(name, expected_status, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    span_record = receive_span_by_name(name, timeout)

    status = span(span_record, :status)
    actual_code = extract_status_code(status)

    assert actual_code == expected_status,
           "Expected span #{inspect(name)} to have status #{inspect(expected_status)}, " <>
             "got: #{inspect(actual_code)}"

    true
  end

  @doc """
  Asserts that `child_name` span is a child of `parent_name` span
  (i.e. child's parent_span_id == parent's span_id).
  """
  def assert_child_span(parent_name, child_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    spans = collect_spans(Keyword.merge([timeout: timeout], opts))

    parent = Enum.find(spans, fn s -> span(s, :name) == parent_name end)
    child = Enum.find(spans, fn s -> span(s, :name) == child_name end)

    # Re-queue spans not involved in this assertion
    Enum.each(spans, fn s ->
      name = span(s, :name)
      if name != parent_name and name != child_name, do: send(self(), {:span, s})
    end)

    assert parent != nil,
           "Expected parent span #{inspect(parent_name)} to exist"

    assert child != nil,
           "Expected child span #{inspect(child_name)} to exist"

    parent_span_id = span(parent, :span_id)
    child_parent_id = span(child, :parent_span_id)

    assert child_parent_id == parent_span_id,
           "Expected child span #{inspect(child_name)} parent_span_id (#{inspect(child_parent_id)}) " <>
             "to equal parent span #{inspect(parent_name)} span_id (#{inspect(parent_span_id)})"

    true
  end

  @doc """
  Asserts that NO span with the given `name` was recorded within the timeout.
  """
  def refute_span_recorded(name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    spans = collect_spans(timeout: timeout)

    matching = Enum.find(spans, fn s -> span(s, :name) == name end)

    # Re-queue non-matching spans
    Enum.each(spans, fn s ->
      if span(s, :name) != name, do: send(self(), {:span, s})
    end)

    assert matching == nil,
           "Expected span #{inspect(name)} NOT to be recorded, but it was"

    true
  end

  @doc """
  Collects all span messages received within the timeout period.
  """
  def collect_spans(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    collect_spans_loop(timeout, [])
  end

  # --- Private helpers ---

  defp collect_spans_loop(timeout, acc) do
    receive do
      {:span, span_record} when elem(span_record, 0) == :span ->
        collect_spans_loop(timeout, [span_record | acc])
    after
      timeout -> Enum.reverse(acc)
    end
  end

  defp receive_span_by_name(name, timeout) do
    spans = collect_spans(timeout: timeout)

    {matched, rest} = Enum.split_with(spans, fn s -> span(s, :name) == name end)

    # Re-queue non-matching spans
    Enum.each(rest, fn s -> send(self(), {:span, s}) end)

    case matched do
      [span_record | _] -> span_record
      [] -> flunk("Expected span #{inspect(name)} to be recorded within #{timeout}ms")
    end
  end

  defp extract_attributes_map(span_record) do
    attrs = span(span_record, :attributes)
    :otel_attributes.map(attrs)
  end

  defp extract_status_code(s) when is_tuple(s) and elem(s, 0) == :status do
    status(s, :code)
  end

  defp extract_status_code(:undefined), do: :unset
  defp extract_status_code(nil), do: :unset
end
