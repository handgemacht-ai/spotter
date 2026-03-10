defmodule SpotterWeb.RouteCleanupTest do
  @moduledoc """
  Integration tests verifying that dual project routes have been removed.

  GIVEN the router no longer defines /projects/:project_id paths for
        file-metrics, telemetry/commands, or telemetry/instructions
  WHEN  a request hits one of those removed paths
  THEN  the response is 404
  """
  use ExUnit.Case, async: true

  @endpoint SpotterWeb.Endpoint

  @tag :slow
  @tag timeout: 5_000
  test "GET /projects/:id/file-metrics returns 404 (route removed)" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> Phoenix.ConnTest.dispatch(
        @endpoint,
        :get,
        "/projects/00000000-0000-0000-0000-000000000001/file-metrics"
      )

    assert conn.status == 404
  end

  @tag :slow
  @tag timeout: 5_000
  test "GET /projects/:id/telemetry/commands returns 404 (route removed)" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> Phoenix.ConnTest.dispatch(
        @endpoint,
        :get,
        "/projects/00000000-0000-0000-0000-000000000001/telemetry/commands"
      )

    assert conn.status == 404
  end

  @tag :slow
  @tag timeout: 5_000
  test "GET /projects/:id/telemetry/instructions returns 404 (route removed)" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> Phoenix.ConnTest.dispatch(
        @endpoint,
        :get,
        "/projects/00000000-0000-0000-0000-000000000001/telemetry/instructions"
      )

    assert conn.status == 404
  end
end
