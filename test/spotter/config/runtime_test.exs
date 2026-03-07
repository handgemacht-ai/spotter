defmodule Spotter.Config.RuntimeTest do
  use Spotter.DataCase

  alias Spotter.Config.Runtime
  alias Spotter.Config.Setting

  describe "transcript_roots/0" do
    test "DB override beats TOML and default" do
      Ash.create!(Setting, %{key: "transcript_roots", value: ~s(["/custom/dir"])})

      assert {["/custom/dir"], :db} = Runtime.transcript_roots()
    end

    test "falls back to TOML when DB absent" do
      {roots, source} = Runtime.transcript_roots()

      assert [_ | _] = roots
      assert source in [:toml, :default]
    end

    test "expands tilde in DB override" do
      Ash.create!(Setting, %{key: "transcript_roots", value: ~s(["~/my-transcripts"])})

      {[dir], :db} = Runtime.transcript_roots()
      refute String.starts_with?(dir, "~")
      assert String.ends_with?(dir, "/my-transcripts")
    end
  end

  describe "Setting resource" do
    test "creates valid setting" do
      assert {:ok, setting} =
               Ash.create(Setting, %{key: "transcript_roots", value: ~s(["/test"])})

      assert setting.key == "transcript_roots"
      assert setting.value == ~s(["/test"])
    end

    test "rejects disallowed key" do
      assert {:error, _} = Ash.create(Setting, %{key: "invalid_key", value: "test"})
    end

    test "enforces unique key" do
      Ash.create!(Setting, %{key: "transcript_roots", value: ~s(["/v1"])})

      assert {:error, _} = Ash.create(Setting, %{key: "transcript_roots", value: ~s(["/v2"])})
    end

    test "updates value" do
      setting = Ash.create!(Setting, %{key: "transcript_roots", value: ~s(["/v1"])})
      updated = Ash.update!(setting, %{value: ~s(["/v2"])})

      assert updated.value == ~s(["/v2"])
    end

    test "destroys setting" do
      setting = Ash.create!(Setting, %{key: "transcript_roots", value: ~s(["/v1"])})
      assert :ok = Ash.destroy!(setting)
    end
  end
end
