defmodule Spotter.Services.ProjectRollupDistiller do
  @moduledoc """
  Distills a project rollup pack into a structured summary using an LLM.

  Supports pluggable adapters via application config:

      config :spotter, :project_rollup_distiller_adapter, MyAdapter
  """

  @callback distill(pack :: map(), opts :: keyword()) ::
              {:ok,
               %{
                 summary_json: map(),
                 summary_text: String.t(),
                 model_used: String.t(),
                 raw_response_text: String.t()
               }}
              | {:error, term()}

  @doc "Distills the given pack using the configured adapter."
  def distill(pack, opts \\ []) do
    adapter().distill(pack, opts)
  end

  defp adapter do
    Application.get_env(
      :spotter,
      :project_rollup_distiller_adapter,
      Spotter.Services.ProjectRollupDistiller.Anthropic
    )
  end
end
