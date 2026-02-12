defmodule Spotter.Config.EnvParser do
  @moduledoc """
  Deterministic parsing helpers for runtime environment variables.
  Returns safe defaults for missing or malformed input.
  """

  require Logger

  @default_pool_size 10

  @valid_exporters %{
    "otlp" => :otlp,
    "stdout" => {:otel_exporter_stdout, %{}},
    "none" => :none,
    "console" => {:otel_exporter_stdout, %{}}
  }

  @doc """
  Parses a pool size from an env var value.
  Returns `#{@default_pool_size}` for missing, non-integer, or non-positive values.
  """
  def parse_pool_size(nil), do: @default_pool_size
  def parse_pool_size(""), do: @default_pool_size

  def parse_pool_size(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 ->
        int

      _ ->
        Logger.warning(
          "Invalid POOL_SIZE #{inspect(value)}, falling back to #{@default_pool_size}"
        )

        @default_pool_size
    end
  end

  @doc """
  Parses an OTEL exporter name from an env var value.
  Accepts (case-insensitive): otlp, stdout, none, console.
  Returns a value valid for `:opentelemetry` `:traces_exporter`.
  Falls back to `:otlp` for missing or unrecognized values.
  """
  def parse_otel_exporter(nil), do: :otlp
  def parse_otel_exporter(""), do: :otlp

  def parse_otel_exporter(value) when is_binary(value) do
    key = value |> String.trim() |> String.downcase()

    case Map.fetch(@valid_exporters, key) do
      {:ok, exporter} ->
        exporter

      :error ->
        Logger.warning("Invalid OTEL_EXPORTER #{inspect(value)}, falling back to :otlp")
        :otlp
    end
  end
end
