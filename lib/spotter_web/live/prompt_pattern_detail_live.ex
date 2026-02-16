defmodule SpotterWeb.PromptPatternDetailLive do
  @moduledoc false
  use Phoenix.LiveView
  use AshComputer.LiveView

  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Services.TranscriptRenderer
  alias Spotter.Transcripts.{Annotation, AnnotationMessageRef}

  attach_computer(SpotterWeb.Live.PromptPatternDetailComputers, :pattern_detail)

  @impl true
  def mount(%{"pattern_id" => pattern_id}, _session, socket) do
    socket =
      socket
      |> mount_computers(%{pattern_detail: %{pattern_id: pattern_id}})
      |> assign(selected_match: nil, annotation_comment: "")

    {:ok, socket}
  end

  @impl true
  def handle_event("select_match", %{"match-id" => match_id}, socket) do
    match = Enum.find(socket.assigns.pattern_detail_matches, &(&1.id == match_id))
    {:noreply, assign(socket, selected_match: match, annotation_comment: "")}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_match: nil, annotation_comment: "")}
  end

  def handle_event("save_annotation", %{"comment" => comment}, socket) do
    match = socket.assigns.selected_match
    pattern = socket.assigns.pattern_detail_pattern

    if match && comment != "" do
      Tracer.with_span "spotter.prompt_pattern_detail.save_annotation" do
        Tracer.set_attribute("spotter.pattern_id", pattern.id)
        Tracer.set_attribute("spotter.match_id", match.id)

        prompt_text =
          match.message.content
          |> TranscriptRenderer.extract_text()
          |> String.slice(0, 500)

        annotation =
          Ash.create!(Annotation, %{
            source: :prompt_pattern,
            session_id: match.session_id,
            selected_text: prompt_text,
            comment: comment,
            purpose: :review,
            metadata: %{
              "pattern_id" => pattern.id,
              "pattern_label" => pattern.label
            }
          })

        Ash.create!(AnnotationMessageRef, %{
          annotation_id: annotation.id,
          message_id: match.message.id,
          ordinal: 0
        })
      end

      socket =
        socket
        |> assign(selected_match: nil, annotation_comment: "")
        |> put_flash(:info, "Annotation created")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Comment cannot be empty")}
    end
  end

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

  defp format_confidence(nil), do: ""
  defp format_confidence(c), do: "#{round(c * 100)}%"

  @impl true
  def render(assigns) do
    ~H"""
    <div data-testid="prompt-pattern-detail-root">
      <%= case @pattern_detail_error_state do %>
        <% :not_found -> %>
          <div class="breadcrumb">
            <a href="/">Dashboard</a>
            <span class="breadcrumb-sep">/</span>
            <span class="breadcrumb-current">Pattern not found</span>
          </div>
          <div class="terminal-connecting">
            <div>
              <div class="terminal-connecting-title">Pattern not found</div>
              <div class="terminal-connecting-subtitle">
                The requested prompt pattern could not be found.
              </div>
            </div>
          </div>
        <% _ -> %>
          <div class="breadcrumb">
            <a href="/">Dashboard</a>
            <span class="breadcrumb-sep">/</span>
            <span class="breadcrumb-current">{@pattern_detail_pattern.label}</span>
          </div>

          <%!-- Pattern header card --%>
          <div class="commit-detail-header mb-4">
            <h2 class="commit-detail-subject">{@pattern_detail_pattern.label}</h2>
            <div class="commit-detail-info">
              <code class="text-sm">{@pattern_detail_pattern.needle}</code>
              <span class="badge">{@pattern_detail_pattern.count_total} matches</span>
              <span
                :if={@pattern_detail_pattern.confidence}
                class="badge badge-inferred"
              >
                {format_confidence(@pattern_detail_pattern.confidence)}
              </span>
            </div>
          </div>

          <%!-- Match list --%>
          <div class="commit-detail-section-title mb-2">
            Matches ({length(@pattern_detail_matches)})
          </div>

          <%= if @pattern_detail_matches == [] do %>
            <div class="empty-state">No matches found for this pattern.</div>
          <% else %>
            <div class="pattern-match-list">
              <div
                :for={match <- @pattern_detail_matches}
                class="pattern-match-row"
                phx-click="select_match"
                phx-value-match-id={match.id}
                data-testid="pattern-match-row"
              >
                <div class="pattern-match-prompt">
                  {TranscriptRenderer.extract_text(match.message.content)
                  |> String.slice(0, 300)}
                </div>
                <div class="pattern-match-meta">
                  <a href={"/sessions/#{match.session.session_id}"} class="file-link">
                    {session_label(match.session)}
                  </a>
                  <span :if={match.session.project}>
                    {match.session.project.name}
                  </span>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Annotation form (when match selected) --%>
          <%= if @selected_match do %>
            <div class="pattern-annotation-form mt-3" data-testid="annotation-form">
              <div class="commit-detail-section-title mb-2">
                Annotate match
              </div>
              <div class="pattern-match-prompt mb-2">
                {TranscriptRenderer.extract_text(@selected_match.message.content)
                |> String.slice(0, 300)}
              </div>
              <form phx-submit="save_annotation">
                <textarea
                  name="comment"
                  class="form-textarea"
                  placeholder="Add a review comment..."
                  rows="3"
                  phx-debounce="300"
                >{@annotation_comment}</textarea>
                <div class="mt-2" style="display: flex; gap: var(--space-2);">
                  <button type="submit" class="btn btn-success">Save annotation</button>
                  <button type="button" class="btn" phx-click="clear_selection">Cancel</button>
                </div>
              </form>
            </div>
          <% end %>
      <% end %>
    </div>
    """
  end
end
