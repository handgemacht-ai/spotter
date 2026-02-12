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

  @fixtures_dir "test/fixtures/transcripts"

  defp post_json(path, params) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.dispatch(@endpoint, :post, path, params)
    |> then(fn conn -> {conn.status, Jason.decode!(conn.resp_body), conn} end)
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

  describe "POST /api/hooks/waiting-summary" do
    test "returns 400 when session_id missing" do
      {status, body, _conn} =
        post_json("/api/hooks/waiting-summary", %{"transcript_path" => "/some/path.jsonl"})

      assert status == 400
      assert body["error"] =~ "required"
    end

    test "returns 400 when transcript_path missing" do
      {status, body, _conn} =
        post_json("/api/hooks/waiting-summary", %{"session_id" => "abc"})

      assert status == 400
      assert body["error"] =~ "required"
    end

    test "returns 400 when both fields missing" do
      {status, body, _conn} = post_json("/api/hooks/waiting-summary", %{})

      assert status == 400
      assert body["error"] =~ "required"
    end

    test "returns 200 with fallback summary for missing transcript file" do
      {status, body, _conn} =
        post_json("/api/hooks/waiting-summary", %{
          "session_id" => "test-session-123",
          "transcript_path" => "/nonexistent/path.jsonl"
        })

      assert status == 200
      assert body["ok"] == true
      assert is_binary(body["summary"])
      assert body["summary"] =~ "test-ses"
      assert is_integer(body["input_chars"])
      assert is_map(body["source_window"])
    end

    test "returns 200 with summary for valid transcript" do
      path = Path.absname(Path.join(@fixtures_dir, "short.jsonl"))

      {status, body, _conn} =
        post_json("/api/hooks/waiting-summary", %{
          "session_id" => "55604662-cf2a-4331-851a-ec234028f8ca",
          "transcript_path" => path
        })

      assert status == 200
      assert body["ok"] == true
      assert is_binary(body["summary"])
      assert body["summary"] != ""
      assert is_integer(body["input_chars"])
      assert body["input_chars"] > 0
      assert body["source_window"]["head_messages"] >= 0
      assert body["source_window"]["tail_messages"] >= 0
    end

    test "accepts optional token_budget parameter" do
      path = Path.absname(Path.join(@fixtures_dir, "short.jsonl"))

      {status, body, _conn} =
        post_json("/api/hooks/waiting-summary", %{
          "session_id" => "55604662-cf2a-4331-851a-ec234028f8ca",
          "transcript_path" => path,
          "token_budget" => 200
        })

      assert status == 200
      assert body["ok"] == true
      assert body["input_chars"] <= 200
    end
  end
end
