defmodule Spotter.Services.Tmux do
  @moduledoc """
  Discovers and interacts with tmux panes via the tmux CLI.
  """

  @doc """
  Lists all tmux panes across all sessions.
  Returns `{:ok, [pane]}` or `{:error, reason}`.

  Each pane is a map with keys:
  `:pane_id`, `:session_name`, `:window_index`, `:pane_index`,
  `:pane_title`, `:pane_width`, `:pane_height`, `:pane_current_command`.
  """
  def list_panes do
    format =
      "#{pf("pane_id")}#{pf("session_name")}#{pf("window_index")}#{pf("pane_index")}#{pf("pane_title")}#{pf("pane_width")}#{pf("pane_height")}#{pf("pane_current_command")}"

    case System.cmd("tmux", ["list-panes", "-a", "-F", format], stderr_to_stdout: true) do
      {output, 0} ->
        panes =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_pane_line/1)

        {:ok, panes}

      {output, _} ->
        {:error, String.trim(output)}
    end
  rescue
    e in ErlangError -> {:error, Exception.message(e)}
  end

  @doc """
  Lists panes that appear to be running Claude Code.
  """
  def list_claude_panes do
    with {:ok, panes} <- list_panes() do
      claude_panes =
        Enum.filter(panes, fn pane ->
          pane.pane_current_command in ["claude", "claude-code"] or
            String.contains?(pane.pane_title, "claude")
        end)

      {:ok, claude_panes}
    end
  end

  @doc """
  Captures the current visible content of a pane.
  """
  def capture_pane(pane_id) do
    case System.cmd("tmux", ["capture-pane", "-t", pane_id, "-p", "-e"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, String.trim(output)}
    end
  rescue
    e in ErlangError -> {:error, Exception.message(e)}
  end

  @doc """
  Sends keys to a tmux pane.
  """
  def send_keys(pane_id, keys) do
    case System.cmd("tmux", ["send-keys", "-t", pane_id, "-l", keys], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, String.trim(output)}
    end
  rescue
    e in ErlangError -> {:error, Exception.message(e)}
  end

  @doc """
  Returns the session name for a given pane_id.
  """
  def session_for_pane(pane_id) do
    case System.cmd("tmux", ["display-message", "-t", pane_id, "-p", "\#{session_name}"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  rescue
    e in ErlangError -> {:error, Exception.message(e)}
  end

  @doc """
  Checks if a pane_id exists.
  """
  def pane_exists?(pane_id) do
    case System.cmd("tmux", ["has-session", "-t", pane_id], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  # Private helpers

  defp pf(field), do: "\#{#{field}}\t"

  defp parse_pane_line(line) do
    parts = String.split(line, "\t")

    %{
      pane_id: Enum.at(parts, 0, ""),
      session_name: Enum.at(parts, 1, ""),
      window_index: Enum.at(parts, 2, "0") |> String.to_integer(),
      pane_index: Enum.at(parts, 3, "0") |> String.to_integer(),
      pane_title: Enum.at(parts, 4, ""),
      pane_width: Enum.at(parts, 5, "80") |> String.to_integer(),
      pane_height: Enum.at(parts, 6, "24") |> String.to_integer(),
      pane_current_command: Enum.at(parts, 7, "") |> String.trim()
    }
  end
end
