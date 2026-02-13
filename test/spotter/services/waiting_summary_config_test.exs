defmodule Spotter.Services.WaitingSummaryConfigTest do
  use Spotter.DataCase

  alias Spotter.Config.{Runtime, Setting}

  describe "configured_model via DB override" do
    test "DB override for summary_model is used" do
      Ash.create!(Setting, %{key: "summary_model", value: "claude-opus-4"})

      # generate/2 calls configured_model internally; we verify by checking
      # that the module resolves without error (actual LLM call will fail
      # without API key, but the config path is exercised)
      {model, :db} = Runtime.summary_model()
      assert model == "claude-opus-4"
    end

    test "env var drives value when DB absent" do
      System.put_env("SPOTTER_SUMMARY_MODEL", "env-model")
      on_exit(fn -> System.delete_env("SPOTTER_SUMMARY_MODEL") end)

      {model, :env} = Runtime.summary_model()
      assert model == "env-model"
    end
  end

  describe "configured_budget via DB override" do
    test "DB override for summary_token_budget is used" do
      Ash.create!(Setting, %{key: "summary_token_budget", value: "9000"})

      {budget, :db} = Runtime.summary_token_budget()
      assert budget == 9000
    end

    test "env var drives value when DB absent" do
      System.put_env("SPOTTER_SUMMARY_TOKEN_BUDGET", "7000")
      on_exit(fn -> System.delete_env("SPOTTER_SUMMARY_TOKEN_BUDGET") end)

      {budget, :env} = Runtime.summary_token_budget()
      assert budget == 7000
    end
  end
end
