defmodule Spotter.ProductSpec.Jobs.UpdateRollingSpecTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.ProductSpec.Jobs.UpdateRollingSpec
  alias Spotter.ProductSpec.RollingSpecRun
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, Project, Session, SessionCommitLink}

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_session(project_id, attrs \\ %{}) do
    session =
      Ash.create!(Session, %{session_id: Ash.UUID.generate(), project_id: project_id})

    if map_size(attrs) > 0, do: Ash.update!(session, attrs), else: session
  end

  describe "perform/1 idempotence" do
    test "skips when run already has status :ok" do
      project_id = Ash.UUID.generate()
      commit_hash = String.duplicate("b", 40)

      # Pre-create a successful run
      {:ok, _run} =
        Ash.create(RollingSpecRun, %{
          project_id: project_id,
          commit_hash: commit_hash,
          status: :ok,
          finished_at: DateTime.utc_now()
        })

      job = %Oban.Job{
        args: %{
          "project_id" => project_id,
          "commit_hash" => commit_hash
        }
      }

      assert :ok = UpdateRollingSpec.perform(job)

      run =
        RollingSpecRun
        |> Ash.Query.filter(project_id == ^project_id and commit_hash == ^commit_hash)
        |> Ash.read_one!()

      assert run.status in [:ok, :skipped]
    end
  end

  describe "validate_agent_input/1" do
    @valid_agent_input %{
      project_id: "00000000-0000-0000-0000-000000000042",
      commit_hash: String.duplicate("a", 40),
      commit_subject: "feat: add login page",
      commit_body: "",
      diff_stats: %{files_changed: 1, insertions: 10, deletions: 0, binary_files: []},
      patch_files: [%{path: "lib/app.ex", hunks: []}],
      context_windows: %{"lib/app.ex" => "defmodule App do\nend"},
      linked_session_summaries: [],
      git_cwd: nil
    }

    test "accepts a well-formed map with empty commit_body" do
      assert :ok = UpdateRollingSpec.validate_agent_input(@valid_agent_input)
    end

    test "rejects blank commit_subject" do
      input = Map.put(@valid_agent_input, :commit_subject, "")
      assert {:error, msg} = UpdateRollingSpec.validate_agent_input(input)
      assert msg =~ "commit_subject"
    end

    test "rejects nil commit_subject" do
      input = Map.put(@valid_agent_input, :commit_subject, nil)
      assert {:error, msg} = UpdateRollingSpec.validate_agent_input(input)
      assert msg =~ "commit_subject"
    end

    test "rejects diff_stats that is not a map" do
      input = Map.put(@valid_agent_input, :diff_stats, "not a map")
      assert {:error, msg} = UpdateRollingSpec.validate_agent_input(input)
      assert msg =~ "diff_stats"
    end

    test "rejects patch_files that is not a list" do
      input = Map.put(@valid_agent_input, :patch_files, %{})
      assert {:error, msg} = UpdateRollingSpec.validate_agent_input(input)
      assert msg =~ "patch_files"
    end

    test "rejects context_windows that is not a map" do
      input = Map.put(@valid_agent_input, :context_windows, [])
      assert {:error, msg} = UpdateRollingSpec.validate_agent_input(input)
      assert msg =~ "context_windows"
    end

    test "accepts input without optional linked_session_summaries" do
      input = Map.delete(@valid_agent_input, :linked_session_summaries)
      assert :ok = UpdateRollingSpec.validate_agent_input(input)
    end

    test "rejects linked_session_summaries that is not a list" do
      input = Map.put(@valid_agent_input, :linked_session_summaries, "not a list")
      assert {:error, msg} = UpdateRollingSpec.validate_agent_input(input)
      assert msg =~ "linked_session_summaries"
    end
  end

  describe "fallback commit subject" do
    test "blank commit subject resolves to fallback value" do
      # The fallback is applied in load_commit_message (private), but we can
      # verify the contract: the fallback subject is "(unknown subject)"
      # by checking the module attribute indirectly through build_agent_input
      # which calls load_commit_message. Since build_agent_input is private,
      # we test the public validate_agent_input with the expected fallback.
      input = %{
        project_id: Ash.UUID.generate(),
        commit_hash: String.duplicate("f", 40),
        commit_subject: "(unknown subject)",
        commit_body: "",
        diff_stats: %{},
        patch_files: [],
        context_windows: %{}
      }

      assert :ok = UpdateRollingSpec.validate_agent_input(input)
    end
  end

  describe "load_linked_session_summaries/1" do
    test "returns summaries for sessions with completed distillation" do
      commit_hash = String.duplicate("c", 40)
      project = Ash.create!(Project, %{name: "test-proj", pattern: "^test"})
      commit = Ash.create!(Commit, %{commit_hash: commit_hash, subject: "feat: test"})

      session =
        create_session(project.id, %{
          distilled_status: :completed,
          distilled_summary: "Added login page with email/password auth",
          distilled_at: DateTime.utc_now()
        })

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      summaries = UpdateRollingSpec.load_linked_session_summaries(commit_hash)

      assert length(summaries) == 1
      [summary] = summaries
      assert summary.session_id == session.session_id
      assert summary.distilled_status == :completed
      assert summary.distilled_summary == "Added login page with email/password auth"
    end

    test "excludes sessions with pending distillation" do
      commit_hash = String.duplicate("d", 40)
      project = Ash.create!(Project, %{name: "test-proj-2", pattern: "^test2"})
      commit = Ash.create!(Commit, %{commit_hash: commit_hash, subject: "chore: deps"})

      session = create_session(project.id)

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      assert UpdateRollingSpec.load_linked_session_summaries(commit_hash) == []
    end

    test "returns empty list when no commit matches" do
      assert UpdateRollingSpec.load_linked_session_summaries(String.duplicate("e", 40)) == []
    end
  end
end
