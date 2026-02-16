defmodule Spotter.Search.Query do
  @moduledoc """
  Executes search queries against the `search_documents` table.

  Fast path: FTS5 `MATCH` with `bm25()` ranking.
  Fallback: `LIKE` queries when FTS5 is unavailable or errors occur.
  """

  require Logger
  require OpenTelemetry.Tracer

  alias Spotter.Observability.ErrorReport
  alias Spotter.Repo
  alias Spotter.Search.Result

  @max_query_bytes 200
  @default_limit 20
  @min_limit 1
  @max_limit 50

  @doc """
  Searches the unified index. Returns `[Result.t()]`, never raises.
  """
  @spec search(String.t(), keyword()) :: [Result.t()]
  def search(q, opts \\ []) do
    OpenTelemetry.Tracer.with_span "spotter.search.query" do
      q = String.trim(to_string(q))
      project_id = opts[:project_id]
      limit = opts[:limit] |> clamp_limit()

      OpenTelemetry.Tracer.set_attribute("spotter.search.q", q)
      OpenTelemetry.Tracer.set_attribute("spotter.search.project_id", project_id || "all")
      OpenTelemetry.Tracer.set_attribute("spotter.search.limit", limit)

      cond do
        q == "" ->
          OpenTelemetry.Tracer.set_attribute("spotter.search.backend", "empty")
          []

        byte_size(q) > @max_query_bytes ->
          OpenTelemetry.Tracer.set_attribute("spotter.search.backend", "too_long")
          []

        true ->
          do_search(q, project_id, limit)
      end
    end
  end

  defp do_search(q, project_id, limit) do
    if fts_available?() do
      case fts_search(q, project_id, limit) do
        {:ok, results} ->
          OpenTelemetry.Tracer.set_attribute("spotter.search.backend", "fts5")
          results

        {:error, _reason} ->
          OpenTelemetry.Tracer.set_attribute("spotter.search.backend", "like_fallback")
          like_search(q, project_id, limit)
      end
    else
      OpenTelemetry.Tracer.set_attribute("spotter.search.backend", "fts_missing")
      like_search(q, project_id, limit)
    end
  end

  # --- FTS5 path ---

  defp fts_search(q, project_id, limit) do
    fts_query = build_fts_query(q)

    {where_clause, params} = fts_where(project_id, fts_query, limit)

    sql = """
    SELECT d.kind, d.project_id, d.external_id, d.title, d.subtitle, d.url,
           bm25(search_documents_fts) AS score
    FROM search_documents_fts
    JOIN search_documents d ON d.rowid = search_documents_fts.rowid
    #{where_clause}
    ORDER BY score
    LIMIT ?
    """

    case Repo.query(sql, params) do
      {:ok, %{rows: rows}} -> {:ok, rows_to_results(rows)}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.warning("FTS5 query failed: #{inspect(e)}")
      ErrorReport.set_trace_error("fts5_query_error", "fts5_query_error", "search.query")
      {:error, e}
  end

  defp fts_where(nil, fts_query, limit) do
    {"WHERE search_documents_fts MATCH ?", [fts_query, limit]}
  end

  defp fts_where(project_id, fts_query, limit) do
    {"WHERE search_documents_fts MATCH ? AND d.project_id = ?", [fts_query, project_id, limit]}
  end

  @doc false
  def build_fts_query(q) do
    tokens =
      q
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&escape_fts_token/1)

    case tokens do
      [] ->
        ""

      [single] ->
        "\"#{single}\"*"

      many ->
        {leading, [last]} = Enum.split(many, -1)
        parts = Enum.map(leading, &"\"#{&1}\"") ++ ["\"#{last}\"*"]
        Enum.join(parts, " AND ")
    end
  end

  defp escape_fts_token(token) do
    String.replace(token, "\"", "\"\"")
  end

  # --- LIKE fallback path ---

  defp like_search(q, project_id, limit) do
    pattern = "%#{escape_like(q)}%"
    prefix_pattern = "#{escape_like(q)}%"

    {where_clause, params} = like_where(project_id, pattern, prefix_pattern, limit)

    sql = """
    SELECT kind, project_id, external_id, title, subtitle, url,
           CASE
             WHEN title LIKE ? THEN 1.0
             WHEN external_id LIKE ? THEN 2.0
             WHEN search_text LIKE ? THEN 3.0
             ELSE 4.0
           END AS score
    FROM search_documents
    #{where_clause}
    ORDER BY score ASC, title ASC
    LIMIT ?
    """

    case Repo.query(sql, params) do
      {:ok, %{rows: rows}} ->
        rows_to_results(rows)

      {:error, reason} ->
        Logger.warning("LIKE search failed: #{inspect(reason)}")
        ErrorReport.set_trace_error("like_query_error", "like_query_error", "search.query")
        []
    end
  rescue
    e ->
      Logger.warning("LIKE search failed: #{inspect(e)}")
      ErrorReport.set_trace_error("like_query_error", "like_query_error", "search.query")
      []
  end

  defp like_where(nil, pattern, prefix_pattern, limit) do
    where = "WHERE (title LIKE ? OR external_id LIKE ? OR search_text LIKE ?)"
    {where, [prefix_pattern, prefix_pattern, pattern, pattern, prefix_pattern, pattern, limit]}
  end

  defp like_where(project_id, pattern, prefix_pattern, limit) do
    where =
      "WHERE project_id = ? AND (title LIKE ? OR external_id LIKE ? OR search_text LIKE ?)"

    {where,
     [
       prefix_pattern,
       prefix_pattern,
       pattern,
       project_id,
       pattern,
       prefix_pattern,
       pattern,
       limit
     ]}
  end

  defp escape_like(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  # --- Shared helpers ---

  defp fts_available? do
    case Repo.query(
           "SELECT 1 FROM sqlite_master WHERE type='table' AND name='search_documents_fts' LIMIT 1"
         ) do
      {:ok, %{rows: [_ | _]}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp rows_to_results(rows) do
    Enum.map(rows, fn [kind, project_id, external_id, title, subtitle, url, score] ->
      %Result{
        kind: kind,
        project_id: project_id,
        external_id: external_id,
        title: title,
        subtitle: subtitle,
        url: url,
        score: score / 1.0
      }
    end)
  end

  defp clamp_limit(nil), do: @default_limit
  defp clamp_limit(n) when is_integer(n), do: max(@min_limit, min(n, @max_limit))
  defp clamp_limit(_), do: @default_limit
end
