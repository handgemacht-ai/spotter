defmodule Spotter.Services.WaitingSummaryBudgetTest do
  use ExUnit.Case, async: false

  @moduletag :live_api

  alias Spotter.Services.WaitingSummary

  @fixtures_dir "test/fixtures/transcripts"
  @env_key "SPOTTER_SUMMARY_TOKEN_BUDGET"

  setup do
    original = System.get_env(@env_key)

    on_exit(fn ->
      if original, do: System.put_env(@env_key, original), else: System.delete_env(@env_key)
    end)

    :ok
  end

  describe "configured_budget env parsing" do
    @describetag :spawns_claude
    test "missing env uses default budget without crash" do
      System.delete_env(@env_key)
      path = Path.join(@fixtures_dir, "short.jsonl")

      assert {:ok, result} = WaitingSummary.generate(path)
      assert is_binary(result.summary)
    end

    test "invalid string env uses default budget without crash" do
      System.put_env(@env_key, "bad")
      path = Path.join(@fixtures_dir, "short.jsonl")

      assert {:ok, result} = WaitingSummary.generate(path)
      assert is_binary(result.summary)
    end

    test "zero env uses default budget without crash" do
      System.put_env(@env_key, "0")
      path = Path.join(@fixtures_dir, "short.jsonl")

      assert {:ok, result} = WaitingSummary.generate(path)
      assert is_binary(result.summary)
    end

    test "negative env uses default budget without crash" do
      System.put_env(@env_key, "-100")
      path = Path.join(@fixtures_dir, "short.jsonl")

      assert {:ok, result} = WaitingSummary.generate(path)
      assert is_binary(result.summary)
    end

    test "valid positive env is honored" do
      System.put_env(@env_key, "100")
      path = Path.join(@fixtures_dir, "short.jsonl")

      assert {:ok, result} = WaitingSummary.generate(path)
      assert is_binary(result.summary)
      # With a small budget, input_chars should be limited
      assert result.input_chars <= 200
    end
  end
end
