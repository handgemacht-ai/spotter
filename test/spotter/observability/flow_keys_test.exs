defmodule Spotter.Observability.FlowKeysTest do
  use ExUnit.Case, async: true

  alias Spotter.Observability.FlowKeys

  test "subagent/1 returns subagent:<id>" do
    assert FlowKeys.subagent("abc") == "subagent:abc"
  end

  test "session/1 returns session:<id>" do
    assert FlowKeys.session("xyz") == "session:xyz"
  end

  test "derive/1 extracts known keys" do
    keys = FlowKeys.derive(%{"session_id" => "s1", "commit_hash" => "c1"})
    assert "session:s1" in keys
    assert "commit:c1" in keys
  end
end
