defmodule Spotter.Services.GitLogReaderTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.GitLogReader

  describe "parse_output/1" do
    test "parses standard git log output" do
      output = """
      COMMIT:abc123:1700000000
      lib/foo.ex
      lib/bar.ex
      COMMIT:def456:1700086400
      README.md
      """

      result = GitLogReader.parse_output(output)
      assert length(result) == 2

      [first, second] = result
      assert first.hash == "abc123"
      assert first.timestamp == ~U[2023-11-14 22:13:20Z]
      assert first.files == ["lib/foo.ex", "lib/bar.ex"]

      assert second.hash == "def456"
      assert second.files == ["README.md"]
    end

    test "handles empty output" do
      assert GitLogReader.parse_output("") == []
    end

    test "handles output with no files" do
      output = "COMMIT:abc123:1700000000\n"
      result = GitLogReader.parse_output(output)
      assert length(result) == 1
      assert hd(result).files == []
    end

    test "handles malformed commit header" do
      output = "COMMIT:badformat\nfile.ex\n"
      # Should still parse - badformat becomes hash, no unix timestamp
      result = GitLogReader.parse_output(output)
      assert result == []
    end
  end

  describe "resolve_branch/2" do
    test "returns provided branch when given" do
      assert {:ok, "develop"} = GitLogReader.resolve_branch("/tmp", "develop")
    end

    test "skips empty string branch" do
      # Empty string falls through to auto-detect which will fail on /tmp
      assert {:error, _} = GitLogReader.resolve_branch("/tmp/nonexistent-repo", "")
    end
  end

  describe "changed_files_by_commit/2" do
    test "returns error for nonexistent repo" do
      assert {:error, _} =
               GitLogReader.changed_files_by_commit(
                 "/tmp/nonexistent-repo-#{System.unique_integer()}",
                 since_days: 1
               )
    end
  end

  describe "filter_spotterignore" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "git_log_reader_test_#{System.unique_integer()}")
      File.mkdir_p!(tmp_dir)

      System.cmd("git", ["-C", tmp_dir, "init"])
      System.cmd("git", ["-C", tmp_dir, "config", "user.name", "Test"])
      System.cmd("git", ["-C", tmp_dir, "config", "user.email", "test@test.com"])

      # Create and commit lib/foo.ex
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.write!(Path.join(tmp_dir, "lib/foo.ex"), "defmodule Foo, do: :ok")

      # Create and commit .beads/issues.jsonl
      File.mkdir_p!(Path.join(tmp_dir, ".beads"))
      File.write!(Path.join(tmp_dir, ".beads/issues.jsonl"), "{}")

      System.cmd("git", ["-C", tmp_dir, "add", "."])
      System.cmd("git", ["-C", tmp_dir, "commit", "-m", "initial"])

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir}
    end

    test "default call returns all paths including .beads/", %{tmp_dir: tmp_dir} do
      {:ok, commits} =
        GitLogReader.changed_files_by_commit(tmp_dir, since_days: 30, branch: "main")

      all_files = Enum.flat_map(commits, & &1.files)
      assert ".beads/issues.jsonl" in all_files
      assert "lib/foo.ex" in all_files
    end

    test "filter_spotterignore: true excludes matching paths", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, ".spotterignore"), ".beads/\n")

      {:ok, commits} =
        GitLogReader.changed_files_by_commit(tmp_dir,
          since_days: 30,
          branch: "main",
          filter_spotterignore: true
        )

      all_files = Enum.flat_map(commits, & &1.files)
      refute ".beads/issues.jsonl" in all_files
      assert "lib/foo.ex" in all_files
    end

    test "missing .spotterignore keeps all paths", %{tmp_dir: tmp_dir} do
      {:ok, commits} =
        GitLogReader.changed_files_by_commit(tmp_dir,
          since_days: 30,
          branch: "main",
          filter_spotterignore: true
        )

      all_files = Enum.flat_map(commits, & &1.files)
      assert ".beads/issues.jsonl" in all_files
    end

    test "empty .spotterignore keeps all paths", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, ".spotterignore"), "")

      {:ok, commits} =
        GitLogReader.changed_files_by_commit(tmp_dir,
          since_days: 30,
          branch: "main",
          filter_spotterignore: true
        )

      all_files = Enum.flat_map(commits, & &1.files)
      assert ".beads/issues.jsonl" in all_files
    end
  end
end
