defmodule Spotter.Services.LlmCredentialsTest do
  use ExUnit.Case, async: false

  alias Spotter.Services.LlmCredentials

  setup do
    prev_env = System.get_env("SPOTTER_ANTHROPIC_API_KEY")

    on_exit(fn ->
      if prev_env,
        do: System.put_env("SPOTTER_ANTHROPIC_API_KEY", prev_env),
        else: System.delete_env("SPOTTER_ANTHROPIC_API_KEY")
    end)

    System.delete_env("SPOTTER_ANTHROPIC_API_KEY")

    :ok
  end

  describe "anthropic_api_key/0" do
    test "returns ok when env var is set" do
      System.put_env("SPOTTER_ANTHROPIC_API_KEY", "sk-ant-test")
      assert {:ok, "sk-ant-test"} = LlmCredentials.anthropic_api_key()
    end

    test "returns error when env var is nil" do
      assert {:error, :missing_api_key} = LlmCredentials.anthropic_api_key()
    end

    test "returns error when env var is empty string" do
      System.put_env("SPOTTER_ANTHROPIC_API_KEY", "")
      assert {:error, :missing_api_key} = LlmCredentials.anthropic_api_key()
    end

    test "returns error when env var is whitespace-only" do
      System.put_env("SPOTTER_ANTHROPIC_API_KEY", "   ")
      assert {:error, :missing_api_key} = LlmCredentials.anthropic_api_key()
    end
  end
end
