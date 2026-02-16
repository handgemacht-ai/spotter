defmodule Spotter.Search.ReindexProjectJobTest do
  use Spotter.DataCase, async: false

  alias Spotter.Search
  alias Spotter.Search.Indexer

  @project_id "00000000-0000-0000-0000-000000000099"

  setup do
    # Create a minimal project
    Repo.query!(
      "INSERT INTO projects (id, name, pattern, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?)",
      [@project_id, "test-project", "test/*", DateTime.utc_now(), DateTime.utc_now()]
    )

    # Create a session
    session_id = Ecto.UUID.generate()
    session_pk = Ecto.UUID.generate()
    now = DateTime.utc_now()

    Repo.query!(
      """
      INSERT INTO sessions (id, session_id, project_id, slug, schema_version, inserted_at, updated_at)
      VALUES (?, ?, ?, ?, 1, ?, ?)
      """,
      [session_pk, session_id, @project_id, "test-session", now, now]
    )

    # Create a commit and link it to the session
    commit_id = Ecto.UUID.generate()

    Repo.query!(
      "INSERT INTO commits (id, commit_hash, subject, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?)",
      [commit_id, "abc123def456", "Fix auth bug", now, now]
    )

    Repo.query!(
      """
      INSERT INTO session_commit_links (id, session_id, commit_id, link_type, confidence, inserted_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      [Ecto.UUID.generate(), session_pk, commit_id, "observed_in_session", 1.0, now, now]
    )

    %{session_id: session_id, commit_id: commit_id}
  end

  describe "reindex_project/1" do
    test "indexes sessions and commits" do
      assert :ok = Indexer.reindex_project(@project_id)

      results = Search.search("test-session", project_id: @project_id)
      assert Enum.any?(results, &(&1.kind == "session"))

      results = Search.search("auth bug", project_id: @project_id)
      assert Enum.any?(results, &(&1.kind == "commit"))
    end

    test "is idempotent" do
      assert :ok = Indexer.reindex_project(@project_id)
      assert :ok = Indexer.reindex_project(@project_id)

      # Should not duplicate documents
      {:ok, %{rows: [[count]]}} =
        Repo.query(
          "SELECT COUNT(*) FROM search_documents WHERE project_id = ? AND kind = 'session'",
          [@project_id]
        )

      assert count == 1
    end

    test "sweeps stale documents" do
      # Insert a stale doc that won't be regenerated
      Repo.query!(
        """
        INSERT INTO search_documents (id, project_id, kind, external_id, title, url, search_text, inserted_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
          Ecto.UUID.generate(),
          @project_id,
          "session",
          "stale-session-id",
          "Stale session",
          "/sessions/stale",
          "stale session",
          ~U[2020-01-01 00:00:00Z],
          ~U[2020-01-01 00:00:00Z]
        ]
      )

      # Verify stale doc exists
      {:ok, %{rows: [[1]]}} =
        Repo.query(
          "SELECT COUNT(*) FROM search_documents WHERE external_id = ?",
          ["stale-session-id"]
        )

      # Reindex should remove it
      assert :ok = Indexer.reindex_project(@project_id)

      {:ok, %{rows: [[0]]}} =
        Repo.query(
          "SELECT COUNT(*) FROM search_documents WHERE external_id = ?",
          ["stale-session-id"]
        )
    end

    test "succeeds even when repo root is unavailable" do
      # No cwd set on sessions, so resolve_repo_root will fail
      # But indexer should still succeed for non-file kinds
      assert :ok = Indexer.reindex_project(@project_id)

      {:ok, %{rows: rows}} =
        Repo.query(
          "SELECT kind FROM search_documents WHERE project_id = ?",
          [@project_id]
        )

      kinds = Enum.map(rows, fn [k] -> k end)
      assert "session" in kinds
      assert "commit" in kinds
      # file/directory won't be present since no repo root
      refute "file" in kinds
    end
  end
end
