defmodule Spotter.Services.ProjectPeriodRollupPackTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.ProjectPeriodRollupPack

  describe "build/3" do
    test "output sessions contain session_ended_at key" do
      project = %{id: "proj-1", name: "test", timezone: "UTC"}

      sessions = [
        %{
          session_id: "sess-1",
          session_ended_at: ~U[2026-03-06 12:00:00Z],
          commit_hashes: ["abc123"],
          distilled_summary: "Did stuff"
        }
      ]

      pack =
        ProjectPeriodRollupPack.build(project, sessions,
          bucket_kind: :daily,
          bucket_start_date: ~D[2026-03-06]
        )

      [session_entry] = pack.sessions
      assert Map.has_key?(session_entry, :session_ended_at)
      refute Map.has_key?(session_entry, :hook_ended_at)
      assert session_entry.session_ended_at == ~U[2026-03-06 12:00:00Z]
    end
  end
end
