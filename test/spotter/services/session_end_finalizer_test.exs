defmodule Spotter.Services.SessionEndFinalizerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Services.SessionEndFinalizer
  alias Spotter.Transcripts.{Project, Session}

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "finalizer-test", pattern: "^finalizer-test"})

    %{project: project}
  end

  describe "finalize/3 broadcasts session_activity :finished" do
    test "broadcasts after successful mark_ended", %{project: project} do
      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/finalizer-test",
          cwd: "/home/user/finalizer-project",
          project_id: project.id,
          started_at: DateTime.utc_now()
        })

      Phoenix.PubSub.subscribe(Spotter.PubSub, "session_activity")

      _result = SessionEndFinalizer.finalize(session.session_id)

      assert_receive {:session_activity, %{session_id: sid, status: :finished}}, 1000
      assert sid == session.session_id
    end
  end
end
