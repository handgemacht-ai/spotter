defmodule SpotterWeb.SessionHookControllerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Observability.FlowHub
  alias Spotter.Transcripts.{Project, Session}

  @endpoint SpotterWeb.Endpoint

  @valid_traceparent "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
  @malformed_traceparent "not-a-valid-traceparent"

  setup do
    Sandbox.checkout(Spotter.Repo)

    if :ets.whereis(FlowHub) != :undefined do
      :ets.delete_all_objects(FlowHub)
    end

    :ok
  end

  defp flush_flow_hub, do: FlowHub.snapshot(minutes: 5)

  defp post_session_start(params, headers \\ []) do
    post_hook("/api/hooks/session-start", params, headers)
  end

  defp post_session_end(params, headers \\ []) do
    post_hook("/api/hooks/session-end", params, headers)
  end

  defp post_hook(path, params, headers) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Phoenix.ConnTest.dispatch(@endpoint, :post, path, params)

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

    test "succeeds with valid traceparent header and FlowHub events have trace_id" do
      {status, body, conn} =
        post_session_start(valid_params(), [{"traceparent", @valid_traceparent}])

      assert status == 200
      assert body["ok"] == true

      trace_id = conn |> Plug.Conn.get_resp_header("x-spotter-trace-id") |> List.first()
      assert trace_id != nil

      %{events: events} = flush_flow_hub()

      received_event =
        Enum.find(events, &(&1.kind == "hook.session_start.received"))

      assert received_event != nil
      assert received_event.trace_id == trace_id
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

    test "broadcasts session_activity :started on success" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, "session_activity")

      params = valid_params()
      {200, %{"ok" => true}, _conn} = post_session_start(params)

      assert_receive {:session_activity, %{session_id: sid, status: :started}}, 1000
      assert sid == params["session_id"]
    end
  end

  describe "POST /api/hooks/waiting-summary" do
    test "returns 400 when session_id missing" do
      {status, body, _conn} =
        post_json("/api/hooks/waiting-summary", %{"transcript_path" => "/some/path.jsonl"})

      assert status == 400
      assert body["error"] =~ "required"
    end

    test "returns 400 when no params" do
      {status, body, _conn} = post_json("/api/hooks/waiting-summary", %{})

      assert status == 400
      assert body["error"] =~ "required"
    end

    test "returns 200 with static summary when session_id provided" do
      {status, body, _conn} =
        post_json("/api/hooks/waiting-summary", %{
          "session_id" => "test-session-123"
        })

      assert status == 200
      assert body["ok"] == true
      assert is_binary(body["summary"])
      assert is_integer(body["input_chars"])
      assert is_map(body["source_window"])
    end

    @tag :live_api
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

    @tag :live_api
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

  describe "POST /api/hooks/session-end" do
    test "succeeds with valid session_id" do
      session_id = Ash.UUID.generate()
      {status, body, _conn} = post_session_end(%{"session_id" => session_id})

      assert status == 200
      assert body["ok"] == true
    end

    test "is idempotent for duplicate end requests" do
      session_id = Ash.UUID.generate()

      {status1, body1, _} = post_session_end(%{"session_id" => session_id, "reason" => "first"})
      {status2, body2, _} = post_session_end(%{"session_id" => session_id, "reason" => "second"})

      assert status1 == 200
      assert body1["ok"] == true
      assert status2 == 200
      assert body2["ok"] == true
    end

    test "duplicate SessionEnd still sets session_ended_at" do
      project =
        Ash.create!(Project, %{name: "idempotent-end", pattern: "^idempotent-end$"})

      session_id = Ash.UUID.generate()

      Ash.create!(Session, %{
        session_id: session_id,
        project_id: project.id,
        cwd: "/home/user/idempotent-end"
      })

      {200, %{"ok" => true}, _} =
        post_session_end(%{"session_id" => session_id, "reason" => "first"})

      first_session =
        Session |> Ash.read!() |> Enum.find(&(&1.session_id == session_id))

      first_ended_at = first_session.session_ended_at
      assert first_ended_at != nil

      Process.sleep(10)

      {200, %{"ok" => true}, _} =
        post_session_end(%{"session_id" => session_id, "reason" => "second"})

      second_session =
        Session |> Ash.read!() |> Enum.find(&(&1.session_id == session_id))

      assert second_session.session_ended_at != nil
    end

    test "handles unknown session without crashing" do
      {status, body, _conn} =
        post_session_end(%{"session_id" => Ash.UUID.generate()})

      assert status == 200
      assert body["ok"] == true
    end

    test "marks an existing session as ended" do
      project =
        Ash.create!(Project, %{name: "session-end-project", pattern: "^session-end-project$"})

      session_id = Ash.UUID.generate()

      Ash.create!(Session, %{
        session_id: session_id,
        project_id: project.id,
        cwd: "/home/user/session-end-project"
      })

      {status, body, _conn} =
        post_session_end(%{"session_id" => session_id, "reason" => "clear"})

      assert status == 200
      assert body["ok"] == true

      ended_session =
        Session
        |> Ash.read!()
        |> Enum.find(&(&1.session_id == session_id))

      assert ended_session.session_ended_at != nil
    end

    test "returns 400 for missing session_id" do
      {status, body, _conn} = post_session_end(%{})

      assert status == 400
      assert body["error"] =~ "session_id is required"
    end

    test "succeeds with valid traceparent header" do
      {status, body, conn} =
        post_session_end(
          %{"session_id" => Ash.UUID.generate()},
          [{"traceparent", @valid_traceparent}]
        )

      assert status == 200
      assert body["ok"] == true
      assert Plug.Conn.get_resp_header(conn, "x-spotter-trace-id") != []
    end
  end
end
