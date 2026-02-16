defmodule Spotter.Services.SessionDistiller.ErrorStub do
  @moduledoc "Test stub that returns distillation errors for failure-path testing."
  @behaviour Spotter.Services.SessionDistiller

  @impl true
  def distill(_pack, _opts \\ []) do
    case Process.get(:distiller_error_stub_reason) do
      nil -> {:error, :no_distillation_tool_output}
      reason -> {:error, reason}
    end
  end
end
