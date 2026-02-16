defmodule Spotter.Transcripts.Jobs.AnalyzeCommitTestsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Transcripts.{Commit, CommitTestRun, Project, Session}
  alias Spotter.Transcripts.Jobs.AnalyzeCommitTests

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "analyze-tests", pattern: "^test"})

    %{project: project}
  end

  defp perform_job(project_id, commit_hash) do
    job = %Oban.Job{
      args: %{"project_id" => project_id, "commit_hash" => commit_hash}
    }

    AnalyzeCommitTests.perform(job)
  end

  defp setup_git_repo do
    tmp_dir = Path.join(System.tmp_dir!(), "spotter-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)
    tmp_dir
  end

  defp git_commit_hash(repo_path) do
    {hash, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: repo_path)
    String.trim(hash)
  end

  defp create_session(project, cwd) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      project_id: project.id,
      cwd: cwd,
      started_at: DateTime.utc_now()
    })
  end

  describe "parse_diff_tree/1" do
    test "parses added, modified, deleted, renamed entries" do
      output =
        "A\ttest/foo_test.exs\nM\ttest/bar_test.exs\nD\ttest/old_test.exs\nR100\ttest/baz_test.exs\ttest/qux_test.exs\n"

      result = AnalyzeCommitTests.parse_diff_tree(output)
      assert length(result) == 4
      assert Enum.at(result, 0) == %{status: :added, path: "test/foo_test.exs"}
      assert Enum.at(result, 1) == %{status: :modified, path: "test/bar_test.exs"}
      assert Enum.at(result, 2) == %{status: :deleted, path: "test/old_test.exs"}

      assert Enum.at(result, 3) == %{
               status: :renamed,
               old_path: "test/baz_test.exs",
               path: "test/qux_test.exs"
             }
    end
  end

  describe "test_candidate?/1" do
    test "matches test paths" do
      assert AnalyzeCommitTests.test_candidate?("test/foo_test.exs")
      assert AnalyzeCommitTests.test_candidate?("lib/test/helper.ex")
      assert AnalyzeCommitTests.test_candidate?("src/__tests__/foo.test.ts")
      assert AnalyzeCommitTests.test_candidate?("spec/models/user_spec.rb")
      assert AnalyzeCommitTests.test_candidate?("src/foo.spec.js")
    end

    test "rejects non-test paths" do
      refute AnalyzeCommitTests.test_candidate?("lib/foo.ex")
      refute AnalyzeCommitTests.test_candidate?("src/index.ts")
      refute AnalyzeCommitTests.test_candidate?("README.md")
    end
  end

  describe "perform/1 - missing repo path" do
    test "marks commit as error", %{project: project} do
      commit = Ash.create!(Commit, %{commit_hash: String.duplicate("d", 40)})

      # No sessions exist, so resolve_repo_path returns :no_cwd
      perform_job(project.id, commit.commit_hash)

      updated = Ash.get!(Commit, commit.id)
      assert updated.tests_status == :error
      assert updated.tests_error =~ "no accessible repo path"
    end
  end

  describe "perform/1 - deleted file" do
    @describetag :live_dolt

    test "deletes existing tests for the file", %{project: project} do
      Application.put_env(:spotter, :commit_test_agent_module, StubAgent)
      tmp_dir = setup_git_repo()

      # Create initial commit with a test file
      File.mkdir_p!(Path.join(tmp_dir, "test"))
      File.write!(Path.join(tmp_dir, "test/old_test.exs"), "# old test")
      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

      # Delete the file and commit
      File.rm!(Path.join(tmp_dir, "test/old_test.exs"))
      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "delete test"], cd: tmp_dir)

      hash = git_commit_hash(tmp_dir)
      commit = Ash.create!(Commit, %{commit_hash: hash})
      create_session(project, tmp_dir)

      # Seed test_specs in Dolt that should be deleted
      alias Spotter.TestSpec.Agent.ToolHelpers, as: DoltH

      DoltH.dolt_query!(
        "INSERT INTO test_specs (project_id, test_key, relative_path, framework, describe_path_json, test_name, given_json, when_json, then_json, metadata_json, updated_by_git_commit) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          project.id,
          "ExUnit|test/old_test.exs||old test 1",
          "test/old_test.exs",
          "ExUnit",
          "[]",
          "old test 1",
          "[]",
          "[]",
          "[]",
          "{}",
          hash
        ]
      )

      DoltH.dolt_query!(
        "INSERT INTO test_specs (project_id, test_key, relative_path, framework, describe_path_json, test_name, given_json, when_json, then_json, metadata_json, updated_by_git_commit) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          project.id,
          "ExUnit|test/old_test.exs||old test 2",
          "test/old_test.exs",
          "ExUnit",
          "[]",
          "old test 2",
          "[]",
          "[]",
          "[]",
          "{}",
          hash
        ]
      )

      perform_job(project.id, hash)

      # Verify tests were deleted from Dolt
      {:ok, remaining} =
        DoltH.dolt_query(
          "SELECT COUNT(*) FROM test_specs WHERE project_id = ? AND relative_path = ?",
          [project.id, "test/old_test.exs"]
        )

      assert remaining.rows == [[0]]

      # Verify commit is marked ok
      updated = Ash.get!(Commit, commit.id)
      assert updated.tests_status == :ok

      # Verify CommitTestRun was created
      runs = CommitTestRun |> Ash.Query.filter(commit_id == ^commit.id) |> Ash.read!()
      assert length(runs) == 1
      assert hd(runs).status == :completed

      File.rm_rf!(tmp_dir)
      Application.delete_env(:spotter, :commit_test_agent_module)
    end
  end

  describe "perform/1 - agent success path" do
    @describetag :live_dolt

    test "creates test cases via stub agent", %{project: project} do
      Application.put_env(:spotter, :commit_test_agent_module, StubAgentWithCreate)
      tmp_dir = setup_git_repo()

      # Create initial commit
      File.write!(Path.join(tmp_dir, "README.md"), "# hi")
      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

      # Add a test file
      File.mkdir_p!(Path.join(tmp_dir, "test"))

      File.write!(Path.join(tmp_dir, "test/new_test.exs"), """
      defmodule NewTest do
        use ExUnit.Case
        test "works" do
          assert true
        end
      end
      """)

      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "add test"], cd: tmp_dir)

      hash = git_commit_hash(tmp_dir)
      commit = Ash.create!(Commit, %{commit_hash: hash})
      create_session(project, tmp_dir)

      perform_job(project.id, hash)

      updated = Ash.get!(Commit, commit.id)
      assert updated.tests_status == :ok
      assert updated.tests_analyzed_at != nil

      runs = CommitTestRun |> Ash.Query.filter(commit_id == ^commit.id) |> Ash.read!()
      assert length(runs) == 1
      assert hd(runs).status == :completed

      File.rm_rf!(tmp_dir)
      Application.delete_env(:spotter, :commit_test_agent_module)
    end
  end
end

defmodule StubAgent do
  @moduledoc false
  def run_file(_input) do
    {:ok, %{model_used: "stub", tool_counts: %{}, final_text: "done"}}
  end
end

defmodule StubAgentWithCreate do
  @moduledoc false
  def run_file(input) do
    Ash.create!(Spotter.Transcripts.TestCase, %{
      project_id: input.project_id,
      relative_path: input.relative_path,
      framework: "ExUnit",
      test_name: "works",
      given: [],
      when: [],
      then: ["assert true"],
      confidence: 0.95
    })

    {:ok,
     %{
       model_used: "stub",
       tool_counts: %{"mcp__spotter-tests__create_test" => 1},
       final_text: ~s({"recognized_tests": 1, "created": 1, "updated": 0, "deleted": 0})
     }}
  end
end
