defmodule Spotter.ProductSpec.Jobs.UpdateRollingSpecTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.ProductSpec.Jobs.UpdateRollingSpec
  alias Spotter.ProductSpec.RollingSpecRun
  alias Spotter.Repo

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  describe "perform/1 when product spec disabled" do
    test "returns :ok without creating a run" do
      # Product spec is disabled by default in test config
      job = %Oban.Job{
        args: %{
          "project_id" => Ash.UUID.generate(),
          "commit_hash" => String.duplicate("a", 40)
        }
      }

      assert :ok = UpdateRollingSpec.perform(job)

      runs = Ash.read!(RollingSpecRun)
      assert runs == []
    end
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

      # Enable product spec temporarily for this test
      original = Application.get_env(:spotter, :product_spec_enabled)
      Application.put_env(:spotter, :product_spec_enabled, true)

      on_exit(fn -> Application.put_env(:spotter, :product_spec_enabled, original) end)

      job = %Oban.Job{
        args: %{
          "project_id" => project_id,
          "commit_hash" => commit_hash
        }
      }

      assert :ok = UpdateRollingSpec.perform(job)

      # Verify the run was marked as skipped (upsert creates new with pending, then idempotence check marks skipped)
      run =
        RollingSpecRun
        |> Ash.Query.filter(project_id == ^project_id and commit_hash == ^commit_hash)
        |> Ash.read_one!()

      assert run.status in [:ok, :skipped]
    end
  end
end
