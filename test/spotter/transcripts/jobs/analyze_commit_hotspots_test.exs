defmodule Spotter.Transcripts.Jobs.AnalyzeCommitHotspotsTest do
  use ExUnit.Case, async: false
  # Quarantined: flaky DBConnection.OwnershipError and timeouts in CI/hooks
  # See spotter-y6o for follow-up fix
  @moduletag :flaky

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, Project, Session}
  alias Spotter.Transcripts.Jobs.AnalyzeCommitHotspots

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  describe "perform/1 with missing repo path" do
    test "marks commit as error when no session cwd exists" do
      project = Ash.create!(Project, %{name: "test-analyze", pattern: "^test"})

      commit =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("a", 40),
          subject: "Test commit"
        })

      job = %Oban.Job{
        args: %{"project_id" => project.id, "commit_hash" => commit.commit_hash}
      }

      assert :ok = AnalyzeCommitHotspots.perform(job)

      updated = Ash.read_one!(Commit |> Ash.Query.filter(id == ^commit.id))
      assert updated.hotspots_status == :error
      assert updated.hotspots_error =~ "no accessible repo path"
    end
  end

  describe "perform/1 with missing commit" do
    test "returns :ok without crashing" do
      project = Ash.create!(Project, %{name: "test-analyze-miss", pattern: "^test"})

      job = %Oban.Job{
        args: %{"project_id" => project.id, "commit_hash" => String.duplicate("f", 40)}
      }

      assert :ok = AnalyzeCommitHotspots.perform(job)
    end
  end

  describe "perform/1 with valid repo but no API key" do
    @tag :spawns_claude
    @tag :slow
    test "marks commit as error for missing API key" do
      project = Ash.create!(Project, %{name: "test-analyze-key", pattern: "^test"})
      cwd = File.cwd!()

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id,
        cwd: cwd,
        started_at: DateTime.utc_now()
      })

      commit =
        Ash.create!(Commit, %{
          commit_hash: get_real_commit_hash(),
          subject: "Real commit"
        })

      job = %Oban.Job{
        args: %{"project_id" => project.id, "commit_hash" => commit.commit_hash}
      }

      assert :ok = AnalyzeCommitHotspots.perform(job)

      updated = Ash.read_one!(Commit |> Ash.Query.filter(id == ^commit.id))
      assert updated.hotspots_status == :error
      assert updated.hotspots_error =~ "missing_api_key"
    end
  end

  describe "filter_patch_files/2" do
    test "filters out blocklisted and binary files with correct counts" do
      patch_files = [
        %{path: ".beads/issues.jsonl", hunks: []},
        %{path: "lib/a.ex", hunks: []},
        %{path: "assets/logo.png", hunks: []}
      ]

      binary_files = ["bin/whatever.exe"]

      {eligible, meta} = AnalyzeCommitHotspots.filter_patch_files(patch_files, binary_files)

      assert [%{path: "lib/a.ex"}] = eligible
      assert meta.total == 3
      assert meta.eligible == 1
      assert meta.skipped_binary == 0
      assert meta.skipped_blocklist == 2
    end

    test "counts binary files separately from blocklist" do
      patch_files = [
        %{path: "bin/app.exe", hunks: []},
        %{path: ".beads/data.jsonl", hunks: []},
        %{path: "lib/b.ex", hunks: []}
      ]

      binary_files = ["bin/app.exe"]

      {eligible, meta} = AnalyzeCommitHotspots.filter_patch_files(patch_files, binary_files)

      assert [%{path: "lib/b.ex"}] = eligible
      assert meta.total == 3
      assert meta.eligible == 1
      assert meta.skipped_binary == 1
      assert meta.skipped_blocklist == 1
    end

    test "returns empty eligible list when all files are filtered" do
      patch_files = [
        %{path: ".beads/issues.jsonl", hunks: []},
        %{path: "deps/foo/lib/bar.ex", hunks: []}
      ]

      {eligible, meta} = AnalyzeCommitHotspots.filter_patch_files(patch_files, [])

      assert eligible == []
      assert meta.total == 2
      assert meta.eligible == 0
    end
  end

  defp get_real_commit_hash do
    {hash, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    String.trim(hash)
  end
end
