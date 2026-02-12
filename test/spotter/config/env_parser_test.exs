defmodule Spotter.Config.EnvParserTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Spotter.Config.EnvParser

  describe "parse_pool_size/1" do
    test "missing value defaults to 10" do
      assert EnvParser.parse_pool_size(nil) == 10
    end

    test "empty string defaults to 10" do
      assert EnvParser.parse_pool_size("") == 10
    end

    test "non-integer value defaults to 10 with warning" do
      assert capture_log(fn ->
               assert EnvParser.parse_pool_size("bad") == 10
             end) =~ "Invalid POOL_SIZE"
    end

    test "zero defaults to 10 with warning" do
      assert capture_log(fn ->
               assert EnvParser.parse_pool_size("0") == 10
             end) =~ "Invalid POOL_SIZE"
    end

    test "negative value defaults to 10 with warning" do
      assert capture_log(fn ->
               assert EnvParser.parse_pool_size("-5") == 10
             end) =~ "Invalid POOL_SIZE"
    end

    test "valid positive integer parses correctly" do
      assert EnvParser.parse_pool_size("20") == 20
    end

    test "value with trailing text defaults to 10" do
      assert capture_log(fn ->
               assert EnvParser.parse_pool_size("10abc") == 10
             end) =~ "Invalid POOL_SIZE"
    end
  end

  describe "parse_otel_exporter/1" do
    test "missing value defaults to :otlp" do
      assert EnvParser.parse_otel_exporter(nil) == :otlp
    end

    test "empty string defaults to :otlp" do
      assert EnvParser.parse_otel_exporter("") == :otlp
    end

    test "invalid value defaults to :otlp with warning" do
      assert capture_log(fn ->
               assert EnvParser.parse_otel_exporter("!!!") == :otlp
             end) =~ "Invalid OTEL_EXPORTER"
    end

    test "valid values parse correctly" do
      assert EnvParser.parse_otel_exporter("otlp") == :otlp
      assert EnvParser.parse_otel_exporter("stdout") == {:otel_exporter_stdout, %{}}
      assert EnvParser.parse_otel_exporter("none") == :none
      assert EnvParser.parse_otel_exporter("console") == {:otel_exporter_stdout, %{}}
    end

    test "mixed case values parse correctly" do
      assert EnvParser.parse_otel_exporter("STDOUT") == {:otel_exporter_stdout, %{}}
      assert EnvParser.parse_otel_exporter("Otlp") == :otlp
      assert EnvParser.parse_otel_exporter("NONE") == :none
    end
  end
end
