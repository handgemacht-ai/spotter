defmodule Spotter.Services.ProjectRollupDistiller.Stub do
  @moduledoc "Test stub for project rollup distillation that returns canned responses."
  @behaviour Spotter.Services.ProjectRollupDistiller

  @impl true
  def distill(_pack, _opts \\ []) do
    {:ok,
     %{
       summary_json: %{
         "period_summary" => "Active development on timezone and distillation features",
         "themes" => ["infrastructure", "observability"],
         "open_threads" => [],
         "risks" => []
       },
       summary_text: "Active development on timezone and distillation features",
       model_used: "stub-model",
       raw_response_text:
         ~s({"period_summary":"Active development on timezone and distillation features"})
     }}
  end
end
