defmodule Spotter.Services.GitLogReaderRangeTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.GitLogReader
  alias Spotter.TestSupport.GitRepoHelper

  @jan1 ~U[2025-01-01 10:00:00Z]
  @jan2 ~U[2025-01-02 10:00:00Z]
  @jan3 ~U[2025-01-03 10:00:00Z]
  @jan4 ~U[2025-01-04 10:00:00Z]

  setup do
    repo_path =
      GitRepoHelper.create_repo_with_timed_history!([
        {@jan1, [{"lib/a.ex", "defmodule A, do: :v1"}]},
        {@jan2, [{"lib/b.ex", "defmodule B, do: :v1"}]},
        {@jan3, [{"lib/c.ex", "defmodule C, do: :v1"}]},
        {@jan4, [{"lib/d.ex", "defmodule D, do: :v1"}]}
      ])

    on_exit(fn -> File.rm_rf!(repo_path) end)

    %{repo_path: repo_path}
  end

  describe "since/until range filtering" do
    test "returns only commits within the time window", %{repo_path: repo_path} do
      {:ok, commits} =
        GitLogReader.changed_files_by_commit(repo_path,
          since: @jan2,
          until: @jan3,
          branch: "main"
        )

      files = Enum.flat_map(commits, & &1.files)
      refute "lib/a.ex" in files
      assert "lib/b.ex" in files
      assert "lib/c.ex" in files
      refute "lib/d.ex" in files
    end

    test "since without until returns all commits from that point", %{repo_path: repo_path} do
      {:ok, commits} =
        GitLogReader.changed_files_by_commit(repo_path,
          since: @jan3,
          branch: "main"
        )

      files = Enum.flat_map(commits, & &1.files)
      refute "lib/a.ex" in files
      refute "lib/b.ex" in files
      assert "lib/c.ex" in files
      assert "lib/d.ex" in files
    end

    test "returned maps include :hash, :timestamp, and :files", %{repo_path: repo_path} do
      {:ok, commits} =
        GitLogReader.changed_files_by_commit(repo_path,
          since: @jan1,
          branch: "main"
        )

      assert commits != []

      for commit <- commits do
        assert is_binary(commit.hash)
        assert %DateTime{} = commit.timestamp
        assert is_list(commit.files)
      end
    end
  end

  describe "since_days fallback" do
    test "falls back to since_days when :since not provided", %{repo_path: repo_path} do
      # These commits are ~1 year old, so since_days: 1 should return nothing
      {:ok, commits} =
        GitLogReader.changed_files_by_commit(repo_path,
          since_days: 1,
          branch: "main"
        )

      assert commits == []
    end
  end
end
