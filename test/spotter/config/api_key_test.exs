defmodule Spotter.Config.ApiKeyTest do
  @moduledoc """
  Tests the API key availability helper that Oban workers and other
  components should use to check for Anthropic API key presence.
  """
  use ExUnit.Case, async: true

  describe "Spotter.Config.anthropic_api_key/0" do
    test "returns nil when no Anthropic API key env vars are set" do
      # Ensure clean slate
      original_key = System.get_env("ANTHROPIC_API_KEY")
      original_spotter_key = System.get_env("SPOTTER_ANTHROPIC_API_KEY")

      try do
        System.delete_env("ANTHROPIC_API_KEY")
        System.delete_env("SPOTTER_ANTHROPIC_API_KEY")

        assert is_nil(Spotter.Config.anthropic_api_key())
      after
        if original_key, do: System.put_env("ANTHROPIC_API_KEY", original_key)

        if original_spotter_key,
          do: System.put_env("SPOTTER_ANTHROPIC_API_KEY", original_spotter_key)
      end
    end

    test "returns key from SPOTTER_ANTHROPIC_API_KEY when set" do
      original = System.get_env("SPOTTER_ANTHROPIC_API_KEY")

      try do
        System.put_env("SPOTTER_ANTHROPIC_API_KEY", "sk-test-123")
        assert Spotter.Config.anthropic_api_key() == "sk-test-123"
      after
        if original,
          do: System.put_env("SPOTTER_ANTHROPIC_API_KEY", original),
          else: System.delete_env("SPOTTER_ANTHROPIC_API_KEY")
      end
    end

    test "SPOTTER_ANTHROPIC_API_KEY takes precedence over ANTHROPIC_API_KEY" do
      original_spotter = System.get_env("SPOTTER_ANTHROPIC_API_KEY")
      original_plain = System.get_env("ANTHROPIC_API_KEY")

      try do
        System.put_env("SPOTTER_ANTHROPIC_API_KEY", "sk-spotter-key")
        System.put_env("ANTHROPIC_API_KEY", "sk-plain-key")
        assert Spotter.Config.anthropic_api_key() == "sk-spotter-key"
      after
        if original_spotter,
          do: System.put_env("SPOTTER_ANTHROPIC_API_KEY", original_spotter),
          else: System.delete_env("SPOTTER_ANTHROPIC_API_KEY")

        if original_plain,
          do: System.put_env("ANTHROPIC_API_KEY", original_plain),
          else: System.delete_env("ANTHROPIC_API_KEY")
      end
    end

    test "falls back to ANTHROPIC_API_KEY when SPOTTER_ variant is not set" do
      original_spotter = System.get_env("SPOTTER_ANTHROPIC_API_KEY")
      original_plain = System.get_env("ANTHROPIC_API_KEY")

      try do
        System.delete_env("SPOTTER_ANTHROPIC_API_KEY")
        System.put_env("ANTHROPIC_API_KEY", "sk-fallback-key")
        assert Spotter.Config.anthropic_api_key() == "sk-fallback-key"
      after
        if original_spotter,
          do: System.put_env("SPOTTER_ANTHROPIC_API_KEY", original_spotter),
          else: System.delete_env("SPOTTER_ANTHROPIC_API_KEY")

        if original_plain,
          do: System.put_env("ANTHROPIC_API_KEY", original_plain),
          else: System.delete_env("ANTHROPIC_API_KEY")
      end
    end
  end

  describe "Spotter.Config.anthropic_api_key?/0" do
    test "returns false when no key is available" do
      original_key = System.get_env("ANTHROPIC_API_KEY")
      original_spotter_key = System.get_env("SPOTTER_ANTHROPIC_API_KEY")

      try do
        System.delete_env("ANTHROPIC_API_KEY")
        System.delete_env("SPOTTER_ANTHROPIC_API_KEY")

        refute Spotter.Config.anthropic_api_key?()
      after
        if original_key, do: System.put_env("ANTHROPIC_API_KEY", original_key)

        if original_spotter_key,
          do: System.put_env("SPOTTER_ANTHROPIC_API_KEY", original_spotter_key)
      end
    end

    test "returns true when a key is available" do
      original = System.get_env("SPOTTER_ANTHROPIC_API_KEY")

      try do
        System.put_env("SPOTTER_ANTHROPIC_API_KEY", "sk-test-123")
        assert Spotter.Config.anthropic_api_key?()
      after
        if original,
          do: System.put_env("SPOTTER_ANTHROPIC_API_KEY", original),
          else: System.delete_env("SPOTTER_ANTHROPIC_API_KEY")
      end
    end
  end
end
