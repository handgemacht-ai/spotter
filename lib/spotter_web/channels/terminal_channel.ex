defmodule SpotterWeb.TerminalChannel do
  use Phoenix.Channel

  require Logger

  alias Spotter.Services.Tmux

  @impl true
  def join("terminal:" <> pane_id, _params, socket) do
    if Tmux.pane_exists?(pane_id) do
      send(self(), :start_streaming)

      initial_content =
        case Tmux.capture_pane(pane_id) do
          {:ok, content} -> content
          _ -> ""
        end

      {:ok, %{initial_content: initial_content}, assign(socket, :pane_id, pane_id)}
    else
      {:error, %{reason: "pane not found"}}
    end
  end

  @impl true
  def handle_info(:start_streaming, socket) do
    pane_id = socket.assigns.pane_id

    port =
      Port.open(
        {:spawn_executable, System.find_executable("tmux")},
        [
          :binary,
          :exit_status,
          args: ["-C", "attach-session", "-t", pane_id, "-r"]
        ]
      )

    {:noreply, assign(socket, :port, port)}
  end

  def handle_info({port, {:data, data}}, %{assigns: %{port: port}} = socket) do
    # tmux control mode outputs lines like %output %<pane_id> <data>
    data
    |> String.split("\n")
    |> Enum.each(fn line ->
      case parse_control_line(line) do
        {:output, _target_pane, content} ->
          push(socket, "output", %{data: decode_octal(content)})

        _ ->
          :ok
      end
    end)

    {:noreply, socket}
  end

  def handle_info({port, {:exit_status, _status}}, %{assigns: %{port: port}} = socket) do
    Logger.info("tmux control mode exited for pane #{socket.assigns.pane_id}")
    {:stop, :normal, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_in("input", %{"data" => data}, socket) do
    Tmux.send_keys(socket.assigns.pane_id, data)
    {:noreply, socket}
  end

  def handle_in("resize", %{"cols" => cols, "rows" => rows}, socket) do
    pane_id = socket.assigns.pane_id

    System.cmd("tmux", ["resize-pane", "-t", pane_id, "-x", to_string(cols), "-y", to_string(rows)],
      stderr_to_stdout: true
    )

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if port = socket.assigns[:port] do
      Port.close(port)
    end

    :ok
  rescue
    _ -> :ok
  end

  # Parse tmux control mode output lines
  defp parse_control_line(line) do
    case String.split(line, " ", parts: 3) do
      ["%output", pane, content] -> {:output, pane, content}
      ["%begin" | _] -> :begin
      ["%end" | _] -> :end
      ["%exit" | _] -> :exit
      _ -> :unknown
    end
  end

  # Decode tmux octal-escaped sequences (e.g., \033 -> ESC)
  defp decode_octal(str) do
    Regex.replace(~r/\\(\d{3})/, str, fn _, octal ->
      <<String.to_integer(octal, 8)::utf8>>
    end)
  end
end
