defmodule SpotterWeb.ProjectReviewLive do
  use Phoenix.LiveView

  alias Spotter.Services.{ReviewTokenStore, Tmux}
  alias Spotter.Transcripts.{Annotation, Project, Session}
  require Ash.Query

  @review_port Application.compile_env(:spotter, [SpotterWeb.Endpoint, :http, :port], 1100)

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    case Ash.get(Project, project_id) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(project: project)
         |> load_review_data()}

      _ ->
        {:ok, assign(socket, project: nil, sessions: [], open_annotations: [])}
    end
  end

  @impl true
  def handle_event("close_review_session", _params, socket) do
    project = socket.assigns.project

    sessions =
      Session
      |> Ash.Query.filter(project_id == ^project.id)
      |> Ash.Query.select([:id])
      |> Ash.read!()

    session_ids = Enum.map(sessions, & &1.id)

    closed_count =
      if session_ids == [] do
        0
      else
        Annotation
        |> Ash.Query.filter(session_id in ^session_ids and state == :open)
        |> Ash.read!()
        |> Enum.reduce(0, fn ann, acc ->
          Ash.update!(ann, %{}, action: :close)
          acc + 1
        end)
      end

    {:noreply,
     socket
     |> put_flash(:info, "Closed #{closed_count} annotations")
     |> load_review_data()}
  end

  def handle_event("open_conversation", _params, socket) do
    project = socket.assigns.project
    token = ReviewTokenStore.mint(project.id)

    case Tmux.launch_project_review(project.id, token, @review_port) do
      {:ok, name} ->
        {:noreply, put_flash(socket, :info, "Launched review session: #{name}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :info, "Failed to launch: #{reason}")}
    end
  end

  defp load_review_data(socket) do
    project = socket.assigns.project

    sessions =
      Session
      |> Ash.Query.filter(project_id == ^project.id)
      |> Ash.Query.sort(started_at: :desc)
      |> Ash.read!()

    session_ids = Enum.map(sessions, & &1.id)
    sessions_by_id = Map.new(sessions, &{&1.id, &1})

    open_annotations =
      if session_ids == [] do
        []
      else
        Annotation
        |> Ash.Query.filter(session_id in ^session_ids and state == :open)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.read!()
        |> Ash.load!(message_refs: :message)
      end

    assign(socket,
      sessions: sessions,
      sessions_by_id: sessions_by_id,
      open_annotations: open_annotations
    )
  end

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

  defp source_badge(:transcript), do: "Transcript"
  defp source_badge(_), do: "Terminal"

  defp source_badge_color(:transcript), do: "background: #1a4a6b;"
  defp source_badge_color(_), do: "background: #4a3a1a;"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div style="display: flex; align-items: center; gap: 1rem; margin-bottom: 1rem;">
        <a href="/" style="color: #64b5f6; text-decoration: none;">&larr; Back</a>
        <%= if @project do %>
          <h1 style="margin: 0;">Review: {@project.name}</h1>
        <% else %>
          <h1 style="margin: 0;">Project not found</h1>
        <% end %>
      </div>

      <div :if={Phoenix.Flash.get(@flash, :info)} style="background: #1a3a1a; color: #4ade80; padding: 0.5rem 1rem; border-radius: 4px; margin-bottom: 1rem; font-size: 0.9em;">
        {Phoenix.Flash.get(@flash, :info)}
      </div>

      <div :if={Phoenix.Flash.get(@flash, :error)} style="background: #3a1a1a; color: #f87171; padding: 0.5rem 1rem; border-radius: 4px; margin-bottom: 1rem; font-size: 0.9em;">
        {Phoenix.Flash.get(@flash, :error)}
      </div>

      <%= if is_nil(@project) do %>
        <p style="color: #888; font-style: italic;">
          The requested project does not exist.
        </p>
      <% else %>
        <%= if @open_annotations == [] do %>
          <p style="color: #666; font-style: italic;">
            No open annotations for this project.
          </p>
        <% else %>
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.5rem;">
            <span style="color: #888; font-size: 0.9em;">
              {length(@open_annotations)} open annotations across {map_size(@sessions_by_id)} sessions
            </span>
            <div style="display: flex; gap: 0.5rem;">
              <button
                phx-click="open_conversation"
                style="padding: 0.3rem 0.8rem; background: #1a3a1a; border: none; border-radius: 4px; color: #4ade80; cursor: pointer; font-size: 0.8em;"
              >
                Open conversation
              </button>
              <button
                phx-click="close_review_session"
                style="padding: 0.3rem 0.8rem; background: #6b1a1a; border: none; border-radius: 4px; color: #f87171; cursor: pointer; font-size: 0.8em;"
              >
                Close review session
              </button>
            </div>
          </div>

          <%= for ann <- @open_annotations do %>
            <% session = Map.get(@sessions_by_id, ann.session_id) %>
            <div style="background: #1a1a2e; border-radius: 6px; padding: 0.75rem; margin-bottom: 0.5rem;">
              <div style="display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.4rem;">
                <span style={"color: #e0e0e0; font-size: 0.7em; padding: 1px 6px; border-radius: 3px; #{source_badge_color(ann.source)}"}>
                  {source_badge(ann.source)}
                </span>
                <span :if={ann.source == :transcript && ann.message_refs != []} style="color: #666; font-size: 0.7em;">
                  {length(ann.message_refs)} messages
                </span>
                <span :if={session} style="color: #555; font-size: 0.7em;">
                  {session_label(session)}
                </span>
              </div>
              <pre style="margin: 0 0 0.5rem 0; color: #a0a0a0; white-space: pre-wrap; font-size: 0.8em; max-height: 60px; overflow-y: auto;"><%= ann.selected_text %></pre>
              <p style="margin: 0; color: #e0e0e0; font-size: 0.9em;"><%= ann.comment %></p>
              <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 0.5rem;">
                <span style="font-size: 0.75em; color: #555;">
                  <%= Calendar.strftime(ann.inserted_at, "%H:%M") %>
                </span>
                <a
                  :if={session}
                  href={"/sessions/#{session.session_id}"}
                  style="color: #64b5f6; font-size: 0.8em; text-decoration: none;"
                >
                  View session
                </a>
              </div>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end
end
