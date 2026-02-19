defmodule SpotterWeb.SearchController do
  @moduledoc "Global search endpoint for FTS results."

  use Phoenix.Controller, formats: [:json]

  require SpotterWeb.OtelTraceHelpers
  alias SpotterWeb.OtelTraceHelpers

  @max_q_bytes 200

  def index(conn, params) do
    q = params["q"] |> to_string() |> String.trim()
    project_id = params["project_id"]
    limit = parse_limit(params["limit"])

    OtelTraceHelpers.with_span "spotter.web.search", %{
      "spotter.search.q" => q,
      "spotter.search.project_id" => project_id || "all",
      "spotter.search.limit" => limit
    } do
      results =
        if q == "" or byte_size(q) > @max_q_bytes do
          []
        else
          safe_fts_search(q, project_id, limit)
          |> Enum.sort_by(&{&1.score, &1.title}, :asc)
          |> Enum.take(limit)
          |> Enum.map(&result_to_json/1)
        end

      conn
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{ok: true, q: q, results: results})
    end
  end

  defp safe_fts_search(q, project_id, limit) do
    Spotter.Search.search(q, project_id: project_id, limit: limit)
  rescue
    e ->
      OtelTraceHelpers.set_error("fts_search_error", %{
        "error.message" => inspect(e),
        "error.source" => "search_controller"
      })

      []
  end

  defp result_to_json(r) do
    %{
      kind: r.kind,
      project_id: r.project_id,
      external_id: r.external_id,
      title: r.title,
      subtitle: r.subtitle,
      url: r.url,
      score: r.score
    }
  end

  defp parse_limit(nil), do: 20
  defp parse_limit(val) when is_binary(val), do: parse_limit(String.to_integer(val))
  defp parse_limit(n) when is_integer(n), do: max(1, min(n, 50))
  defp parse_limit(_), do: 20
end
