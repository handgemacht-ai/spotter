defmodule SpotterWeb.McpNoApiKeyTest do
  @moduledoc """
  Verifies that the MCP plug handles requests gracefully when no
  Anthropic API key is configured. The plug must not crash — it should
  either serve the request normally (for non-LLM operations like tool
  listing) or return a clear error.
  """
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox

  @endpoint SpotterWeb.Endpoint

  setup do
    Sandbox.checkout(Spotter.Repo)

    # Ensure no Anthropic key is set
    refute System.get_env("ANTHROPIC_API_KEY"),
           "Test must run without ANTHROPIC_API_KEY"

    refute System.get_env("SPOTTER_ANTHROPIC_API_KEY"),
           "Test must run without SPOTTER_ANTHROPIC_API_KEY"

    :ok
  end

  describe "MCP plug without API key" do
    test "initialize succeeds without API key" do
      conn =
        mcp_post(
          json_rpc(
            "initialize",
            %{
              "protocolVersion" => "2024-11-05",
              "capabilities" => %{},
              "clientInfo" => %{"name" => "test", "version" => "1.0"}
            },
            1
          )
        )

      assert conn.status == 200

      body = Jason.decode!(conn.resp_body)
      assert body["jsonrpc"] == "2.0"
      assert body["result"]["serverInfo"]
    end

    test "tools/list succeeds without API key" do
      # First initialize to get a session
      init_conn =
        mcp_post(
          json_rpc(
            "initialize",
            %{
              "protocolVersion" => "2024-11-05",
              "capabilities" => %{},
              "clientInfo" => %{"name" => "test", "version" => "1.0"}
            },
            1
          )
        )

      session_id = get_mcp_session_id(init_conn)

      # Then list tools
      conn = mcp_post(json_rpc("tools/list", %{}, 2), session_id)

      assert conn.status == 200

      body = Jason.decode!(conn.resp_body)
      assert body["jsonrpc"] == "2.0"
      assert is_list(body["result"]["tools"])
    end

    test "GET /api/mcp without SSE returns 204 (not crash)" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> Phoenix.ConnTest.dispatch(@endpoint, :get, "/api/mcp")

      # Should return 204 (no content), not a 500 crash
      assert conn.status == 204
    end
  end

  # Helpers

  defp mcp_post(body, session_id \\ nil) do
    conn = Phoenix.ConnTest.build_conn()
    conn = Plug.Conn.put_req_header(conn, "content-type", "application/json")
    conn = Plug.Conn.put_req_header(conn, "accept", "application/json")

    conn =
      if session_id do
        Plug.Conn.put_req_header(conn, "mcp-session-id", session_id)
      else
        conn
      end

    Phoenix.ConnTest.dispatch(conn, @endpoint, :post, "/api/mcp", Jason.encode!(body))
  end

  defp json_rpc(method, params, id) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    }
  end

  defp get_mcp_session_id(conn) do
    conn
    |> Plug.Conn.get_resp_header("mcp-session-id")
    |> List.first()
  end
end
