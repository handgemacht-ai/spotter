defmodule SpotterWeb.TerminalChannel do
  @moduledoc """
  Phoenix Channel for streaming tmux pane output to xterm.js terminals.

  Connects to tmux control mode for real-time output and forwards
  user input back to the tmux pane.
  """
  use Phoenix.Channel

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Observability.ErrorReport
  alias Spotter.Services.Tmux
  alias Spotter.Services.TmuxOutput

  @impl true
  def join("terminal:debug", _params, socket) do
    span_event("spotter.channel.join", %{
      "spotter.channel.topic" => "terminal:debug",
      "spotter.mode" => "debug"
    })

    send(self(), :start_debug_shell)
    {:ok, %{initial_content: ""}, assign(socket, :mode, :debug)}
  end

  def join("terminal:" <> pane_id, _params, socket) do
    span_event("spotter.channel.join", %{
      "spotter.pane_id" => pane_id,
      "spotter.channel.topic" => "terminal:#{pane_id}",
      "spotter.mode" => "tmux"
    })

    if Tmux.pane_exists?(pane_id) do
      send(self(), :start_streaming)

      initial_content =
        case Tmux.capture_pane(pane_id) do
          {:ok, content} -> TmuxOutput.prepare_for_xterm(content)
          _ -> ""
        end

      {:ok, %{initial_content: initial_content}, assign(socket, pane_id: pane_id, mode: :tmux)}
    else
      span_error("pane_not_found")
      {:error, %{reason: "pane not found"}}
    end
  end

  @impl true
  def handle_info(:start_debug_shell, socket) do
    span_event("spotter.channel.stream_start", %{"spotter.mode" => "debug"})
    shell = System.find_executable("bash") || System.find_executable("sh")

    port =
      Port.open(
        {:spawn_executable, System.find_executable("script")},
        [
          :binary,
          :exit_status,
          args: ["-q", "-c", shell, "/dev/null"],
          env: [
            {~c"TERM", ~c"xterm-256color"},
            {~c"COLUMNS", ~c"80"},
            {~c"LINES", ~c"24"}
          ]
        ]
      )

    {:noreply, assign(socket, :port, port)}
  end

  def handle_info(:start_streaming, socket) do
    pane_id = socket.assigns.pane_id

    span_event("spotter.channel.stream_start", %{
      "spotter.pane_id" => pane_id,
      "spotter.mode" => "tmux"
    })

    port =
      Port.open(
        {:spawn_executable, System.find_executable("tmux")},
        [
          :binary,
          :exit_status,
          args: ["-C", "attach-session", "-t", pane_id, "-r"]
        ]
      )

    {:noreply, assign(socket, port: port, buffer: "")}
  end

  def handle_info({port, {:data, data}}, %{assigns: %{port: port, mode: :debug}} = socket) do
    push(socket, "output", %{data: data})
    {:noreply, socket}
  end

  def handle_info({port, {:data, data}}, %{assigns: %{port: port}} = socket) do
    # Port data arrives in arbitrary chunks - buffer incomplete lines
    buffered = socket.assigns.buffer <> data
    {lines, remaining} = split_complete_lines(buffered)

    # tmux control mode outputs lines like %output %<pane_id> <data>
    # Only forward output from the target pane, ignore other panes in the session
    target_pane = socket.assigns.pane_id

    Enum.each(lines, fn line ->
      case parse_control_line(line) do
        {:output, ^target_pane, content} ->
          push(socket, "output", %{data: decode_output(content)})

        _ ->
          :ok
      end
    end)

    {:noreply, assign(socket, :buffer, remaining)}
  end

  def handle_info(
        {port, {:exit_status, _status}},
        %{assigns: %{port: port, mode: :debug}} = socket
      ) do
    span_event("spotter.channel.stream_exit", %{"spotter.mode" => "debug"})
    Logger.info("Debug shell exited")
    {:stop, :normal, socket}
  end

  def handle_info({port, {:exit_status, _status}}, %{assigns: %{port: port}} = socket) do
    span_event("spotter.channel.stream_exit", %{
      "spotter.pane_id" => socket.assigns.pane_id,
      "spotter.mode" => "tmux"
    })

    Logger.info("tmux control mode exited for pane #{socket.assigns.pane_id}")
    {:stop, :normal, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_in("input", %{"data" => data}, %{assigns: %{mode: :debug}} = socket) do
    span_event("spotter.channel.input", %{"spotter.mode" => "debug"})
    Port.command(socket.assigns.port, data)
    {:noreply, socket}
  end

  def handle_in("input", %{"data" => data}, socket) do
    span_event("spotter.channel.input", %{
      "spotter.pane_id" => socket.assigns.pane_id,
      "spotter.mode" => "tmux"
    })

    Tmux.send_keys(socket.assigns.pane_id, data)
    {:noreply, socket}
  end

  def handle_in("resize", _params, %{assigns: %{mode: :debug}} = socket) do
    span_event("spotter.channel.resize", %{"spotter.mode" => "debug"})
    {:noreply, socket}
  end

  def handle_in("resize", %{"cols" => cols, "rows" => rows}, socket) do
    pane_id = socket.assigns.pane_id

    span_event("spotter.channel.resize", %{
      "spotter.pane_id" => pane_id,
      "spotter.mode" => "tmux"
    })

    System.cmd(
      "tmux",
      ["resize-pane", "-t", pane_id, "-x", to_string(cols), "-y", to_string(rows)],
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

  # Split into complete lines (ending with \n) and a remaining partial line
  defp split_complete_lines(data) do
    case String.split(data, "\n", trim: false) do
      [only] -> {[], only}
      parts -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
    end
  end

  defp decode_output(str) do
    decoded = decode_octal(str)

    if String.valid?(decoded),
      do: decoded,
      else: :unicode.characters_to_binary(decoded, :latin1, :utf8)
  end

  defp decode_octal(str) do
    Regex.replace(~r/\\(\d{3})/, str, fn _, octal ->
      <<String.to_integer(octal, 8)>>
    end)
  end

  defp span_event(name, attrs) do
    Tracer.add_event(name, Map.to_list(attrs))
  rescue
    _error -> :ok
  end

  defp span_error(reason) do
    ErrorReport.set_trace_error("channel_error", reason, "channels.terminal_channel")
  rescue
    _error -> :ok
  end
end
