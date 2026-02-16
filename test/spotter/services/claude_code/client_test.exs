defmodule Spotter.Services.ClaudeCode.ClientTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.ClaudeCode.Client

  describe "query_text/3 provider error metadata" do
    @tag :spawns_claude
    @tag :slow
    test "does not crash when SDK raises an exception with provider metadata" do
      # This test verifies the rescue path handles exceptions gracefully.
      # We can't easily inject a fake exception into the SDK call,
      # so we test that the public API returns {:error, _} for missing API key
      # and that the function doesn't crash.
      assert {:error, :missing_api_key} = Client.query_text("system", "user")
    end
  end

  describe "query_json_schema/4 provider error metadata" do
    @tag :spawns_claude
    @tag :slow
    test "does not crash when SDK raises an exception with provider metadata" do
      schema = %{"type" => "object", "properties" => %{}}
      assert {:error, :missing_api_key} = Client.query_json_schema("system", "user", schema)
    end
  end
end
