defmodule Spotter.Services.CommitPatchExtractor do
  @moduledoc "Parses unified diff hunks from a commit to identify new/changed code ranges."

  require Logger

  alias Spotter.Services.GitRunner

  @doc """
  Returns a list of per-file hunk data for a commit.

  Each entry is `%{path: String.t(), hunks: [%{new_start: integer, new_len: integer, lines: [String.t()]}]}`.

  Hunks with `new_len == 0` (deletion-only) are skipped.
  """
  @spec patch_hunks(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def patch_hunks(repo_path, commit_hash) do
    case GitRunner.run(["show", "--format=", "--unified=0", commit_hash],
           cd: repo_path,
           timeout_ms: 20_000
         ) do
      {:ok, output} ->
        {:ok, parse_patch(output)}

      {:error, err} ->
        Logger.warning("CommitPatchExtractor: git show failed: #{inspect(err.kind)}")

        {:error, :git_show_failed}
    end
  end

  @doc false
  def parse_patch(output) do
    output
    |> split_file_diffs()
    |> Enum.flat_map(&parse_file_diff/1)
  end

  defp split_file_diffs(output) do
    # Split on "diff --git" boundaries
    output
    |> String.split(~r/^diff --git /m, trim: true)
  end

  defp parse_file_diff(block) do
    lines = String.split(block, "\n")

    case extract_path(lines) do
      nil ->
        []

      path ->
        hunks =
          lines
          |> extract_hunks()
          |> Enum.reject(&(&1.new_len == 0))

        if hunks == [] do
          []
        else
          [%{path: path, hunks: hunks}]
        end
    end
  end

  defp extract_path(lines) do
    # Look for +++ b/path line
    Enum.find_value(lines, fn line ->
      case line do
        "+++ b/" <> path -> path
        _ -> nil
      end
    end)
  end

  defp extract_hunks(lines) do
    lines
    |> Enum.chunk_while(nil, &classify_line/2, &flush_acc/1)
    |> Enum.reject(&is_nil/1)
  end

  defp classify_line(line, acc) do
    cond do
      String.starts_with?(line, "@@") ->
        if acc,
          do: {:cont, acc, parse_hunk_header(line)},
          else: {:cont, parse_hunk_header(line)}

      acc && String.starts_with?(line, "+") ->
        {:cont, %{acc | lines: acc.lines ++ [String.slice(line, 1..-1//1)]}}

      true ->
        {:cont, acc}
    end
  end

  defp flush_acc(nil), do: {:cont, nil}
  defp flush_acc(acc), do: {:cont, acc, nil}

  @hunk_header_re ~r/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

  defp parse_hunk_header(line) do
    case Regex.run(@hunk_header_re, line) do
      [_, start_str] ->
        %{new_start: String.to_integer(start_str), new_len: 1, lines: []}

      [_, start_str, len_str] ->
        %{new_start: String.to_integer(start_str), new_len: String.to_integer(len_str), lines: []}

      _ ->
        nil
    end
  end
end
