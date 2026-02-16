defmodule Spotter.Search.QueryTest do
  use Spotter.DataCase, async: false

  alias Spotter.Search
  alias Spotter.Search.Query
  alias Spotter.Search.Result

  @project_id "00000000-0000-0000-0000-000000000001"
  @other_project_id "00000000-0000-0000-0000-000000000002"

  setup do
    insert_doc(%{
      kind: "session",
      project_id: @project_id,
      external_id: "sess-001",
      title: "Refactoring auth module",
      subtitle: "Session on 2026-01-15",
      url: "/projects/#{@project_id}/sessions/sess-001",
      search_text: "refactoring auth module login password"
    })

    insert_doc(%{
      kind: "commit",
      project_id: @project_id,
      external_id: "abc123",
      title: "Fix login bug",
      subtitle: nil,
      url: "/projects/#{@project_id}/commits/abc123",
      search_text: "fix login bug authentication"
    })

    insert_doc(%{
      kind: "file",
      project_id: @other_project_id,
      external_id: "lib/other/thing.ex",
      title: "lib/other/thing.ex",
      subtitle: nil,
      url: "/projects/#{@other_project_id}/files/lib/other/thing.ex",
      search_text: "lib/other/thing.ex"
    })

    :ok
  end

  describe "empty / guard queries" do
    test "empty string returns []" do
      assert Search.search("") == []
    end

    test "whitespace-only returns []" do
      assert Search.search("   ") == []
    end

    test "query over 200 bytes returns []" do
      long = String.duplicate("a", 201)
      assert Search.search(long) == []
    end
  end

  describe "prefix search" do
    test "partial match returns results" do
      results = Search.search("refact")
      assert results != []
      assert Enum.any?(results, &(&1.external_id == "sess-001"))
    end

    test "full word matches" do
      results = Search.search("login")
      assert results != []
    end
  end

  describe "project filter" do
    test "scopes results to given project_id" do
      results = Search.search("lib", project_id: @project_id)
      assert Enum.all?(results, &(&1.project_id == @project_id))
    end

    test "other project docs excluded" do
      results = Search.search("thing", project_id: @project_id)
      assert results == []
    end

    test "without filter returns all projects" do
      results = Search.search("lib")
      assert results != []
    end
  end

  describe "result structure" do
    test "returns Result structs with all fields" do
      [result | _] = Search.search("auth")
      assert %Result{} = result
      assert is_binary(result.kind)
      assert is_binary(result.project_id)
      assert is_binary(result.external_id)
      assert is_binary(result.title)
      assert is_binary(result.url)
      assert is_float(result.score)
    end
  end

  describe "limit" do
    test "respects limit option" do
      results = Search.search("login", limit: 1)
      assert length(results) <= 1
    end
  end

  describe "FTS query building" do
    test "single token gets prefix wildcard" do
      assert Query.build_fts_query("hello") == "\"hello\"*"
    end

    test "multiple tokens joined with AND, last gets wildcard" do
      assert Query.build_fts_query("fix login") == "\"fix\" AND \"login\"*"
    end

    test "quotes in tokens are escaped" do
      assert Query.build_fts_query("he\"llo") == "\"he\"\"llo\"*"
    end
  end

  describe "resilience" do
    test "does not raise on unusual input" do
      assert is_list(Search.search("*"))
      assert is_list(Search.search("OR AND NOT"))
      assert is_list(Search.search("\"unclosed"))
      assert is_list(Search.search("a b c d e f g h i j"))
    end
  end

  # --- Helpers ---

  defp insert_doc(attrs) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    Repo.query!(
      """
      INSERT INTO search_documents (id, project_id, kind, external_id, title, subtitle, url, search_text, inserted_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        id,
        attrs.project_id,
        attrs.kind,
        attrs.external_id,
        attrs.title,
        attrs.subtitle,
        attrs.url,
        attrs.search_text,
        now,
        now
      ]
    )
  end
end
