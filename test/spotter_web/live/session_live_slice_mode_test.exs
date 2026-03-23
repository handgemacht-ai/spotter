defmodule SpotterWeb.SessionLiveSliceModeTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Message, Project, Session, SessionSlice}

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "slice-live", pattern: "^slice"})
    session_id = Ash.UUID.generate()

    session =
      Ash.create!(Session, %{
        session_id: session_id,
        transcript_dir: "/tmp/slice-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    # Create some messages with ordinals and tool_use_ids
    for i <- 0..9 do
      Ash.create!(Message, %{
        uuid: "msg-#{i}",
        type: :assistant,
        role: :assistant,
        content: %{"text" => "Message #{i}"},
        timestamp: DateTime.utc_now() |> DateTime.add(i, :second),
        ordinal: i,
        source_scope: "main",
        record_type: "assistant",
        normalization_status: :full,
        tool_use_id: if(rem(i, 3) == 0, do: "toolu_#{i}", else: nil),
        session_id: session.id
      })
    end

    slice =
      Ash.create!(SessionSlice, %{
        session_id: session.id,
        project_id: project.id,
        title: "Test slice",
        highlight_tool_use_ids: ["toolu_0", "toolu_6"],
        context_before_lines: 1,
        context_after_lines: 1
      })

    %{session: session, session_id: session_id, slice: slice, project: project}
  end

  describe "slice mode activation" do
    test "?slice= param activates slice mode", %{session_id: sid, slice: slice} do
      {:ok, view, html} = live(build_conn(), "/sessions/#{sid}?slice=#{slice.id}")

      assert html =~ "slice"
      assert render(view) =~ slice.title
    end

    test "invalid slice_id shows error flash", %{session_id: sid} do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{sid}?slice=nonexistent-id")

      assert html =~ "error" or html =~ "not found"
    end

    test "slice from different session shows error", %{slice: slice} do
      other_project = Ash.create!(Project, %{name: "other", pattern: "^other"})
      other_session_id = Ash.UUID.generate()

      Ash.create!(Session, %{
        session_id: other_session_id,
        transcript_dir: "/tmp/other",
        cwd: "/tmp/other",
        project_id: other_project.id
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{other_session_id}?slice=#{slice.id}")

      assert html =~ "error" or html =~ "not found"
    end
  end

  describe "slice mode display" do
    test "slice mode shows only highlighted windows", %{session_id: sid, slice: slice} do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{sid}?slice=#{slice.id}")

      # Windows: [0,1] around toolu_0 and [5,7] around toolu_6 (context=1)
      # Messages 2,3,4 should be hidden (between windows)
      refute html =~ "Message 3"
      refute html =~ "Message 4"
    end

    test "clearing slice restores full transcript", %{session_id: sid, slice: slice} do
      {:ok, view, _html} = live(build_conn(), "/sessions/#{sid}?slice=#{slice.id}")

      # Click "Show full transcript" — should push_patch to base URL
      view |> element("[data-action=clear-slice]") |> render_click()

      assert_patched(view, "/sessions/#{sid}")
    end
  end
end
