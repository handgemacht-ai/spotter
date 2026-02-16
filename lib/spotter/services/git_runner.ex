defmodule Spotter.Services.GitRunner do
  @moduledoc """
  Port-based git command runner with enforced timeouts and structured errors.

  Prevents agent jobs from hanging indefinitely on git operations by using
  an Erlang Port instead of `System.cmd/3`.
  """

  require OpenTelemetry.Tracer, as: Tracer

  @default_timeout_ms 10_000
  @default_max_bytes 1_000_000

  @doc """
  Runs a git command with enforced timeout.

  ## Options

    * `:cd` — repo path (required)
    * `:timeout_ms` — hard timeout in milliseconds (default #{@default_timeout_ms})
    * `:max_bytes` — max output bytes before truncation (default #{@default_max_bytes})

  ## Returns

    * `{:ok, output}` — command succeeded (exit 0)
    * `{:error, %{kind: :timeout, ...}}` — command timed out
    * `{:error, %{kind: :exit_nonzero, status: int, ...}}` — non-zero exit
  """
  @spec run([String.t()], keyword()) :: {:ok, binary()} | {:error, map()}
  def run(args, opts) when is_list(args) do
    cd = Keyword.fetch!(opts, :cd)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)

    args_display = Enum.join(["git" | args], " ") |> String.slice(0, 500)

    Tracer.with_span "spotter.git.run" do
      Tracer.set_attribute("spotter.git.args", args_display)
      Tracer.set_attribute("spotter.git.timeout_ms", timeout_ms)
      Tracer.set_attribute("spotter.git.max_bytes", max_bytes)

      git = System.find_executable("git") || "git"
      full_args = ["-C", cd | args]

      port =
        Port.open({:spawn_executable, git}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          args: full_args
        ])

      try do
        collect_output(port, timeout_ms, max_bytes)
      after
        safe_close(port)
      end
    end
  end

  defp collect_output(port, timeout_ms, max_bytes) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_collect(port, deadline, max_bytes, [])
  end

  defp do_collect(port, deadline, max_bytes, acc) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      output = IO.iodata_to_binary(acc)
      truncated = byte_size(output) > max_bytes
      output = if truncated, do: binary_part(output, 0, max_bytes), else: output

      Tracer.set_status(:error, "timeout")

      {:error,
       %{
         kind: :timeout,
         timeout_ms: deadline_to_timeout(deadline),
         output: output,
         truncated: truncated
       }}
    else
      receive do
        {^port, {:data, data}} ->
          total = IO.iodata_length(acc) + byte_size(data)

          if total > max_bytes do
            output = IO.iodata_to_binary([acc, data]) |> binary_part(0, max_bytes)

            {:error,
             %{kind: :output_too_large, max_bytes: max_bytes, output: output, truncated: true}}
          else
            do_collect(port, deadline, max_bytes, [acc, data])
          end

        {^port, {:exit_status, 0}} ->
          output = IO.iodata_to_binary(acc)
          Tracer.set_attribute("spotter.git.exit_status", 0)
          {:ok, output}

        {^port, {:exit_status, status}} ->
          output = IO.iodata_to_binary(acc)
          Tracer.set_attribute("spotter.git.exit_status", status)
          Tracer.set_status(:error, "exit #{status}")

          {:error, %{kind: :exit_nonzero, status: status, output: output, truncated: false}}
      after
        max(remaining, 0) ->
          output = IO.iodata_to_binary(acc)
          truncated = byte_size(output) > max_bytes
          output = if truncated, do: binary_part(output, 0, max_bytes), else: output

          Tracer.set_status(:error, "timeout")

          {:error,
           %{
             kind: :timeout,
             timeout_ms: deadline_to_timeout(deadline),
             output: output,
             truncated: truncated
           }}
      end
    end
  end

  defp deadline_to_timeout(deadline) do
    # Approximate original timeout from deadline
    max(deadline - System.monotonic_time(:millisecond), 0)
  end

  defp safe_close(port) do
    if Port.info(port), do: Port.close(port)
  rescue
    _ -> :ok
  end
end
