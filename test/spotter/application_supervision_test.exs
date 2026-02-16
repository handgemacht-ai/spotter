defmodule Spotter.ApplicationSupervisionTest do
  use ExUnit.Case, async: true

  describe "Spotter.Supervisor children" do
    test "includes TranscriptFileLinks as a supervised child" do
      children = Supervisor.which_children(Spotter.Supervisor)

      match =
        Enum.find(children, fn {id, _pid, _type, _modules} ->
          id == Spotter.Services.TranscriptFileLinks
        end)

      assert {Spotter.Services.TranscriptFileLinks, pid, :worker, _modules} = match
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
  end
end
