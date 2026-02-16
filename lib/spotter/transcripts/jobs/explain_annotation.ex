defmodule Spotter.Transcripts.Jobs.ExplainAnnotation do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [keys: [:annotation_id], period: 300]

  alias Spotter.Observability.{FlowHub, FlowKeys}
  alias Spotter.Services.AnnotationExplainPrompt
  alias Spotter.Telemetry.TraceContext

  alias Spotter.Transcripts.{
    Annotation,
    Flashcard,
    ReviewItem
  }

  require OpenTelemetry.Tracer, as: Tracer

  @model "haiku"
  @timeout_ms 120_000
  @delta_throttle_ms 50

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"annotation_id" => annotation_id}}) do
    Tracer.with_span "spotter.annotations.explain.job",
      attributes: %{
        annotation_id: annotation_id,
        "spotter.model_requested": @model,
        "spotter.timeout_ms": @timeout_ms
      } do
      run_explain(annotation_id, job_id)
    end
  end

  defp run_explain(annotation_id, job_id) do
    annotation =
      Annotation
      |> Ash.get!(annotation_id)
      |> Ash.load!([:session, :file_refs, message_refs: :message])

    run_id = "explain-#{annotation.id}-job-#{job_id || "unknown"}"

    flow_keys =
      [
        FlowKeys.agent_run(run_id),
        FlowKeys.session(annotation.session.session_id),
        if(job_id, do: FlowKeys.oban(to_string(job_id)))
      ]
      |> Enum.reject(&is_nil/1)

    traceparent = TraceContext.current_traceparent()

    update_explain_metadata(annotation, %{
      "status" => "pending",
      "started_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "model" => "haiku"
    })

    Tracer.set_attribute(:session_id, annotation.session_id)

    emit_flow_event("agent.run.start", :running, flow_keys, traceparent, %{
      "run_id" => run_id,
      "annotation_id" => annotation.id,
      "job_id" => job_id
    })

    case stream_explanation(annotation, flow_keys, traceparent) do
      {:ok, answer, references} ->
        finalize_success(annotation, answer, references)
        emit_flow_event("agent.run.stop", :ok, flow_keys, traceparent, %{"run_id" => run_id})

      {:error, reason} ->
        finalize_error(annotation, reason)
        emit_flow_event("agent.run.stop", :error, flow_keys, traceparent, %{"run_id" => run_id})
        {:error, reason}
    end
  rescue
    e ->
      reason = Exception.message(e)
      Tracer.set_status(:error, reason)

      try do
        annotation = Ash.get!(Annotation, annotation_id)
        finalize_error(annotation, reason)
      rescue
        _ -> :ok
      end

      {:error, reason}
  end

  defp stream_explanation(annotation, flow_keys, _traceparent) do
    Tracer.with_span "spotter.annotations.explain.agent_stream",
      attributes: %{
        annotation_id: annotation.id,
        "spotter.model_requested": @model,
        "spotter.timeout_ms": @timeout_ms
      } do
      prompts = AnnotationExplainPrompt.build(annotation)
      streaming_mod = streaming_module()

      {:ok, session} =
        streaming_mod.start_session(%ClaudeAgentSDK.Options{
          model: @model,
          system_prompt: prompts.system,
          allowed_tools: ["WebSearch", "WebFetch"],
          max_turns: 5,
          timeout_ms: @timeout_ms,
          permission_mode: :dont_ask
        })

      started_at_ms = System.monotonic_time(:millisecond)
      last_delta_at_ms = started_at_ms - @delta_throttle_ms - 1

      try do
        {answer, _last_delta_at_ms} =
          streaming_mod.send_message(session, prompts.user)
          |> Enum.reduce({"", last_delta_at_ms}, fn event, {acc, last_delta} ->
            elapsed = System.monotonic_time(:millisecond) - started_at_ms

            if elapsed > @timeout_ms do
              raise "stream_timeout: exceeded #{@timeout_ms}ms wall clock"
            end

            case event do
              %{type: :text_delta, text: chunk} ->
                broadcast_delta(annotation.id, chunk)
                now = System.monotonic_time(:millisecond)

                last_delta =
                  if now - last_delta >= @delta_throttle_ms do
                    emit_flow_event("agent.output.delta", :running, flow_keys, nil, %{
                      "text" => chunk
                    })

                    now
                  else
                    last_delta
                  end

                {acc <> chunk, last_delta}

              %{type: :message_stop, final_text: final} when is_binary(final) ->
                {final, last_delta}

              _ ->
                {acc, last_delta}
            end
          end)

        references = parse_references(answer)
        {:ok, answer, references}
      rescue
        e ->
          {:error, Exception.message(e)}
      after
        streaming_mod.close_session(session)
      end
    end
  end

  defp emit_flow_event(kind, status, flow_keys, traceparent, payload) do
    FlowHub.record(%{
      kind: kind,
      status: status,
      flow_keys: flow_keys,
      summary: "ExplainAnnotation #{kind}",
      traceparent: traceparent,
      payload: payload
    })
  rescue
    _ -> :ok
  end

  defp finalize_success(annotation, answer, references) do
    update_explain_metadata(annotation, %{
      "status" => "complete",
      "answer" => answer,
      "references" => references,
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    question = non_empty(annotation.comment)
    project_id = annotation.session.project_id

    with {:ok, flashcard} <-
           Ash.create(Flashcard, %{
             project_id: project_id,
             annotation_id: annotation.id,
             question: question,
             front_snippet: annotation.selected_text,
             answer: answer,
             references: %{"urls" => Enum.map(references, & &1["url"])}
           }),
         {:ok, _review_item} <- find_or_create_review_item(flashcard) do
      broadcast_done(annotation.id, answer, references)
      :ok
    end
  end

  defp find_or_create_review_item(flashcard) do
    require Ash.Query

    case ReviewItem
         |> Ash.Query.filter(flashcard_id == ^flashcard.id and target_kind == :flashcard)
         |> Ash.read_one() do
      {:ok, nil} ->
        Ash.create(ReviewItem, %{
          project_id: flashcard.project_id,
          target_kind: :flashcard,
          flashcard_id: flashcard.id,
          importance: :medium,
          interval_days: 1,
          next_due_on: Date.utc_today()
        })

      {:ok, existing} ->
        {:ok, existing}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finalize_error(annotation, reason) do
    Tracer.set_status(:error, reason)

    update_explain_metadata(annotation, %{
      "status" => "error",
      "error" => reason,
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    broadcast_error(annotation.id, reason)
  end

  defp update_explain_metadata(annotation, new_fields) do
    existing = Map.get(annotation.metadata, "explain", %{})
    merged = Map.merge(existing, new_fields)
    metadata = Map.put(annotation.metadata, "explain", merged)
    Ash.update!(annotation, %{metadata: metadata})
  end

  defp parse_references(text) do
    case String.split(text, ~r/References:\s*\n/i) do
      [_ | rest] when rest != [] ->
        rest
        |> List.last()
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "- "))
        |> Enum.map(fn line ->
          url = line |> String.trim_leading("- ") |> String.trim()
          %{"title" => nil, "url" => url}
        end)

      _ ->
        []
    end
  end

  defp broadcast_delta(annotation_id, chunk) do
    Phoenix.PubSub.broadcast(
      Spotter.PubSub,
      "annotation_explain:#{annotation_id}",
      {:annotation_explain_delta, annotation_id, chunk}
    )
  end

  defp broadcast_done(annotation_id, final_text, references) do
    Phoenix.PubSub.broadcast(
      Spotter.PubSub,
      "annotation_explain:#{annotation_id}",
      {:annotation_explain_done, annotation_id, final_text, references}
    )
  end

  defp broadcast_error(annotation_id, reason) do
    Phoenix.PubSub.broadcast(
      Spotter.PubSub,
      "annotation_explain:#{annotation_id}",
      {:annotation_explain_error, annotation_id, reason}
    )
  end

  defp streaming_module do
    Application.get_env(:spotter, :claude_streaming_module, ClaudeAgentSDK.Streaming)
  end

  defp non_empty(nil), do: nil
  defp non_empty(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: s)
end
