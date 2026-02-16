defmodule SpotterWeb.SearchController do
  @moduledoc "Global search endpoint merging FTS results and product spec."

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
          merge_results(q, project_id, limit)
        end

      conn
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{ok: true, q: q, results: results})
    end
  end

  defp merge_results(q, project_id, limit) do
    fts_results = safe_fts_search(q, project_id, limit)
    product_results = safe_product_search(q, project_id, limit)

    (fts_results ++ product_results)
    |> Enum.uniq_by(&{&1.kind, &1.project_id, &1.external_id, &1.url})
    |> Enum.sort_by(&{&1.score, &1.title}, :asc)
    |> Enum.take(limit)
    |> Enum.map(&result_to_json/1)
  end

  defp safe_fts_search(q, project_id, limit) do
    Spotter.Search.search(q, project_id: project_id, limit: limit)
  rescue
    e ->
      OtelTraceHelpers.set_error("fts_search_error", %{"error.message" => inspect(e)})
      []
  end

  defp safe_product_search(q, project_id, limit) do
    if Spotter.ProductSpec.dolt_available?() do
      per_kind = max(div(limit, 3), 3)

      domains = Spotter.ProductSpec.search_domains(project_id, q, per_kind)
      features = Spotter.ProductSpec.search_features(project_id, q, per_kind)
      requirements = Spotter.ProductSpec.search_requirements(project_id, q, per_kind)

      product_url = product_url(project_id, q)

      to_product_results(domains, "product_domain", project_id, product_url) ++
        to_product_results(features, "product_feature", project_id, product_url) ++
        to_product_results(requirements, "product_requirement", project_id, product_url)
    else
      []
    end
  rescue
    e ->
      OtelTraceHelpers.set_error("product_search_error", %{"error.message" => inspect(e)})
      []
  end

  defp to_product_results(rows, kind, project_id, url) do
    Enum.map(rows, &product_row_to_result(&1, kind, project_id, url))
  end

  defp product_row_to_result(row, kind, project_id, url) do
    %Spotter.Search.Result{
      kind: kind,
      project_id: project_id || row[:project_id] || "",
      external_id: first_present([row[:id], row[:spec_key]]),
      title: first_present([row[:name], row[:statement], row[:spec_key]]),
      subtitle: first_present([row[:description], row[:spec_key]]),
      url: url,
      score: 50.0
    }
  end

  defp first_present(values), do: Enum.find(values, "", &(&1 != nil && &1 != ""))

  defp product_url(project_id, q) do
    base = "/specs?artifact=product&spec_view=snapshot&q=#{URI.encode_www_form(q)}"
    if project_id, do: base <> "&project_id=#{project_id}", else: base
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
