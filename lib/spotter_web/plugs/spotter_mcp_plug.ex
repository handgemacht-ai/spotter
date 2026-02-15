defmodule SpotterWeb.SpotterMcpPlug do
  @moduledoc """
  MCP endpoint plug that wraps `AshAi.Mcp.Router` with OpenTelemetry tracing.

  Mounted at `/api/mcp` and exposes Spotter review tools to Claude Code.
  """

  @behaviour Plug

  alias SpotterWeb.OtelTraceHelpers

  require OtelTraceHelpers

  # AshAi.Mcp.Router is conditionally compiled (Code.ensure_loaded? guard),
  # so we reference it via a module attribute to avoid credo nested-module warnings.
  @mcp_router AshAi.Mcp.Router

  @mcp_opts [
    otp_app: :spotter,
    mcp_name: "Spotter",
    mcp_server_version: "1.0.0",
    tools: [:list_projects, :list_sessions, :list_review_annotations, :resolve_annotation]
  ]

  @impl true
  def init(_opts) do
    @mcp_router.init(@mcp_opts)
  end

  @impl true
  def call(conn, router_opts) do
    session_id_present = Plug.Conn.get_req_header(conn, "mcp-session-id") != []

    jsonrpc_method =
      case {conn.method, conn.body_params} do
        {"POST", %{"method" => method}} when is_binary(method) -> method
        _ -> nil
      end

    attrs =
      %{
        "http.method" => conn.method,
        "http.target" => conn.request_path,
        "mcp.session_id_present" => session_id_present
      }
      |> maybe_put("mcp.jsonrpc_method", jsonrpc_method)

    OtelTraceHelpers.with_span "spotter.mcp.http", attrs do
      conn
      |> OtelTraceHelpers.put_trace_response_header()
      |> @mcp_router.call(router_opts)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
