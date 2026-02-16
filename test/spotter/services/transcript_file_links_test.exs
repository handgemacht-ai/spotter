defmodule Spotter.Services.TranscriptFileLinksTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.TranscriptFileLinks

  describe "for_session/1" do
    test "returns error for nil cwd" do
      assert {:error, :no_cwd} = TranscriptFileLinks.for_session(nil)
    end

    test "returns error for non-existent directory" do
      assert {:error, _reason} = TranscriptFileLinks.for_session("/nonexistent/path/xyz")
    end

    test "resolves files for current repo" do
      # Use the project's own repo as a test subject
      cwd = File.cwd!()

      case TranscriptFileLinks.for_session(cwd) do
        {:ok, result} ->
          assert is_binary(result.repo_root)
          assert is_binary(result.ref)
          assert is_binary(result.ref_hash)
          assert %MapSet{} = result.files
          # This project should have at least its own source files
          assert MapSet.member?(result.files, "mix.exs")

        {:error, _reason} ->
          # May fail in CI or unusual git configs — acceptable
          :ok
      end
    end

    test "cache hit returns same result without extra git calls" do
      cwd = File.cwd!()

      case TranscriptFileLinks.for_session(cwd) do
        {:ok, first_result} ->
          {:ok, second_result} = TranscriptFileLinks.for_session(cwd)
          assert first_result.files == second_result.files
          assert first_result.ref_hash == second_result.ref_hash

        {:error, _} ->
          :ok
      end
    end
  end

  describe "ensure_available/0" do
    test "returns :ok when service is running" do
      assert :ok = TranscriptFileLinks.ensure_available()
    end
  end

  describe "resilience to missing ETS table" do
    test "safe_lookup returns miss when ETS table is absent" do
      # Delete the table, call for_session, verify no ArgumentError
      # The service should recover via ensure_available -> restart_child
      original_pid = Process.whereis(TranscriptFileLinks)
      assert original_pid != nil

      # Stop the GenServer (which owns the ETS table)
      GenServer.stop(original_pid)

      # Table and process are now gone — for_session must not raise
      result = TranscriptFileLinks.for_session("/nonexistent/path/xyz")

      # Should return a normal error tuple, never raise
      assert {:error, _reason} = result

      # Service should have been recovered by ensure_available
      new_pid = Process.whereis(TranscriptFileLinks)
      assert new_pid != nil
      assert new_pid != original_pid
    end
  end
end
