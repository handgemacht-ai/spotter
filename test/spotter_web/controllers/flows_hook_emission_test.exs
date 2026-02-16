defmodule SpotterWeb.FlowsHookEmissionTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Observability.FlowEvent
  alias Spotter.Observability.FlowHub
  alias Spotter.Transcripts.{Project, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    Sandbox.checkout(Spotter.Repo)

    if :ets.whereis(FlowHub) != :undefined do
      :ets.delete_all_objects(FlowHub)
    end

    Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

    project = Ash.create!(Project, %{name: "test-flows", pattern: "^test-flows"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    %{session: session, project: project}
  end

  defp post_json(path, params, headers \\ []) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Phoenix.ConnTest.dispatch(@endpoint, :post, path, params)

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp valid_hash, do: String.duplicate("a", 40)

  # Collect all error events emitted in a block and assert none have empty payloads
  defp assert_error_payloads_non_empty(events) do
    error_events = Enum.filter(events, &String.ends_with?(&1.kind, ".error"))

    for event <- error_events do
      assert event.payload != %{},
             "Expected non-empty payload for #{event.kind}, got: #{inspect(event.payload)}"
    end
  end

  describe "commit_event hook" do
    test "emits hook.commit_event.received and hook.commit_event.ok", %{session: session} do
      {201, _body} =
        post_json("/api/hooks/commit-event", %{
          "session_id" => session.session_id,
          "new_commit_hashes" => [valid_hash()]
        })

      assert_receive {:flow_event, %FlowEvent{kind: "hook.commit_event.received"}}, 1000
      assert_receive {:flow_event, %FlowEvent{kind: "hook.commit_event.ok"}}, 1000
    end

    test "emits structured error payload on invalid format", %{session: session} do
      {400, _body} =
        post_json("/api/hooks/commit-event", %{
          "session_id" => session.session_id,
          "new_commit_hashes" => ["not-a-hash"]
        })

      assert_receive {:flow_event, %FlowEvent{kind: "hook.commit_event.received"}}, 1000

      assert_receive {:flow_event, %FlowEvent{kind: "hook.commit_event.error"} = event},
                     1000

      assert event.payload["error.type"] == "invalid_format"
      assert event.payload["error.message"] == "invalid commit hash format"
      assert event.payload["http.status_code"] == 400
      assert event.payload["invalid_count"] == 1
      assert is_binary(event.payload["error.source"])
      assert is_binary(event.payload["hook_event"])
      assert is_binary(event.payload["hook_script"])
    end

    test "emits structured error payload on too many hashes", %{session: session} do
      hashes = for _ <- 1..51, do: valid_hash()

      {400, _body} =
        post_json("/api/hooks/commit-event", %{
          "session_id" => session.session_id,
          "new_commit_hashes" => hashes
        })

      assert_receive {:flow_event, %FlowEvent{kind: "hook.commit_event.error"} = event},
                     1000

      assert event.payload["error.type"] == "too_many_hashes"
      assert event.payload["hash_count"] == 51
      assert event.payload["max_hashes"] == 50
      assert event.payload["http.status_code"] == 400
    end

    test "emits structured error payload on missing required fields", _context do
      {400, _body} = post_json("/api/hooks/commit-event", %{"bad" => "params"})

      assert_receive {:flow_event, %FlowEvent{kind: "hook.commit_event.error"} = event},
                     1000

      assert event.payload["error.type"] == "invalid_params"
      assert is_binary(event.payload["reason"])
      assert event.payload["reason"] != ""
      assert event.payload["http.status_code"] == 400
    end

    test "emits oban.enqueued events for jobs", %{session: session} do
      {201, _body} =
        post_json("/api/hooks/commit-event", %{
          "session_id" => session.session_id,
          "new_commit_hashes" => [valid_hash()]
        })

      # Should receive at least one oban.enqueued event (enrichment, heatmap, etc.)
      assert_receive {:flow_event, %FlowEvent{kind: "oban.enqueued"}}, 1000
    end

    test "includes flow keys with session and commit", %{session: session} do
      hash = valid_hash()

      {201, _body} =
        post_json("/api/hooks/commit-event", %{
          "session_id" => session.session_id,
          "new_commit_hashes" => [hash]
        })

      assert_receive {:flow_event, %FlowEvent{kind: "hook.commit_event.received"} = event},
                     1000

      assert "session:#{session.session_id}" in event.flow_keys
      assert "commit:#{hash}" in event.flow_keys
    end
  end

  describe "session_start hook" do
    test "emits hook.session_start.received and ok", %{session: session} do
      {200, _body} =
        post_json("/api/hooks/session-start", %{
          "session_id" => session.session_id,
          "pane_id" => "test-pane-123"
        })

      assert_receive {:flow_event, %FlowEvent{kind: "hook.session_start.received"}}, 1000
      assert_receive {:flow_event, %FlowEvent{kind: "hook.session_start.ok"}}, 1000
    end
  end

  describe "session_end hook" do
    test "emits hook.session_end.received and ok", %{session: session} do
      {200, _body} =
        post_json("/api/hooks/session-end", %{
          "session_id" => session.session_id
        })

      assert_receive {:flow_event, %FlowEvent{kind: "hook.session_end.received"}}, 1000
      assert_receive {:flow_event, %FlowEvent{kind: "hook.session_end.ok"}}, 1000
    end

    test "emits structured error payload on missing session_id", _context do
      {400, _body} = post_json("/api/hooks/session-end", %{"bad" => "params"})

      assert_receive {:flow_event, %FlowEvent{kind: "hook.session_end.error"} = event},
                     1000

      assert event.payload != %{}
      assert event.payload["error.type"] == "invalid_params"
      assert is_binary(event.payload["error.message"])
      assert event.payload["http.status_code"] == 400
      assert is_binary(event.payload["error.source"])
    end
  end

  describe "error payload guardrail" do
    test "all error events in this module have non-empty payloads", %{session: session} do
      # Trigger multiple error scenarios
      post_json("/api/hooks/commit-event", %{"bad" => "params"})
      post_json("/api/hooks/session-end", %{"bad" => "params"})

      post_json("/api/hooks/commit-event", %{
        "session_id" => session.session_id,
        "new_commit_hashes" => ["not-valid"]
      })

      # Give events time to arrive
      Process.sleep(200)

      events = collect_all_events()
      assert_error_payloads_non_empty(events)
    end
  end

  defp collect_all_events do
    collect_all_events([])
  end

  defp collect_all_events(acc) do
    receive do
      {:flow_event, %FlowEvent{} = event} -> collect_all_events([event | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end
