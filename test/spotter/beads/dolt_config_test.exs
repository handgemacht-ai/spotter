defmodule Spotter.Beads.DoltConfigTest do
  use ExUnit.Case, async: true

  alias Spotter.Beads.DoltConfig

  describe "connection_opts/1" do
    test "returns correct defaults when no app config is set" do
      # Temporarily clear any app config to test module defaults
      original = Application.get_env(:spotter, DoltConfig)
      Application.delete_env(:spotter, DoltConfig)

      on_exit(fn ->
        if original, do: Application.put_env(:spotter, DoltConfig, original)
      end)

      opts = DoltConfig.connection_opts("myproject")

      assert Keyword.get(opts, :hostname) == "127.0.0.1"
      assert Keyword.get(opts, :port) == 3307
      assert Keyword.get(opts, :username) == "root"
      assert Keyword.get(opts, :password) == ""
      assert Keyword.get(opts, :database) == "myproject"
    end

    test "uses app config overrides when set" do
      original = Application.get_env(:spotter, DoltConfig)

      Application.put_env(:spotter, DoltConfig,
        hostname: "custom-host",
        port: 9999,
        username: "custom-user",
        password: "custom-pass"
      )

      on_exit(fn ->
        if original do
          Application.put_env(:spotter, DoltConfig, original)
        else
          Application.delete_env(:spotter, DoltConfig)
        end
      end)

      opts = DoltConfig.connection_opts("testproject")

      assert Keyword.get(opts, :hostname) == "custom-host"
      assert Keyword.get(opts, :port) == 9999
      assert Keyword.get(opts, :username) == "custom-user"
      assert Keyword.get(opts, :password) == "custom-pass"
      assert Keyword.get(opts, :database) == "testproject"
    end
  end

  describe "database_name/1" do
    test "returns project name directly without prefix" do
      assert DoltConfig.database_name("aufgabenschmiede") == "aufgabenschmiede"
      assert DoltConfig.database_name("le") == "le"
      assert DoltConfig.database_name("beads_spotter") == "beads_spotter"
    end
  end
end
