defmodule SpotterWeb.PaneListLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  alias Spotter.Transcripts.{
    ProjectIngestState,
    Session,
    SessionPresenter,
    SessionRework,
    Subagent,
    ToolCall
  }

  alias Spotter.Transcripts.Jobs.IngestRecentCommits

  require OpenTelemetry.Tracer, as: Tracer

  require Ash.Query

  @sessions_per_page 20

  computer :project_filter do
    input :selected_project_id do
      initial nil
    end

    val :projects do
      compute(fn _inputs ->
        try do
          Spotter.Transcripts.Project |> Ash.read!()
        rescue
          _ -> []
        end
      end)

      depends_on([])
    end
  end

  computer :session_data do
    input :projects do
      initial []
    end
  end

  computer :tool_call_stats do
    input :session_ids do
      initial []
    end

    val :stats do
      compute(fn %{session_ids: session_ids} ->
        if session_ids == [] do
          %{}
        else
          try do
            ToolCall
            |> Ash.Query.filter(session_id in ^session_ids)
            |> Ash.read!()
            |> Enum.group_by(& &1.session_id)
            |> Map.new(fn {sid, calls} ->
              failed = Enum.count(calls, & &1.is_error)
              {sid, %{total: length(calls), failed: failed}}
            end)
          rescue
            _ -> %{}
          end
        end
      end)
    end
  end

  computer :rework_stats do
    input :session_ids do
      initial []
    end

    val :stats do
      compute(fn %{session_ids: session_ids} ->
        if session_ids == [] do
          %{}
        else
          try do
            SessionRework
            |> Ash.Query.filter(session_id in ^session_ids)
            |> Ash.read!()
            |> Enum.group_by(& &1.session_id)
            |> Map.new(fn {sid, records} ->
              {sid, %{count: length(records)}}
            end)
          rescue
            _ -> %{}
          end
        end
      end)
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Spotter.PubSub, "session_activity")
    end

    socket =
      socket
      |> assign(active_status_map: %{})
      |> assign(timezone_errors: %{})
      |> assign(hidden_expanded: %{})
      |> assign(expanded_subagents: %{})
      |> assign(subagents_by_session: %{})
      |> assign(show_import_modal: false)
      |> assign(import_transcripts: [])
      |> assign(all_import_transcripts: [])
      |> assign(import_project_filter: nil)
      |> assign(import_pagination: %{total_count: 0, page: 1, per_page: 20})
      |> assign(import_sort_by: "last_modified")
      |> assign(selected_transcripts: MapSet.new())
      |> mount_computers()
      |> load_session_data()
      |> ensure_default_project_filter()

    if connected?(socket), do: maybe_enqueue_commit_ingest(socket)

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    Tracer.with_span "spotter.pane_list_live.filter_project" do
      parsed_id =
        case raw_id do
          "all" -> nil
          nil -> nil
          "" -> nil
          id -> id
        end

      parsed_id = normalize_project_filter_id(socket.assigns.session_data_projects, parsed_id)

      Tracer.set_attribute("spotter.project_id", parsed_id || "all")

      socket =
        update_computer_inputs(socket, :project_filter, %{selected_project_id: parsed_id})

      {:noreply, socket}
    end
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_session_data(socket)}
  end

  def handle_event("review_session", %{"session-id" => session_id}, socket) do
    {:noreply, push_navigate(socket, to: "/sessions/#{session_id}")}
  end

  def handle_event("hide_session", %{"id" => id}, socket) do
    session = Ash.get!(Spotter.Transcripts.Session, id)
    Ash.update!(session, %{}, action: :hide)
    {:noreply, load_session_data(socket)}
  end

  def handle_event("unhide_session", %{"id" => id}, socket) do
    session = Ash.get!(Spotter.Transcripts.Session, id)
    Ash.update!(session, %{}, action: :unhide)
    {:noreply, load_session_data(socket)}
  end

  def handle_event("toggle_subagents", %{"session-id" => session_id}, socket) do
    expanded = socket.assigns.expanded_subagents
    current = Map.get(expanded, session_id, false)
    {:noreply, assign(socket, expanded_subagents: Map.put(expanded, session_id, !current))}
  end

  def handle_event("toggle_hidden_section", %{"project-id" => project_id}, socket) do
    hidden_expanded = socket.assigns.hidden_expanded
    current = Map.get(hidden_expanded, project_id, false)
    {:noreply, assign(socket, hidden_expanded: Map.put(hidden_expanded, project_id, !current))}
  end

  def handle_event(
        "load_more_sessions",
        %{"project-id" => project_id, "visibility" => visibility},
        socket
      ) do
    visibility = String.to_existing_atom(visibility)
    {:noreply, append_session_page(socket, project_id, visibility)}
  end

  def handle_event("update_timezone", %{"project_id" => id, "timezone" => tz}, socket) do
    project = Ash.get!(Spotter.Transcripts.Project, id)

    case Ash.update(project, %{timezone: tz}) do
      {:ok, _} ->
        errors = Map.delete(socket.assigns.timezone_errors, id)
        {:noreply, socket |> assign(timezone_errors: errors) |> load_session_data()}

      {:error, changeset} ->
        msg = extract_timezone_error(changeset)

        {:noreply,
         assign(socket, timezone_errors: Map.put(socket.assigns.timezone_errors, id, msg))}
    end
  end

  def handle_event("open_import_modal", _params, socket) do
    Tracer.with_span "spotter.import_modal.open" do
      Tracer.set_attribute("source", "dashboard_header")
      {:noreply, assign(socket, show_import_modal: true, import_transcripts: [])}
    end
  end

  def handle_event("close_import_modal", _params, socket) do
    {:noreply, assign(socket, show_import_modal: false)}
  end

  def handle_event("import_page", %{"page" => page}, socket) do
    page = String.to_integer(page)
    pagination = Map.put(socket.assigns.import_pagination, :page, page)
    {:noreply, assign(socket, import_pagination: pagination)}
  end

  def handle_event("toggle_select_all", _params, socket) do
    non_imported =
      socket.assigns.import_transcripts
      |> Enum.reject(& &1.already_imported)
      |> Enum.map(& &1.file_path)
      |> MapSet.new()

    selected =
      if MapSet.equal?(socket.assigns.selected_transcripts, non_imported),
        do: MapSet.new(),
        else: non_imported

    {:noreply, assign(socket, selected_transcripts: selected)}
  end

  def handle_event("toggle_select_transcript", %{"path" => path}, socket) do
    selected = socket.assigns.selected_transcripts

    selected =
      if MapSet.member?(selected, path),
        do: MapSet.delete(selected, path),
        else: MapSet.put(selected, path)

    {:noreply, assign(socket, selected_transcripts: selected)}
  end

  def handle_event("sort_import_transcripts", %{"sort_by" => sort_by}, socket) do
    field = String.to_existing_atom(sort_by)

    sorted =
      case field do
        :last_modified ->
          Enum.sort_by(socket.assigns.import_transcripts, & &1.last_modified, {:desc, DateTime})

        :project_name ->
          Enum.sort_by(socket.assigns.import_transcripts, & &1.project_name, :desc)

        _ ->
          Enum.sort_by(socket.assigns.import_transcripts, &Map.get(&1, field), :desc)
      end

    {:noreply, assign(socket, import_transcripts: sorted, import_sort_by: sort_by)}
  end

  def handle_event("filter_import_project", %{"project_filter" => project}, socket) do
    filtered =
      case project do
        "" -> socket.assigns.all_import_transcripts
        name -> Enum.filter(socket.assigns.all_import_transcripts, &(&1.project_name == name))
      end

    {:noreply, assign(socket, import_transcripts: filtered, import_project_filter: project)}
  end

  @impl true
  def handle_info({:update_import_pagination, meta}, socket) do
    {:noreply, assign(socket, import_pagination: meta)}
  end

  def handle_info({:update_import_transcripts, transcripts}, socket) do
    {:noreply,
     assign(socket, import_transcripts: transcripts, all_import_transcripts: transcripts)}
  end

  def handle_info({:session_activity, %{session_id: session_id, status: status}}, socket) do
    active_status_map = Map.put(socket.assigns.active_status_map, session_id, status)
    {:noreply, assign(socket, active_status_map: active_status_map)}
  end

  @ingest_cooldown_seconds 600

  defp maybe_enqueue_commit_ingest(socket) do
    projects = socket.assigns.session_data_projects
    selected = socket.assigns.project_filter_selected_project_id

    project_ids =
      if selected do
        [selected]
      else
        Enum.map(projects, & &1.id)
      end

    Enum.each(project_ids, fn pid ->
      if should_enqueue_ingest?(pid) do
        Ash.create(ProjectIngestState, %{
          project_id: pid,
          last_commit_ingest_at: DateTime.utc_now()
        })

        %{project_id: pid}
        |> IngestRecentCommits.new()
        |> Oban.insert()
      end
    end)
  end

  defp should_enqueue_ingest?(project_id) do
    case ProjectIngestState
         |> Ash.Query.filter(project_id == ^project_id)
         |> Ash.read_one() do
      {:ok, nil} ->
        true

      {:ok, %{last_commit_ingest_at: nil}} ->
        true

      {:ok, %{last_commit_ingest_at: last}} ->
        DateTime.diff(DateTime.utc_now(), last, :second) >= @ingest_cooldown_seconds

      _ ->
        true
    end
  end

  defp extract_timezone_error(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.find_value(fn
      %Ash.Error.Changes.InvalidAttribute{field: :timezone, message: msg} -> msg
      _ -> nil
    end) || "invalid timezone"
  end

  defp extract_timezone_error(_), do: "invalid timezone"

  defp load_session_data(socket) do
    projects =
      Spotter.Transcripts.Project
      |> Ash.read!()
      |> Enum.map(fn project ->
        {visible, visible_meta} = load_project_sessions(project.id, :visible)
        {hidden, hidden_meta} = load_project_sessions(project.id, :hidden)

        Map.merge(project, %{
          visible_sessions: visible,
          hidden_sessions: hidden,
          visible_cursor: visible_meta.next_cursor,
          visible_has_more: visible_meta.has_more,
          hidden_cursor: hidden_meta.next_cursor,
          hidden_has_more: hidden_meta.has_more
        })
      end)

    session_ids = extract_session_ids(projects)

    subagents_by_session = load_subagents_for_sessions(session_ids)

    socket
    |> assign(session_data_projects: projects)
    |> ensure_default_project_filter_for_projects()
    |> assign(subagents_by_session: subagents_by_session)
    |> update_computer_inputs(:session_data, %{projects: projects})
    |> update_computer_inputs(:tool_call_stats, %{session_ids: session_ids})
    |> update_computer_inputs(:rework_stats, %{session_ids: session_ids})
  end

  defp ensure_default_project_filter(socket) do
    socket
    |> assign(session_data_projects: socket.assigns.session_data_projects || [])
    |> ensure_default_project_filter_for_projects()
  end

  defp ensure_default_project_filter_for_projects(socket) do
    selected_project_id =
      normalize_project_filter_id(
        socket.assigns.session_data_projects,
        socket.assigns.project_filter_selected_project_id
      )

    update_computer_inputs(socket, :project_filter, %{selected_project_id: selected_project_id})
  end

  defp normalize_project_filter_id(projects, project_id) when is_nil(project_id),
    do: first_project_id(projects)

  defp normalize_project_filter_id(projects, project_id) do
    if project_exists?(projects, project_id) do
      project_id
    else
      first_project_id(projects)
    end
  end

  defp project_exists?(projects, project_id) do
    Enum.any?(projects, &(&1.id == project_id))
  end

  defp first_project_id(projects) do
    List.first(projects) |> then(&(&1 && &1.id))
  end

  defp append_session_page(socket, project_id, visibility) do
    projects = socket.assigns.session_data_projects
    project = Enum.find(projects, &(&1.id == project_id))
    has_more_key = :"#{visibility}_has_more"

    if project && Map.get(project, has_more_key) do
      do_append_session_page(socket, project, projects, visibility)
    else
      socket
    end
  end

  defp do_append_session_page(socket, project, projects, visibility) do
    cursor_key = :"#{visibility}_cursor"
    sessions_key = :"#{visibility}_sessions"
    has_more_key = :"#{visibility}_has_more"

    {new_sessions, meta} =
      load_project_sessions(project.id, visibility, after: Map.get(project, cursor_key))

    updated_project =
      project
      |> Map.update!(sessions_key, &(&1 ++ new_sessions))
      |> Map.put(cursor_key, meta.next_cursor)
      |> Map.put(has_more_key, meta.has_more)

    updated_projects =
      Enum.map(projects, fn p ->
        if p.id == project.id, do: updated_project, else: p
      end)

    session_ids = extract_session_ids(updated_projects)
    new_ids = Enum.map(new_sessions, & &1.id)
    new_subagents = load_subagents_for_sessions(new_ids)

    socket
    |> assign(subagents_by_session: Map.merge(socket.assigns.subagents_by_session, new_subagents))
    |> update_computer_inputs(:session_data, %{projects: updated_projects})
    |> update_computer_inputs(:tool_call_stats, %{session_ids: session_ids})
    |> update_computer_inputs(:rework_stats, %{session_ids: session_ids})
  end

  defp load_project_sessions(project_id, visibility, opts \\ []) do
    cursor = Keyword.get(opts, :after)

    query =
      Session
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.sort(started_at: :desc)

    query =
      case visibility do
        :visible -> Ash.Query.filter(query, is_nil(hidden_at))
        :hidden -> Ash.Query.filter(query, not is_nil(hidden_at))
      end

    page_opts = [limit: @sessions_per_page]
    page_opts = if cursor, do: Keyword.put(page_opts, :after, cursor), else: page_opts

    page = query |> Ash.Query.page(page_opts) |> Ash.read!()

    sorted =
      Enum.sort_by(page.results, &SessionPresenter.last_updated_at/1, {:desc, DateTime})

    meta = %{has_more: page.more?, next_cursor: page.after}
    {sorted, meta}
  end

  defp extract_session_ids(projects) do
    projects
    |> Enum.flat_map(fn p -> p.visible_sessions ++ p.hidden_sessions end)
    |> Enum.map(& &1.id)
  end

  defp load_subagents_for_sessions([]), do: %{}

  defp load_subagents_for_sessions(session_ids) do
    Subagent
    |> Ash.Query.filter(session_id in ^session_ids)
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.read!()
    |> Enum.group_by(& &1.session_id)
  end

  defp relative_time(nil), do: "\u2014"

  defp relative_time(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="dashboard-root" id="dashboard-root">
      <div class="page-header">
        <h1>Dashboard</h1>
        <div class="page-header-actions">
          <button class="btn" phx-click="open_import_modal" data-testid="import-button">Import</button>
          <button class="btn" phx-click="refresh">Refresh</button>
        </div>
      </div>

      <%!-- Session Transcripts Section --%>
      <div class="mb-4">
        <div class="page-header">
          <h2 class="section-heading">Session Transcripts</h2>
        </div>

        <%= if @session_data_projects == [] do %>
          <div class="empty-state">
            No sessions yet.
          </div>
        <% else %>
          <div :if={length(@session_data_projects) > 1} class="filter-bar">
            <button
              :for={project <- @session_data_projects}
              phx-click="filter_project"
              phx-value-project-id={project.id}
              class={"filter-btn#{if @project_filter_selected_project_id == project.id, do: " is-active"}"}
            >
              {project.name} ({length(project.visible_sessions)})
            </button>
          </div>

          <div
            :for={project <- @session_data_projects}
            :if={@project_filter_selected_project_id == project.id}
            class="project-section"
          >
            <div class="project-header">
              <h3>
                <span class="project-name">{project.name}</span>
                <span class="project-count">
                  ({length(project.visible_sessions)} sessions)
                </span>
              </h3>
              <a href={"/projects/#{project.id}/file-metrics"} class="btn btn-ghost text-xs">
                File metrics
              </a>
              <form phx-submit="update_timezone" class="inline-form">
                <input type="hidden" name="project_id" value={project.id} />
                <input
                  type="text"
                  name="timezone"
                  value={project.timezone || "Etc/UTC"}
                  class="input input-xs"
                  style="width: 14ch"
                />
                <button type="submit" class="btn btn-ghost text-xs">Save TZ</button>
              </form>
              <span :if={@timezone_errors[project.id]} class="text-error text-xs">
                {@timezone_errors[project.id]}
              </span>
            </div>

            <%= if project.visible_sessions == [] and project.hidden_sessions == [] do %>
              <div class="text-muted text-sm">No sessions yet.</div>
            <% else %>
              <%= if project.visible_sessions != [] do %>
                <table>
                  <thead>
                    <tr>
                      <th>Session</th>
                      <th>Branch</th>
                      <th>Messages</th>
                      <th>Tools</th>
                      <th>Rework</th>
                      <th>Last updated</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for session <- project.visible_sessions do %>
                      <% subagents = Map.get(@subagents_by_session, session.id, []) %>
                      <tr data-testid="session-row" data-session-id={session.session_id}>
                        <td>
                          <div>{SessionPresenter.primary_label(session)}</div>
                          <div class="text-muted text-xs">{SessionPresenter.secondary_label(session)}</div>
                        </td>
                        <td>{session.git_branch || "\u2014"}</td>
                        <td>
                          {session.message_count || 0}
                          <%= if subagents != [] do %>
                            <span
                              phx-click="toggle_subagents"
                              phx-value-session-id={session.id}
                              class="subagent-toggle"
                            >
                              {length(subagents)} agents
                              <%= if Map.get(@expanded_subagents, session.id, false), do: "\u25BC", else: "\u25B6" %>
                            </span>
                          <% end %>
                        </td>
                        <td>
                          <% stats = Map.get(@tool_call_stats_stats, session.id) %>
                          <%= cond do %>
                            <% stats && stats.total > 0 && stats.failed > 0 -> %>
                              <span>{stats.total}</span> <span class="text-error">({stats.failed} failed)</span>
                            <% stats && stats.total > 0 -> %>
                              <span>{stats.total}</span>
                            <% true -> %>
                              <span>\u2014</span>
                          <% end %>
                        </td>
                        <td>
                          <% rework = Map.get(@rework_stats_stats, session.id) %>
                          <%= if rework && rework.count > 0 do %>
                            <span class="text-warning">{rework.count}</span>
                          <% else %>
                            <span>\u2014</span>
                          <% end %>
                        </td>
                        <td>
                          <% last_updated = SessionPresenter.last_updated_display(session) %>
                          <%= if last_updated do %>
                            <div>{last_updated.relative}</div>
                            <div class="text-muted text-xs">{last_updated.absolute}</div>
                          <% else %>
                            \u2014
                          <% end %>
                        </td>
                        <td class="flex gap-1">
                          <button class="btn btn-success" phx-click="review_session" phx-value-session-id={session.session_id}>
                            Review
                          </button>
                          <button class="btn" phx-click="hide_session" phx-value-id={session.id}>
                            Hide
                          </button>
                        </td>
                      </tr>
                      <%= if Map.get(@expanded_subagents, session.id, false) do %>
                        <tr :for={sa <- subagents} class="subagent-row">
                          <td>{sa.slug || String.slice(sa.agent_id, 0, 7)}</td>
                          <td></td>
                          <td>{sa.message_count || 0}</td>
                          <td></td>
                          <td></td>
                          <td>{relative_time(sa.started_at)}</td>
                          <td>
                            <a href={"/sessions/#{session.session_id}/agents/#{sa.agent_id}"} class="btn btn-success">
                              View
                            </a>
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
                <%= if project.visible_has_more do %>
                  <div class="load-more">
                    <button
                      class="btn"
                      phx-click="load_more_sessions"
                      phx-value-project-id={project.id}
                      phx-value-visibility="visible"
                      phx-disable-with="Loading..."
                    >
                      Load more sessions ({length(project.visible_sessions)} shown)
                    </button>
                  </div>
                <% end %>
              <% end %>

              <%= if project.hidden_sessions != [] do %>
                <div class="mt-2">
                  <button
                    class="hidden-toggle"
                    phx-click="toggle_hidden_section"
                    phx-value-project-id={project.id}
                  >
                    <%= if Map.get(@hidden_expanded, project.id, false) do %>
                      \u25BC Hidden sessions ({length(project.hidden_sessions)})
                    <% else %>
                      \u25B6 Hidden sessions ({length(project.hidden_sessions)})
                    <% end %>
                  </button>

                  <%= if Map.get(@hidden_expanded, project.id, false) do %>
                    <table class="hidden-table">
                      <thead>
                        <tr>
                          <th>Session</th>
                          <th>Branch</th>
                          <th>Messages</th>
                          <th>Tools</th>
                          <th>Rework</th>
                          <th>Last updated</th>
                          <th></th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for session <- project.hidden_sessions do %>
                          <% subagents = Map.get(@subagents_by_session, session.id, []) %>
                          <tr data-testid="session-row" data-session-id={session.session_id}>
                            <td>
                              <div>{SessionPresenter.primary_label(session)}</div>
                              <div class="text-muted text-xs">{SessionPresenter.secondary_label(session)}</div>
                            </td>
                            <td>{session.git_branch || "\u2014"}</td>
                            <td>
                              {session.message_count || 0}
                              <%= if subagents != [] do %>
                                <span
                                  phx-click="toggle_subagents"
                                  phx-value-session-id={session.id}
                                  class="subagent-toggle"
                                >
                                  {length(subagents)} agents
                                  <%= if Map.get(@expanded_subagents, session.id, false), do: "\u25BC", else: "\u25B6" %>
                                </span>
                              <% end %>
                            </td>
                            <td>
                              <% stats = Map.get(@tool_call_stats_stats, session.id) %>
                              <%= cond do %>
                                <% stats && stats.total > 0 && stats.failed > 0 -> %>
                                  <span>{stats.total}</span> <span class="text-error">({stats.failed} failed)</span>
                                <% stats && stats.total > 0 -> %>
                                  <span>{stats.total}</span>
                                <% true -> %>
                                  <span>\u2014</span>
                              <% end %>
                            </td>
                            <td>
                              <% rework = Map.get(@rework_stats_stats, session.id) %>
                              <%= if rework && rework.count > 0 do %>
                                <span class="text-warning">{rework.count}</span>
                              <% else %>
                                <span>\u2014</span>
                              <% end %>
                            </td>
                            <td>
                              <% last_updated = SessionPresenter.last_updated_display(session) %>
                              <%= if last_updated do %>
                                <div>{last_updated.relative}</div>
                                <div class="text-muted text-xs">{last_updated.absolute}</div>
                              <% else %>
                                \u2014
                              <% end %>
                            </td>
                            <td>
                              <button class="btn btn-success" phx-click="unhide_session" phx-value-id={session.id}>
                                Unhide
                              </button>
                            </td>
                          </tr>
                          <%= if Map.get(@expanded_subagents, session.id, false) do %>
                            <tr :for={sa <- subagents} class="subagent-row">
                              <td>{sa.slug || String.slice(sa.agent_id, 0, 7)}</td>
                              <td></td>
                              <td>{sa.message_count || 0}</td>
                              <td></td>
                              <td></td>
                              <td>{relative_time(sa.started_at)}</td>
                              <td>
                                <a href={"/sessions/#{session.session_id}/agents/#{sa.agent_id}"} class="btn btn-success">
                                  View
                                </a>
                              </td>
                            </tr>
                          <% end %>
                        <% end %>
                      </tbody>
                    </table>
                    <%= if project.hidden_has_more do %>
                      <div class="load-more">
                        <button
                          class="btn"
                          phx-click="load_more_sessions"
                          phx-value-project-id={project.id}
                          phx-value-visibility="hidden"
                          phx-disable-with="Loading..."
                        >
                          Load more hidden ({length(project.hidden_sessions)} shown)
                        </button>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>

      <%= if @show_import_modal do %>
        <div class="import-modal-overlay" data-testid="import-modal" phx-click-away="close_import_modal" phx-window-keydown="close_import_modal" phx-key="Escape">
          <div class="import-modal-dialog">
            <div class="import-modal-header">
              <h2>Import Transcripts</h2>
              <button class="btn btn-ghost import-modal-close" phx-click="close_import_modal" data-testid="import-modal-close">&times;</button>
            </div>
            <div class="import-modal-body">
              <div class="import-modal-controls">
                <select data-testid="project-filter" phx-change="filter_import_project">
                  <option value="">All Projects</option>
                </select>
                <select data-testid="sort-select" phx-change="sort_import_transcripts">
                  <option value="last_modified">Last Updated</option>
                  <option value="message_count">Message Count</option>
                  <option value="project_name">Project Name</option>
                </select>
              </div>
              <%= if @import_transcripts == [] do %>
                <div class="empty-state">No transcripts found</div>
              <% else %>
                <table class="import-transcript-table">
                  <thead>
                    <tr>
                      <% non_imported_paths = @import_transcripts |> Enum.reject(& &1.already_imported) |> Enum.map(& &1.file_path) |> MapSet.new() %>
                      <th><input type="checkbox" data-testid="select-all" phx-click="toggle_select_all" checked={MapSet.size(non_imported_paths) > 0 and MapSet.subset?(non_imported_paths, @selected_transcripts)} /></th>
                      <th>Project</th>
                      <th>Messages</th>
                      <th>Team</th>
                      <th>Last Updated</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for t <- @import_transcripts do %>
                      <tr data-testid="transcript-row" data-first-prompt={t[:first_prompt]} class={if t.already_imported, do: "already-imported", else: ""}>
                        <td>
                          <input type="checkbox" data-testid="select-transcript" value={t.file_path} phx-click="toggle_select_transcript" phx-value-path={t.file_path} {if t.already_imported, do: [disabled: "disabled"], else: []} />
                        </td>
                        <td><%= t.project_name %></td>
                        <td><%= t.message_count %></td>
                        <td><%= if t.is_team_session, do: "●" %></td>
                        <td><%= relative_time(t.last_modified) %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              <% end %>
              <%= if @import_pagination.total_count > @import_pagination.per_page do %>
                <nav data-testid="pagination">
                  <%= for page <- 1..ceil(@import_pagination.total_count / @import_pagination.per_page) do %>
                    <button data-testid={"page-#{page}"} phx-click="import_page" phx-value-page={page} aria-current={if page == @import_pagination.page, do: "page"}><%= page %></button>
                  <% end %>
                </nav>
              <% end %>
              <div class="import-modal-footer">
                <%= if MapSet.size(@selected_transcripts) > 0 do %>
                  <div data-testid="selection-count"><%= MapSet.size(@selected_transcripts) %> selected</div>
                <% end %>
                <button data-testid="import-action-button" class={"btn#{if MapSet.size(@selected_transcripts) > 0, do: " btn-primary"}"} {if MapSet.size(@selected_transcripts) == 0, do: [disabled: "disabled"], else: []}>
                  <%= if MapSet.size(@selected_transcripts) > 0 do %>Import <%= MapSet.size(@selected_transcripts) %><% else %>Import<% end %>
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
