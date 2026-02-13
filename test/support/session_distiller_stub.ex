defmodule Spotter.Services.SessionDistiller.Stub do
  @moduledoc "Test stub for session distillation that returns canned responses without LLM calls."
  @behaviour Spotter.Services.SessionDistiller

  @impl true
  def distill(_pack, _opts \\ []) do
    {:ok,
     %{
       summary_json: %{
         "session_summary" => "Implemented timezone support for projects",
         "what_changed" => ["Added tzdata dependency", "Added timezone attribute to Project"],
         "key_files" => [
           %{"path" => "lib/spotter/transcripts/project.ex", "reason" => "Added timezone field"}
         ],
         "commands_run" => ["mix test"],
         "open_threads" => [],
         "risks" => []
       },
       summary_text: "Implemented timezone support for projects",
       model_used: "stub-model",
       raw_response_text: ~s({"session_summary":"Implemented timezone support for projects"})
     }}
  end
end
