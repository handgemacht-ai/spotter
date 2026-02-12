defmodule SpotterWeb.SessionHookControllerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox

  @endpoint SpotterWeb.Endpoint

  @valid_traceparent "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
  @malformed_traceparent "not-a-valid-traceparent"

  setup do
    Sandbox.checkout(Spotter.Repo)
    :ok
  end

  defp post_session_start(params, headers \\ []) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Phoenix.ConnTest.dispatch(@endpoint, :post, "/api/hooks/session-start", params)

    {conn.status, Jason.decode!(conn.resp_body), conn}
  end

  defp valid_params do
    %{
      "session_id" => Ash.UUID.generate(),
      "pane_id" => "%1",
      "cwd" => "/home/user/project"
    }
  end

  describe "POST /api/hooks/session-start" do
    test "succeeds with valid params" do
      {status, body, _conn} = post_session_start(valid_params())

      assert status == 200
      assert body["ok"] == true
    end

    test "returns 400 for missing session_id" do
      {status, body, _conn} = post_session_start(%{"pane_id" => "%1"})

      assert status == 400
      assert body["error"] =~ "required"
    end

    test "returns 400 for missing pane_id" do
      {status, body, _conn} =
        post_session_start(%{"session_id" => Ash.UUID.generate()})

      assert status == 400
      assert body["error"] =~ "required"
    end

    test "succeeds with valid traceparent header" do
      {status, body, conn} =
        post_session_start(valid_params(), [{"traceparent", @valid_traceparent}])

      assert status == 200
      assert body["ok"] == true
      assert Plug.Conn.get_resp_header(conn, "x-spotter-trace-id") != []
    end

    test "succeeds with malformed traceparent header" do
      {status, body, _conn} =
        post_session_start(valid_params(), [{"traceparent", @malformed_traceparent}])

      assert status == 200
      assert body["ok"] == true
    end

    test "succeeds without traceparent header" do
      {status, body, _conn} = post_session_start(valid_params())

      assert status == 200
      assert body["ok"] == true
    end
  end
end
