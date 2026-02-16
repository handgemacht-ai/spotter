defmodule SpotterWeb.SpotterMcpPlug do
  @moduledoc """
  MCP endpoint plug that wraps `AshAi.Mcp.Router` with OpenTelemetry tracing.

  Mounted at `/api/mcp` and exposes Spotter review tools to Claude Code.
  """

  @behaviour Plug

  alias Spotter.Transcripts.Sessions
  alias SpotterWeb.OtelTraceHelpers

  require Logger
  require OtelTraceHelpers

  # AshAi.Mcp.Router is conditionally compiled (Code.ensure_loaded? guard),
  # so we reference it via a module attribute to avoid credo nested-module warnings.
  @mcp_router AshAi.Mcp.Router

  @mcp_opts [
    otp_app: :spotter,
    mcp_name: "Spotter",
    mcp_server_version: "1.0.0",
    tools: [:list_sessions, :list_review_annotations, :resolve_annotation]
  ]

  @impl true
  def init(_opts) do
    @mcp_router.init(@mcp_opts)
  end

  # Rate-limit key for GET /api/mcp debug logging (once per 60s)
  @fingerprint_log_key {__MODULE__, :last_mcp_fingerprint_log_at_ms}
  @fingerprint_log_interval_ms 60_000

  @impl true
  def call(conn, router_opts) do
    session_id_present = Plug.Conn.get_req_header(conn, "mcp-session-id") != []

    jsonrpc_method =
      case {conn.method, conn.body_params} do
        {"POST", %{"method" => method}} when is_binary(method) -> method
        _ -> nil
      end

    tool_name =
      case conn.body_params do
        %{"method" => "tools/call", "params" => %{"name" => name}} when is_binary(name) -> name
        _ -> nil
      end

    accept_headers = Plug.Conn.get_req_header(conn, "accept")
    accept_str = Enum.join(accept_headers, ",")
    accepts_sse = Enum.any?(accept_headers, &String.contains?(&1, "text/event-stream"))
    peer_ip = format_peer_ip(conn.remote_ip)
    user_agent = conn |> Plug.Conn.get_req_header("user-agent") |> List.first("")

    attrs =
      %{
        "http.method" => conn.method,
        "http.target" => conn.request_path,
        "mcp.session_id_present" => session_id_present,
        "net.peer.ip" => peer_ip,
        "http.request.header.accept" => accept_str,
        "http.user_agent" => user_agent,
        "mcp.http_accepts_sse" => accepts_sse,
        "mcp.http.method" => conn.method,
        "mcp.http.target" => conn.request_path
      }
      |> maybe_put("mcp.jsonrpc_method", jsonrpc_method)
      |> maybe_put("mcp.tool_name", tool_name)

    maybe_log_get_fingerprint(conn.method, peer_ip, accepts_sse, accept_str, user_agent)

    conn = resolve_mcp_project_scope(conn, attrs)

    case {conn.method, accepts_sse} do
      {"GET", true} ->
        handle_sse_get(conn, attrs)

      {"GET", false} ->
        OtelTraceHelpers.with_span "spotter.mcp.http", attrs do
          conn
          |> OtelTraceHelpers.put_trace_response_header()
          |> Plug.Conn.send_resp(204, "")
        end

      _ ->
        OtelTraceHelpers.with_span "spotter.mcp.http", attrs do
          conn
          |> OtelTraceHelpers.put_trace_response_header()
          |> call_router_with_rescue(router_opts, tool_name)
        end
    end
  end

  defp resolve_mcp_project_scope(conn, _attrs) do
    require OpenTelemetry.Tracer, as: Tracer

    case Plug.Conn.get_req_header(conn, "x-spotter-project-dir") do
      [project_dir | _] when project_dir != "" ->
        Tracer.set_attribute("spotter.mcp.scope.project_dir_present", true)

        case Sessions.resolve_project_by_cwd(project_dir) do
          {:ok, project} ->
            Tracer.set_attribute("spotter.mcp.scope.project_id", project.id)

            Ash.PlugHelpers.set_context(conn, %{
              spotter_mcp_scope: %{project_id: project.id, project_dir: project_dir}
            })

          {:error, reason} ->
            error_str = inspect(reason)
            Tracer.set_attribute("spotter.mcp.scope.error", error_str)

            Ash.PlugHelpers.set_context(conn, %{spotter_mcp_scope_error: error_str})
        end

      _ ->
        Tracer.set_attribute("spotter.mcp.scope.project_dir_present", false)
        Tracer.set_attribute("spotter.mcp.scope.error", "missing_header")

        Ash.PlugHelpers.set_context(conn, %{spotter_mcp_scope_error: "missing_header"})
    end
  end

  defp call_router_with_rescue(conn, router_opts, tool_name) do
    @mcp_router.call(conn, router_opts)
  rescue
    e ->
      OtelTraceHelpers.set_error(:mcp_request_failed, %{
        "error.message" => Exception.message(e),
        "mcp.tool_name" => tool_name || "unknown",
        "error.source" => "spotter_mcp_plug"
      })

      reraise e, __STACKTRACE__
  end

  defp handle_sse_get(conn, attrs) do
    # Span covers only the handshake + first endpoint event, not the full stream
    conn =
      OtelTraceHelpers.with_span "spotter.mcp.http", attrs do
        host =
          case Plug.Conn.get_req_header(conn, "host") do
            [h | _] -> h
            [] -> "#{conn.host}:#{conn.port}"
          end

        scheme = if conn.scheme == :https, do: "https", else: "http"
        post_url = "#{scheme}://#{host}#{conn.request_path}"

        conn
        |> OtelTraceHelpers.put_trace_response_header()
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.put_resp_header("cache-control", "no-cache")
        |> Plug.Conn.send_chunked(200)
        |> send_sse_chunk("event: endpoint\ndata: #{Jason.encode!(%{"url" => post_url})}\n\n")
      end

    sse_keepalive_loop(conn)
  end

  defp sse_keepalive_loop(conn) do
    config = Application.get_env(:spotter, __MODULE__, [])
    keepalive_ms = config[:sse_keepalive_ms] || 15_000
    max_duration_ms = config[:sse_max_duration_ms] || :infinity
    started_at = System.monotonic_time(:millisecond)

    do_sse_keepalive_loop(conn, keepalive_ms, max_duration_ms, started_at)
  end

  defp do_sse_keepalive_loop(conn, keepalive_ms, max_duration_ms, started_at) do
    Process.sleep(keepalive_ms)

    elapsed = System.monotonic_time(:millisecond) - started_at

    if is_integer(max_duration_ms) and elapsed >= max_duration_ms do
      conn
    else
      case Plug.Conn.chunk(conn, ": keepalive\n\n") do
        {:ok, conn} ->
          do_sse_keepalive_loop(conn, keepalive_ms, max_duration_ms, started_at)

        {:error, _reason} ->
          conn
      end
    end
  end

  defp send_sse_chunk(conn, data) do
    case Plug.Conn.chunk(conn, data) do
      {:ok, conn} -> conn
      {:error, _} -> conn
    end
  end

  defp format_peer_ip(remote_ip) do
    case :inet.ntoa(remote_ip) do
      {:error, _} -> inspect(remote_ip)
      charlist -> to_string(charlist)
    end
  end

  defp maybe_log_get_fingerprint("GET", peer_ip, accepts_sse, accept, user_agent) do
    now = System.monotonic_time(:millisecond)

    last =
      try do
        :persistent_term.get(@fingerprint_log_key)
      rescue
        ArgumentError -> 0
      end

    if now - last >= @fingerprint_log_interval_ms do
      :persistent_term.put(@fingerprint_log_key, now)

      Logger.debug(
        "MCP GET fingerprint: peer_ip=#{peer_ip} accepts_sse=#{accepts_sse} accept=#{accept} user_agent=#{user_agent}"
      )
    end
  end

  defp maybe_log_get_fingerprint(_method, _peer_ip, _accepts_sse, _accept, _user_agent), do: :ok

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
