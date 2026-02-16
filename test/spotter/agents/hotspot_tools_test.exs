defmodule Spotter.Agents.HotspotToolsTest do
  use ExUnit.Case, async: true

  alias Spotter.Agents.HotspotTools
  alias Spotter.Agents.HotspotToolServer

  @cwd File.cwd!()

  setup do
    HotspotTools.Helpers.set_git_cwd(@cwd)

    {output, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: @cwd)
    commit_hash = String.trim(output)

    %{commit_hash: commit_hash}
  end

  describe "repo_read_file_at_commit" do
    test "reads full file content", %{commit_hash: hash} do
      {:ok, result} =
        HotspotTools.RepoReadFileAtCommit.execute(%{
          "commit_hash" => hash,
          "relative_path" => "README.md"
        })

      parsed = decode(result)
      assert parsed["ok"] == true
      assert is_binary(parsed["content"])
      assert parsed["bytes"] > 0
      assert parsed["commit_hash"] == hash
    end

    test "reads file with line slicing", %{commit_hash: hash} do
      {:ok, result} =
        HotspotTools.RepoReadFileAtCommit.execute(%{
          "commit_hash" => hash,
          "relative_path" => "README.md",
          "line_start" => 1,
          "line_end" => 5,
          "context_before" => 0,
          "context_after" => 0
        })

      parsed = decode(result)
      assert parsed["ok"] == true
      assert parsed["slice"]["line_start"] == 1
      assert parsed["slice"]["line_end"] >= 1
      assert is_binary(parsed["content"])
      assert parsed["content"] != ""
    end

    test "returns error for missing file", %{commit_hash: hash} do
      {:ok, result} =
        HotspotTools.RepoReadFileAtCommit.execute(%{
          "commit_hash" => hash,
          "relative_path" => "nonexistent/path.txt"
        })

      parsed = decode(result)
      assert parsed["ok"] == false
      assert is_binary(parsed["error"])
    end

    test "returns error when git_cwd not set" do
      HotspotTools.Helpers.set_git_cwd(nil)

      {:ok, result} =
        HotspotTools.RepoReadFileAtCommit.execute(%{
          "commit_hash" => "abc123",
          "relative_path" => "README.md"
        })

      parsed = decode(result)
      assert parsed["ok"] == false
      assert parsed["error"] =~ "git_cwd"
    end
  end

  describe "tool registration" do
    test "all_tool_modules returns 1 tool module" do
      assert length(HotspotTools.all_tool_modules()) == 1
    end

    test "MCP server can be created" do
      server = HotspotToolServer.create_server()
      assert server.name == "spotter-hotspots"
    end
  end

  defp decode(%{"content" => [%{"type" => "text", "text" => json}]}) do
    Jason.decode!(json)
  end
end
