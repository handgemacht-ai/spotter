defmodule Spotter.TestSupport.GitRepoHelper do
  @moduledoc """
  Creates tiny deterministic git repos for co-change tests.
  """

  @doc """
  Creates a temp git repo with a small commit history that reliably generates co-change groups.

  Returns `repo_path`. Caller must clean up with `File.rm_rf!/1`.
  """
  def create_repo_with_history! do
    tmp_dir = Path.join(System.tmp_dir!(), "co_change_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    git!(tmp_dir, ["init"])
    git!(tmp_dir, ["config", "user.name", "Test"])
    git!(tmp_dir, ["config", "user.email", "test@test.com"])

    lib_dir = Path.join(tmp_dir, "lib")
    File.mkdir_p!(lib_dir)

    # Commit 1: a.ex + b.ex
    File.write!(Path.join(lib_dir, "a.ex"), "defmodule A, do: :v1")
    File.write!(Path.join(lib_dir, "b.ex"), "defmodule B, do: :v1")
    git!(tmp_dir, ["add", "."])
    git!(tmp_dir, ["commit", "-m", "commit 1: a + b"])

    # Commit 2: a.ex + b.ex again (creates co-change pair)
    File.write!(Path.join(lib_dir, "a.ex"), "defmodule A, do: :v2")
    File.write!(Path.join(lib_dir, "b.ex"), "defmodule B, do: :v2")
    git!(tmp_dir, ["add", "."])
    git!(tmp_dir, ["commit", "-m", "commit 2: a + b"])

    # Commit 3: b.ex + c.ex
    File.write!(Path.join(lib_dir, "b.ex"), "defmodule B, do: :v3")
    File.write!(Path.join(lib_dir, "c.ex"), "defmodule C, do: :v1")
    git!(tmp_dir, ["add", "."])
    git!(tmp_dir, ["commit", "-m", "commit 3: b + c"])

    tmp_dir
  end

  @doc """
  Creates a temp git repo with commits at specific timestamps.

  Accepts a list of `{datetime, [{path, content}]}` tuples.
  Uses `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` for deterministic timestamps.

  Returns `repo_path`. Caller must clean up with `File.rm_rf!/1`.
  """
  def create_repo_with_timed_history!(commits) do
    tmp_dir = Path.join(System.tmp_dir!(), "timed_repo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    git!(tmp_dir, ["init"])
    git!(tmp_dir, ["config", "user.name", "Test"])
    git!(tmp_dir, ["config", "user.email", "test@test.com"])

    Enum.each(commits, fn {%DateTime{} = dt, files} ->
      Enum.each(files, fn {path, content} ->
        full_path = Path.join(tmp_dir, path)
        File.mkdir_p!(Path.dirname(full_path))
        File.write!(full_path, content)
      end)

      git!(tmp_dir, ["add", "."])
      iso = DateTime.to_iso8601(dt)

      {_, 0} =
        System.cmd("git", ["-C", tmp_dir, "commit", "-m", "commit at #{iso}"],
          env: [{"GIT_AUTHOR_DATE", iso}, {"GIT_COMMITTER_DATE", iso}]
        )
    end)

    tmp_dir
  end

  defp git!(dir, args) do
    {_, 0} = System.cmd("git", ["-C", dir | args])
  end
end
