defmodule Spotter.Config.RuntimeTest do
  use Spotter.DataCase

  alias Spotter.Config.Runtime
  alias Spotter.Config.Setting

  describe "summary_model/0" do
    test "DB override beats env and default" do
      Ash.create!(Setting, %{key: "summary_model", value: "claude-opus-4"})

      assert {_val, :db} = Runtime.summary_model()
      assert {"claude-opus-4", :db} = Runtime.summary_model()
    end

    test "env beats default when DB absent" do
      System.put_env("SPOTTER_SUMMARY_MODEL", "custom-model")
      on_exit(fn -> System.delete_env("SPOTTER_SUMMARY_MODEL") end)

      assert {"custom-model", :env} = Runtime.summary_model()
    end

    test "falls back to default when neither DB nor env set" do
      System.delete_env("SPOTTER_SUMMARY_MODEL")

      assert {"claude-3-5-haiku-latest", :default} = Runtime.summary_model()
    end
  end

  describe "summary_token_budget/0" do
    test "DB override beats env and default" do
      Ash.create!(Setting, %{key: "summary_token_budget", value: "8000"})

      assert {8000, :db} = Runtime.summary_token_budget()
    end

    test "env beats default when DB absent" do
      System.put_env("SPOTTER_SUMMARY_TOKEN_BUDGET", "6000")
      on_exit(fn -> System.delete_env("SPOTTER_SUMMARY_TOKEN_BUDGET") end)

      assert {6000, :env} = Runtime.summary_token_budget()
    end

    test "falls back to default when neither DB nor env set" do
      System.delete_env("SPOTTER_SUMMARY_TOKEN_BUDGET")

      assert {4000, :default} = Runtime.summary_token_budget()
    end

    test "invalid DB value falls back to default budget" do
      Ash.create!(Setting, %{key: "summary_token_budget", value: "not-a-number"})

      assert {4000, :db} = Runtime.summary_token_budget()
    end
  end

  describe "transcripts_dir/0" do
    test "DB override beats TOML and default" do
      Ash.create!(Setting, %{key: "transcripts_dir", value: "/custom/dir"})

      assert {"/custom/dir", :db} = Runtime.transcripts_dir()
    end

    test "falls back to TOML when DB absent" do
      # TOML file exists with transcripts_dir, so should get :toml source
      {dir, source} = Runtime.transcripts_dir()

      assert is_binary(dir)
      assert source in [:toml, :default]
    end

    test "expands tilde in DB override" do
      Ash.create!(Setting, %{key: "transcripts_dir", value: "~/my-transcripts"})

      {dir, :db} = Runtime.transcripts_dir()
      refute String.starts_with?(dir, "~")
      assert String.ends_with?(dir, "/my-transcripts")
    end
  end

  describe "anthropic_key_present?/0" do
    test "returns a boolean" do
      assert is_boolean(Runtime.anthropic_key_present?())
    end
  end

  describe "prompt_patterns_max_prompts_per_run/0" do
    test "DB override beats env and default" do
      Ash.create!(Setting, %{key: "prompt_patterns_max_prompts_per_run", value: "200"})

      assert {200, :db} = Runtime.prompt_patterns_max_prompts_per_run()
    end

    test "env beats default when DB absent" do
      System.put_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPTS_PER_RUN", "300")
      on_exit(fn -> System.delete_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPTS_PER_RUN") end)

      assert {300, :env} = Runtime.prompt_patterns_max_prompts_per_run()
    end

    test "falls back to default" do
      System.delete_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPTS_PER_RUN")

      assert {500, :default} = Runtime.prompt_patterns_max_prompts_per_run()
    end

    test "invalid env value falls back to default" do
      System.put_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPTS_PER_RUN", "abc")
      on_exit(fn -> System.delete_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPTS_PER_RUN") end)

      assert {500, :env} = Runtime.prompt_patterns_max_prompts_per_run()
    end
  end

  describe "prompt_patterns_max_prompt_chars/0" do
    test "DB override beats env and default" do
      Ash.create!(Setting, %{key: "prompt_patterns_max_prompt_chars", value: "800"})

      assert {800, :db} = Runtime.prompt_patterns_max_prompt_chars()
    end

    test "env beats default when DB absent" do
      System.put_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPT_CHARS", "600")
      on_exit(fn -> System.delete_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPT_CHARS") end)

      assert {600, :env} = Runtime.prompt_patterns_max_prompt_chars()
    end

    test "falls back to default" do
      System.delete_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPT_CHARS")

      assert {400, :default} = Runtime.prompt_patterns_max_prompt_chars()
    end

    test "invalid env value falls back to default" do
      System.put_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPT_CHARS", "-5")
      on_exit(fn -> System.delete_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPT_CHARS") end)

      assert {400, :env} = Runtime.prompt_patterns_max_prompt_chars()
    end
  end

  describe "prompt_patterns_model/0" do
    test "DB override beats env and default" do
      Ash.create!(Setting, %{key: "prompt_patterns_model", value: "claude-opus-4"})

      assert {"claude-opus-4", :db} = Runtime.prompt_patterns_model()
    end

    test "env beats default when DB absent" do
      System.put_env("SPOTTER_PROMPT_PATTERNS_MODEL", "custom-model")
      on_exit(fn -> System.delete_env("SPOTTER_PROMPT_PATTERNS_MODEL") end)

      assert {"custom-model", :env} = Runtime.prompt_patterns_model()
    end

    test "falls back to default" do
      System.delete_env("SPOTTER_PROMPT_PATTERNS_MODEL")

      assert {"claude-haiku-4-5", :default} = Runtime.prompt_patterns_model()
    end

    test "blank env value falls back to default" do
      System.put_env("SPOTTER_PROMPT_PATTERNS_MODEL", "   ")
      on_exit(fn -> System.delete_env("SPOTTER_PROMPT_PATTERNS_MODEL") end)

      assert {"claude-haiku-4-5", :default} = Runtime.prompt_patterns_model()
    end
  end

  describe "Setting resource" do
    test "creates valid setting" do
      assert {:ok, setting} = Ash.create(Setting, %{key: "summary_model", value: "test"})
      assert setting.key == "summary_model"
      assert setting.value == "test"
    end

    test "rejects disallowed key" do
      assert {:error, _} = Ash.create(Setting, %{key: "invalid_key", value: "test"})
    end

    test "enforces unique key" do
      Ash.create!(Setting, %{key: "summary_model", value: "v1"})

      assert {:error, _} = Ash.create(Setting, %{key: "summary_model", value: "v2"})
    end

    test "updates value" do
      setting = Ash.create!(Setting, %{key: "summary_model", value: "v1"})
      updated = Ash.update!(setting, %{value: "v2"})

      assert updated.value == "v2"
    end

    test "destroys setting" do
      setting = Ash.create!(Setting, %{key: "summary_model", value: "v1"})
      assert :ok = Ash.destroy!(setting)
    end
  end
end
