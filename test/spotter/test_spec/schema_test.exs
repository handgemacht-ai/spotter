defmodule Spotter.TestSpec.SchemaTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias Spotter.TestSpec.Repo
  alias Spotter.TestSpec.Schema

  @moduletag :live_dolt

  describe "ensure_schema!/0" do
    test "is idempotent — can be called multiple times without error" do
      assert :ok = Schema.ensure_schema!()
      assert :ok = Schema.ensure_schema!()
    end

    test "creates the test_specs table with expected columns" do
      :ok = Schema.ensure_schema!()

      {:ok, result} = SQL.query(Repo, "DESCRIBE test_specs")

      columns = Enum.map(result.rows, &List.first/1)

      expected = ~w(
        id project_id test_key relative_path framework describe_path_json
        test_name line_start line_end given_json when_json then_json
        confidence metadata_json source_commit_hash updated_by_git_commit
        created_at updated_at
      )

      for col <- expected do
        assert col in columns, "Expected column #{col} in test_specs table"
      end
    end
  end
end
