#!/usr/bin/env elixir
# [doctor:claude-hook-truncation:v1]

defmodule ClaudeHookWrapper do
  @moduledoc false

  @max_chars_env "CLAUDE_HOOK_OUTPUT_MAX_CHARS"
  @max_lines_env "CLAUDE_HOOK_OUTPUT_MAX_LINES"
  @default_max_chars 8_000
  @default_max_lines 120
  @truncation_suffix "[truncated]"

  def main(args) do
    case args do
      [event_type] ->
        json_input = IO.read(:stdio, :eof)
        config = load_claude_config()
        ensure_dependencies_installed(config)
        run_hook(event_type, json_input)

      _ ->
        IO.puts(:stderr, "Usage: elixir claude_hook_wrapper.exs <event_type>")
        System.halt(1)
    end
  end

  defp load_claude_config do
    config_path = ".claude.exs"

    if File.exists?(config_path) do
      try do
        {config, _} = Code.eval_file(config_path)
        config
      rescue
        _ -> %{}
      end
    else
      %{}
    end
  end

  defp ensure_dependencies_installed(config) do
    auto_install? = Map.get(config, :auto_install_deps?, false)

    if auto_install? do
      check_and_install_deps()
    end
  end

  defp check_and_install_deps do
    case System.cmd("mix", ["deps"], stderr_to_stdout: true) do
      {output, exit_code} ->
        needs_deps? =
          String.contains?(output, "run \"mix deps.get\"") ||
            String.contains?(output, "lock mismatch") ||
            String.contains?(output, "Can't continue due to errors on dependencies") ||
            exit_code != 0 ||
            not File.exists?("deps")

        if needs_deps? do
          IO.puts(:stderr, "Dependencies not installed. Running mix deps.get...")

          case System.cmd("mix", ["deps.get"], stderr_to_stdout: true) do
            {_, 0} ->
              IO.puts(:stderr, "Dependencies installed successfully.")

            {deps_output, _} ->
              IO.puts(:stderr, "Failed to install dependencies:")
              IO.write(:stderr, truncate_text(deps_output))
              System.halt(2)
          end
        end
    end
  end

  defp run_hook(event_type, json_input) do
    temp_file = Path.join(System.tmp_dir!(), "claude_hook_#{:os.system_time()}.json")
    stdout_file = Path.join(System.tmp_dir!(), "claude_hook_stdout_#{:os.system_time()}.log")
    stderr_file = Path.join(System.tmp_dir!(), "claude_hook_stderr_#{:os.system_time()}.log")

    try do
      File.write!(temp_file, json_input)

      command =
        "mix claude.hooks.run #{shell_escape(event_type)} --json-file #{shell_escape(temp_file)} 1>#{shell_escape(stdout_file)} 2>#{shell_escape(stderr_file)}"

      {_ignored, exit_status} = System.cmd("sh", ["-c", command])
      stdout = read_file(stdout_file)
      stderr = read_file(stderr_file)

      emit_outputs(event_type, stdout, stderr, exit_status)
      System.halt(exit_status)
    after
      File.rm(temp_file)
      File.rm(stdout_file)
      File.rm(stderr_file)
    end
  end

  defp emit_outputs(event_type, stdout, stderr, exit_status) do
    if stderr != "" do
      IO.write(:stderr, truncate_text(stderr))
    end

    cond do
      exit_status == 0 and stdout == "" ->
        :ok

      exit_status == 0 and passthrough_stdout?(event_type) ->
        IO.write(:stdio, stdout)

      exit_status == 0 ->
        IO.write(:stdio, truncate_success_stdout(stdout))

      stderr == "" and stdout != "" ->
        IO.write(:stderr, truncate_text(stdout))

      true ->
        :ok
    end
  end

  defp passthrough_stdout?(event_type), do: event_type in ["worktree_create", "worktree_remove"]

  defp truncate_success_stdout(stdout) do
    case Jason.decode(stdout) do
      {:ok, payload} ->
        payload
        |> clamp_strings()
        |> Jason.encode!()
        |> Kernel.<>("\n")

      {:error, _reason} ->
        truncate_text(stdout)
    end
  end

  defp clamp_strings(value) when is_binary(value) do
    max_chars = max_chars()

    if String.length(value) > max_chars do
      visible = max(max_chars - String.length(@truncation_suffix), 0)
      String.slice(value, 0, visible) <> @truncation_suffix
    else
      value
    end
  end

  defp clamp_strings(value) when is_list(value), do: Enum.map(value, &clamp_strings/1)

  defp clamp_strings(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {key, clamp_strings(nested_value)} end)
  end

  defp clamp_strings(value), do: value

  defp truncate_text(text) do
    lines = String.split(text, "\n")
    total_lines = length(lines)
    total_chars = String.length(text)
    max_lines = max_lines()
    max_chars = max_chars()

    {truncated_lines, line_marker} =
      if total_lines > max_lines do
        {
          lines |> Enum.take(max_lines) |> Enum.join("\n"),
          "[truncated: #{max_lines}/#{total_lines} lines]"
        }
      else
        {text, nil}
      end

    {truncated_text, marker} =
      if String.length(truncated_lines) > max_chars do
        visible = max(max_chars - String.length(@truncation_suffix), 0)
        shortened = String.slice(truncated_lines, 0, visible) <> @truncation_suffix
        chars_marker = "[truncated: #{max_chars}/#{total_chars} chars]"

        {
          shortened,
          [line_marker, chars_marker] |> Enum.reject(&is_nil/1) |> Enum.join("; ")
        }
      else
        {truncated_lines, line_marker}
      end

    if marker do
      truncated_text <> "\n\n" <> marker <> "\n"
    else
      truncated_text
    end
  end

  defp max_chars do
    @max_chars_env
    |> System.get_env(Integer.to_string(@default_max_chars))
    |> parse_positive_integer(@default_max_chars)
  end

  defp max_lines do
    @max_lines_env
    |> System.get_env(Integer.to_string(@default_max_lines))
    |> parse_positive_integer(@default_max_lines)
  end

  defp parse_positive_integer(value, fallback) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _reason} -> ""
    end
  end

  defp shell_escape(value) do
    escaped = String.replace(value, "'", "'\"'\"'")
    "'#{escaped}'"
  end
end

ClaudeHookWrapper.main(System.argv())
