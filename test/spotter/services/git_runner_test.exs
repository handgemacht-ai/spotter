defmodule Spotter.Services.GitRunnerTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.GitRunner

  @cwd File.cwd!()

  @moduletag timeout: 30_000

  describe "run/2" do
    test "success case returns ok with output" do
      assert {:ok, output} = GitRunner.run(["rev-parse", "HEAD"], cd: @cwd, timeout_ms: 5_000)
      assert String.match?(String.trim(output), ~r/^[0-9a-f]{40}$/)
    end

    test "nonzero exit returns structured error" do
      assert {:error, %{kind: :exit_nonzero, status: status}} =
               GitRunner.run(["rev-parse", "DOES_NOT_EXIST"], cd: @cwd, timeout_ms: 5_000)

      assert is_integer(status)
      assert status != 0
    end

    @tag timeout: 10_000
    test "timeout returns structured error" do
      # git cat-file --batch reads from stdin indefinitely
      assert {:error, %{kind: :timeout}} =
               GitRunner.run(["cat-file", "--batch"], cd: @cwd, timeout_ms: 100)
    end

    test "requires cd option" do
      assert_raise KeyError, fn ->
        GitRunner.run(["status"], [])
      end
    end
  end
end
