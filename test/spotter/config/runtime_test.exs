defmodule Spotter.Config.RuntimeTest do
  use Spotter.DataCase

  alias Spotter.Config.Runtime
  alias Spotter.Config.Setting

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

  describe "Setting resource" do
    test "creates valid setting" do
      assert {:ok, setting} = Ash.create(Setting, %{key: "transcripts_dir", value: "test"})
      assert setting.key == "transcripts_dir"
      assert setting.value == "test"
    end

    test "rejects disallowed key" do
      assert {:error, _} = Ash.create(Setting, %{key: "invalid_key", value: "test"})
    end

    test "enforces unique key" do
      Ash.create!(Setting, %{key: "transcripts_dir", value: "v1"})

      assert {:error, _} = Ash.create(Setting, %{key: "transcripts_dir", value: "v2"})
    end

    test "updates value" do
      setting = Ash.create!(Setting, %{key: "transcripts_dir", value: "v1"})
      updated = Ash.update!(setting, %{value: "v2"})

      assert updated.value == "v2"
    end

    test "destroys setting" do
      setting = Ash.create!(Setting, %{key: "transcripts_dir", value: "v1"})
      assert :ok = Ash.destroy!(setting)
    end
  end
end
