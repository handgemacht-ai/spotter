defmodule SpotterWeb.PaneListLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  alias Spotter.Transcripts.{
    Commit,
    CommitHotspot,
    ProjectIngestState,
    PromptPattern,
    PromptPatternRun,
    ReviewItem,
    Session,
    SessionPresenter,
    SessionRework,
    Subagent,
    ToolCall
  }

  alias Spotter.Services.Tmux
  alias Spotter.Transcripts.Jobs.{ComputePromptPatterns, IngestRecentCommits}
  alias SpotterWeb.IngestProgress

  require OpenTelemetry.Tracer, as: Tracer

  require Ash.Query

  @sessions_per_page 20

  computer :study_queue do
    input :study_scope do
      initial "all"
    end

    input :study_project_id do
      initial nil
    end

    val :due_items do
      compute(fn %{study_scope: scope, study_project_id: project_id} ->
        load_due_items(scope, project_id)
      end)
    end

    val :due_counts do
      compute(fn %{study_scope: _scope, study_project_id: project_id} ->
        count_due_items(project_id)
      end)
    end

    event :set_study_scope do
      handle(fn _values, %{"scope" => scope} ->
        %{study_scope: scope}
      end)
    end
  end

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

    event :filter_project do
      handle(fn _values, %{"project-id" => project_id} ->
        if project_id == "all" do
          %{selected_project_id: nil}
        else
          %{selected_project_id: project_id}
        end
      end)
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
      IngestProgress.subscribe()
      Phoenix.PubSub.subscribe(Spotter.PubSub, "session_activity")
    end

    socket =
      socket
      |> assign(active_status_map: %{})
      |> IngestProgress.init_ingest()
      |> assign(hidden_expanded: %{})
      |> assign(expanded_subagents: %{})
      |> assign(subagents_by_session: %{})
      |> assign(pp_project_id: "all", pp_timespan: "30", pp_run: nil, pp_patterns: [])
      |> mount_computers()
      |> load_session_data()

    if connected?(socket), do: maybe_enqueue_commit_ingest(socket)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    pp_project_id = params["prompt_patterns_project_id"] || "all"
    pp_timespan = params["prompt_patterns_timespan"] || "30"

    socket =
      socket
      |> assign(pp_project_id: pp_project_id, pp_timespan: pp_timespan)
      |> load_latest_pp_run()

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_prompt_patterns", _params, socket) do
    Tracer.with_span "spotter.pane_list_live.run_prompt_patterns" do
      scope = if socket.assigns.pp_project_id == "all", do: "global", else: "project"

      project_id =
        if scope == "project", do: socket.assigns.pp_project_id, else: nil

      timespan_days =
        case socket.assigns.pp_timespan do
          "all" -> nil
          val -> String.to_integer(val)
        end

      %{"scope" => scope, "project_id" => project_id, "timespan_days" => timespan_days}
      |> ComputePromptPatterns.new()
      |> Oban.insert()
    end

    {:noreply, load_latest_pp_run(socket)}
  end

  def handle_event("set_pp_project", %{"id" => id}, socket) do
    {:noreply,
     push_patch(socket,
       to: pp_path(id, socket.assigns.pp_timespan)
     )}
  end

  def handle_event("set_pp_timespan", %{"value" => value}, socket) do
    {:noreply,
     push_patch(socket,
       to: pp_path(socket.assigns.pp_project_id, value)
     )}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> load_session_data() |> refresh_study_queue()}
  end

  def handle_event("review_session", %{"session-id" => session_id}, socket) do
    cwd = lookup_session_cwd(session_id)
    Task.start(fn -> Tmux.launch_review_session(session_id, cwd: cwd) end)
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

  def handle_event("ingest", _params, socket) do
    {:noreply, IngestProgress.start_ingest(socket)}
  end

  def handle_event("mark_seen", %{"id" => id}, socket) do
    item = Ash.get!(ReviewItem, id)
    new_interval = advance_interval(item.importance, item.interval_days || 4)

    Ash.update!(item, %{}, action: :mark_seen)

    Ash.update!(item, %{
      interval_days: new_interval,
      next_due_on: Date.add(Date.utc_today(), new_interval)
    })

    {:noreply, refresh_study_queue(socket)}
  end

  def handle_event("set_importance", %{"id" => id, "importance" => importance}, socket) do
    item = Ash.get!(ReviewItem, id)
    importance_atom = String.to_existing_atom(importance)
    {interval, offset} = schedule_for_importance(importance_atom)

    Ash.update!(item, %{
      importance: importance_atom,
      interval_days: interval,
      next_due_on: Date.add(Date.utc_today(), offset)
    })

    {:noreply, refresh_study_queue(socket)}
  end

  @impl true
  def handle_info({:session_activity, %{session_id: session_id, status: status}}, socket) do
    active_status_map = Map.put(socket.assigns.active_status_map, session_id, status)
    {:noreply, assign(socket, active_status_map: active_status_map)}
  end

  def handle_info(msg, socket)
      when elem(msg, 0) in [
             :ingest_enqueued,
             :sync_started,
             :sync_progress,
             :sync_completed,
             :sync_error
           ] do
    case IngestProgress.handle_progress(msg, socket) do
      {:ok, socket} ->
        socket = if elem(msg, 0) == :sync_completed, do: load_session_data(socket), else: socket
        {:noreply, socket}

      :ignore ->
        {:noreply, socket}
    end
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

  defp advance_interval(:high, _current), do: 1
  defp advance_interval(_importance, current), do: (current || 4) * 2

  defp schedule_for_importance(:high), do: {1, 1}
  defp schedule_for_importance(:medium), do: {4, 4}
  defp schedule_for_importance(:low), do: {14, 14}

  defp find_project_name(projects, project_id) do
    case Enum.find(projects, &(&1.id == project_id)) do
      nil -> String.slice(project_id, 0, 8)
      project -> project.name
    end
  end

  defp pp_path(project_id, timespan) do
    "/?prompt_patterns_project_id=#{project_id}&prompt_patterns_timespan=#{timespan}"
  end

  defp load_latest_pp_run(socket) do
    scope = if socket.assigns.pp_project_id == "all", do: :global, else: :project

    project_id =
      if scope == :project, do: socket.assigns.pp_project_id, else: nil

    timespan_days =
      case socket.assigns.pp_timespan do
        "all" -> nil
        val -> String.to_integer(val)
      end

    query =
      PromptPatternRun
      |> Ash.Query.filter(scope == ^scope)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(1)

    query =
      if timespan_days do
        Ash.Query.filter(query, timespan_days == ^timespan_days)
      else
        Ash.Query.filter(query, is_nil(timespan_days))
      end

    query =
      if project_id do
        Ash.Query.filter(query, project_id == ^project_id)
      else
        query
      end

    case Ash.read(query) do
      {:ok, [run]} ->
        patterns =
          PromptPattern
          |> Ash.Query.filter(run_id == ^run.id)
          |> Ash.Query.sort(count_total: :desc)
          |> Ash.read!()

        assign(socket, pp_run: run, pp_patterns: patterns)

      _ ->
        assign(socket, pp_run: nil, pp_patterns: [])
    end
  end

  defp refresh_study_queue(socket) do
    project_id = socket.assigns.project_filter_selected_project_id
    update_computer_inputs(socket, :study_queue, %{study_project_id: project_id})
  end

  defp load_due_items(scope, project_id) do
    today = Date.utc_today()

    query =
      ReviewItem
      |> Ash.Query.filter(is_nil(suspended_at))
      |> Ash.Query.filter(is_nil(next_due_on) or next_due_on <= ^today)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(20)

    query = if project_id, do: Ash.Query.filter(query, project_id == ^project_id), else: query

    query =
      case scope do
        "messages" -> Ash.Query.filter(query, target_kind == :commit_message)
        "hotspots" -> Ash.Query.filter(query, target_kind == :commit_hotspot)
        _ -> query
      end

    items = Ash.read!(query)
    enrich_review_items(items)
  rescue
    _ -> []
  end

  defp enrich_review_items(items) do
    commit_ids = items |> Enum.map(& &1.commit_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    hotspot_ids =
      items |> Enum.map(& &1.commit_hotspot_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    commits =
      if commit_ids != [] do
        Commit |> Ash.Query.filter(id in ^commit_ids) |> Ash.read!() |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    hotspots =
      if hotspot_ids != [] do
        CommitHotspot
        |> Ash.Query.filter(id in ^hotspot_ids)
        |> Ash.read!()
        |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    Enum.map(items, fn item ->
      %{
        item: item,
        commit: Map.get(commits, item.commit_id),
        hotspot: Map.get(hotspots, item.commit_hotspot_id)
      }
    end)
  end

  defp count_due_items(project_id) do
    today = Date.utc_today()

    base =
      ReviewItem
      |> Ash.Query.filter(is_nil(suspended_at))
      |> Ash.Query.filter(is_nil(next_due_on) or next_due_on <= ^today)

    base = if project_id, do: Ash.Query.filter(base, project_id == ^project_id), else: base
    items = Ash.read!(base)

    %{
      total: length(items),
      messages: Enum.count(items, &(&1.target_kind == :commit_message)),
      hotspots: Enum.count(items, &(&1.target_kind == :commit_hotspot)),
      high: Enum.count(items, &(&1.importance == :high)),
      medium: Enum.count(items, &(&1.importance == :medium)),
      low: Enum.count(items, &(&1.importance == :low))
    }
  rescue
    _ -> %{total: 0, messages: 0, hotspots: 0, high: 0, medium: 0, low: 0}
  end

  defp lookup_session_cwd(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{cwd: cwd}} when is_binary(cwd) -> cwd
      _ -> nil
    end
  end

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
    |> assign(subagents_by_session: subagents_by_session)
    |> update_computer_inputs(:session_data, %{projects: projects})
    |> update_computer_inputs(:tool_call_stats, %{session_ids: session_ids})
    |> update_computer_inputs(:rework_stats, %{session_ids: session_ids})
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

    meta = %{has_more: page.more?, next_cursor: page.after}
    {page.results, meta}
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
    <div class="container" data-testid="dashboard-root">
      <div class="page-header">
        <h1>Dashboard</h1>
        <div class="page-header-actions">
          <button class="btn" phx-click="refresh">Refresh</button>
        </div>
      </div>

      <%!-- Study Queue Section --%>
      <div :if={@study_queue_due_counts.total > 0} class="study-queue mb-4" data-testid="study-queue">
        <div class="page-header">
          <h2 class="section-heading">
            Study Queue
            <span class="text-muted text-sm">Due: {@study_queue_due_counts.total}</span>
          </h2>
          <div class="filter-bar">
            <button
              phx-click={event(:study_queue, :set_study_scope)}
              phx-value-scope="all"
              class={"filter-btn#{if @study_queue_study_scope == "all", do: " is-active"}"}
            >
              All ({@study_queue_due_counts.total})
            </button>
            <button
              phx-click={event(:study_queue, :set_study_scope)}
              phx-value-scope="messages"
              class={"filter-btn#{if @study_queue_study_scope == "messages", do: " is-active"}"}
            >
              Messages ({@study_queue_due_counts.messages})
            </button>
            <button
              phx-click={event(:study_queue, :set_study_scope)}
              phx-value-scope="hotspots"
              class={"filter-btn#{if @study_queue_study_scope == "hotspots", do: " is-active"}"}
            >
              Hotspots ({@study_queue_due_counts.hotspots})
            </button>
          </div>
        </div>

        <div class="importance-summary text-sm text-muted mb-2">
          <span :if={@study_queue_due_counts.high > 0} class="text-error">
            {@study_queue_due_counts.high} high
          </span>
          <span :if={@study_queue_due_counts.medium > 0}>
            {@study_queue_due_counts.medium} medium
          </span>
          <span :if={@study_queue_due_counts.low > 0}>
            {@study_queue_due_counts.low} low
          </span>
        </div>

        <div :for={entry <- @study_queue_due_items} class="study-card" data-testid="study-card">
          <div class="study-card-header">
            <span class={"badge study-kind-#{entry.item.target_kind}"}>
              <%= if entry.item.target_kind == :commit_message, do: "Commit", else: "Hotspot" %>
            </span>
            <span class={"badge study-importance-#{entry.item.importance}"}>
              {entry.item.importance}
            </span>
            <span :if={entry.item.seen_count > 0} class="text-muted text-xs">
              seen {entry.item.seen_count}x
            </span>
          </div>

          <div class="study-card-body">
            <%= if entry.item.target_kind == :commit_message and entry.commit do %>
              <div class="study-commit-hash text-muted text-xs">
                {String.slice(entry.commit.commit_hash, 0, 8)}
              </div>
              <div class="study-commit-subject">{entry.commit.subject}</div>
              <div :if={entry.commit.body} class="study-commit-body text-sm text-muted">
                {String.slice(entry.commit.body || "", 0, 200)}
              </div>
            <% end %>

            <%= if entry.item.target_kind == :commit_hotspot and entry.hotspot do %>
              <div class="study-hotspot-path text-muted text-xs">
                {entry.hotspot.relative_path}:{entry.hotspot.line_start}-{entry.hotspot.line_end}
                <%= if entry.hotspot.symbol_name do %>
                  ({entry.hotspot.symbol_name})
                <% end %>
              </div>
              <div class="study-hotspot-reason">{entry.hotspot.reason}</div>
              <div class="study-hotspot-score">
                Score: {entry.hotspot.overall_score}
              </div>
            <% end %>
          </div>

          <div class="study-card-actions">
            <select
              phx-change="set_importance"
              phx-value-id={entry.item.id}
              name="importance"
              class="importance-select"
            >
              <option value="high" selected={entry.item.importance == :high}>High</option>
              <option value="medium" selected={entry.item.importance == :medium}>Medium</option>
              <option value="low" selected={entry.item.importance == :low}>Low</option>
            </select>
            <button class="btn btn-success" phx-click="mark_seen" phx-value-id={entry.item.id}>
              Mark seen
            </button>
          </div>
        </div>
      </div>

      <%!-- Prompt Patterns Section --%>
      <div class="prompt-patterns-section mb-4" data-testid="prompt-patterns-section">
        <div class="page-header">
          <h2 class="section-heading">Repetitive Prompt Patterns</h2>
          <button
            class="btn btn-success"
            phx-click="run_prompt_patterns"
            data-testid="analyze-patterns-btn"
          >
            Analyze patterns
          </button>
        </div>

        <div class="filter-bar">
          <button
            phx-click="set_pp_project"
            phx-value-id="all"
            class={"filter-btn#{if @pp_project_id == "all", do: " is-active"}"}
          >
            All projects
          </button>
          <button
            :for={project <- @session_data_projects}
            phx-click="set_pp_project"
            phx-value-id={project.id}
            class={"filter-btn#{if @pp_project_id == project.id, do: " is-active"}"}
          >
            {project.name}
          </button>
        </div>

        <div class="filter-bar mt-1">
          <button
            :for={{label, val} <- [{"7d", "7"}, {"30d", "30"}, {"90d", "90"}, {"All-time", "all"}]}
            phx-click="set_pp_timespan"
            phx-value-value={val}
            class={"filter-btn#{if @pp_timespan == val, do: " is-active"}"}
          >
            {label}
          </button>
        </div>

        <%= cond do %>
          <% is_nil(@pp_run) -> %>
            <div class="empty-state">
              No prompt pattern analysis yet. Click Analyze patterns.
            </div>
          <% @pp_run.status in [:queued, :running] -> %>
            <div class="empty-state">Analyzing...</div>
          <% @pp_run.status == :error -> %>
            <div class="empty-state text-error">Analysis failed: {@pp_run.error}</div>
          <% @pp_run.status == :completed and @pp_patterns == [] -> %>
            <div class="empty-state">No repeated patterns found in this timespan.</div>
          <% @pp_run.status == :completed -> %>
            <table>
              <thead>
                <tr>
                  <th>Pattern</th>
                  <th>Count</th>
                  <th>Example</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={pattern <- @pp_patterns} data-testid="pattern-row">
                  <td>
                    <div class="text-sm font-medium">{pattern.label}</div>
                    <div class="text-xs text-muted">{pattern.needle}</div>
                  </td>
                  <td>
                    {pattern.count_total}
                    <%= if @pp_project_id == "all" and pattern.project_counts != %{} do %>
                      <div class="pp-project-counts">
                        <span
                          :for={{pid, cnt} <- pattern.project_counts}
                          class="badge text-xs"
                        >
                          {find_project_name(@session_data_projects, pid)}: {cnt}
                        </span>
                      </div>
                    <% end %>
                  </td>
                  <td>
                    <% example = List.first(Map.get(pattern.examples, "items", [])) %>
                    <span :if={example} class="text-sm text-muted">{String.slice(example, 0, 80)}</span>
                  </td>
                </tr>
              </tbody>
            </table>
        <% end %>
      </div>

      <%!-- Session Transcripts Section --%>
      <div class="mb-4">
        <div class="page-header">
          <h2 class="section-heading">Session Transcripts</h2>
          <button
            class="btn"
            phx-click="ingest"
            disabled={@ingest_running}
            data-testid="sync-transcripts-button"
          >
            <%= if @ingest_running, do: "Ingesting...", else: "Ingest" %>
          </button>
        </div>

        <.ingest_status
          :if={@ingest_projects != %{}}
          projects={@ingest_projects}
          running={@ingest_running}
        />

        <%= if @session_data_projects == [] do %>
          <div class="empty-state">
            No projects synced yet. Click Sync to start.
          </div>
        <% else %>
          <div :if={length(@session_data_projects) > 1} class="filter-bar">
            <button
              phx-click={event(:project_filter, :filter_project)}
              phx-value-project-id="all"
              class={"filter-btn#{if @project_filter_selected_project_id == nil, do: " is-active"}"}
            >
              All ({Enum.sum(Enum.map(@session_data_projects, &length(&1.visible_sessions)))})
            </button>
            <button
              :for={project <- @session_data_projects}
              phx-click={event(:project_filter, :filter_project)}
              phx-value-project-id={project.id}
              class={"filter-btn#{if @project_filter_selected_project_id == project.id, do: " is-active"}"}
            >
              {project.name} ({length(project.visible_sessions)})
            </button>
          </div>

          <div
            :for={project <- @session_data_projects}
            :if={@project_filter_selected_project_id == nil or @project_filter_selected_project_id == project.id}
            class="project-section"
          >
            <div class="project-header">
              <h3>
                <span class="project-name">{project.name}</span>
                <span class="project-count">
                  ({length(project.visible_sessions)} sessions)
                </span>
              </h3>
              <.project_ingest_status project_name={project.name} ingest_projects={@ingest_projects} />
              <a href={"/projects/#{project.id}/heatmap"} class="btn btn-ghost text-xs">
                Heatmap
              </a>
              <a href={"/projects/#{project.id}/co-change"} class="btn btn-ghost text-xs">
                Co-change
              </a>
            </div>

            <%= if project.visible_sessions == [] and project.hidden_sessions == [] do %>
              <div class="text-muted text-sm">No sessions yet.</div>
            <% else %>
              <%= if project.visible_sessions != [] do %>
                <table>
                  <thead>
                    <tr>
                      <th>Session</th>
                      <th>Status</th>
                      <th>Branch</th>
                      <th>Messages</th>
                      <th>Tools</th>
                      <th>Rework</th>
                      <th>Started</th>
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
                        <td>
                          <.session_status_badge status={Map.get(@active_status_map, session.session_id)} />
                        </td>
                        <td>{session.git_branch || "—"}</td>
                        <td>
                          {session.message_count || 0}
                          <%= if subagents != [] do %>
                            <span
                              phx-click="toggle_subagents"
                              phx-value-session-id={session.id}
                              class="subagent-toggle"
                            >
                              {length(subagents)} agents
                              <%= if Map.get(@expanded_subagents, session.id, false), do: "▼", else: "▶" %>
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
                              <span>—</span>
                          <% end %>
                        </td>
                        <td>
                          <% rework = Map.get(@rework_stats_stats, session.id) %>
                          <%= if rework && rework.count > 0 do %>
                            <span class="text-warning">{rework.count}</span>
                          <% else %>
                            <span>—</span>
                          <% end %>
                        </td>
                        <td>
                          <% started = SessionPresenter.started_display(session.started_at) %>
                          <%= if started do %>
                            <div>{started.relative}</div>
                            <div class="text-muted text-xs">{started.absolute}</div>
                          <% else %>
                            —
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
                      ▼ Hidden sessions ({length(project.hidden_sessions)})
                    <% else %>
                      ▶ Hidden sessions ({length(project.hidden_sessions)})
                    <% end %>
                  </button>

                  <%= if Map.get(@hidden_expanded, project.id, false) do %>
                    <table class="hidden-table">
                      <thead>
                        <tr>
                          <th>Session</th>
                          <th>Status</th>
                          <th>Branch</th>
                          <th>Messages</th>
                          <th>Tools</th>
                          <th>Rework</th>
                          <th>Hidden</th>
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
                            <td>
                              <.session_status_badge status={Map.get(@active_status_map, session.session_id)} />
                            </td>
                            <td>{session.git_branch || "—"}</td>
                            <td>
                              {session.message_count || 0}
                              <%= if subagents != [] do %>
                                <span
                                  phx-click="toggle_subagents"
                                  phx-value-session-id={session.id}
                                  class="subagent-toggle"
                                >
                                  {length(subagents)} agents
                                  <%= if Map.get(@expanded_subagents, session.id, false), do: "▼", else: "▶" %>
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
                                  <span>—</span>
                              <% end %>
                            </td>
                            <td>
                              <% rework = Map.get(@rework_stats_stats, session.id) %>
                              <%= if rework && rework.count > 0 do %>
                                <span class="text-warning">{rework.count}</span>
                              <% else %>
                                <span>—</span>
                              <% end %>
                            </td>
                            <td>{relative_time(session.hidden_at)}</td>
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

    </div>
    """
  end

  defp ingest_status(assigns) do
    done =
      assigns.projects
      |> Map.values()
      |> Enum.count(&(&1.status in [:completed, :error]))

    total = map_size(assigns.projects)
    assigns = assign(assigns, done: done, total: total)

    ~H"""
    <div class="ingest-progress">
      <%= if @running do %>
        <span class="sync-syncing">Ingesting {@done}/{@total} projects</span>
      <% else %>
        <span class="sync-completed">Ingested {@done}/{@total} projects</span>
      <% end %>
    </div>
    """
  end

  defp project_ingest_status(assigns) do
    proj = Map.get(assigns.ingest_projects, assigns.project_name)
    assigns = assign(assigns, :proj, proj)

    ~H"""
    <%= case @proj do %>
      <% %{status: :syncing} = p -> %>
        <span class="sync-syncing">{p.sessions_done}/{p.sessions_total} sessions</span>
      <% %{status: :completed} = p -> %>
        <span class="sync-completed">✓ {p.sessions_total} sessions in {p.duration_ms}ms</span>
      <% %{status: :error} = p -> %>
        <span class="sync-error">✗ {p.error}</span>
      <% %{status: :queued} -> %>
        <span class="sync-syncing">queued</span>
      <% _ -> %>
    <% end %>
    """
  end

  defp session_status_badge(%{status: :active} = assigns) do
    ~H"""
    <span class="badge session-status-active">active</span>
    """
  end

  defp session_status_badge(%{status: :inactive} = assigns) do
    ~H"""
    <span class="badge session-status-inactive">inactive</span>
    """
  end

  defp session_status_badge(%{status: :ended} = assigns) do
    ~H"""
    <span class="badge session-status-ended">ended</span>
    """
  end

  defp session_status_badge(assigns) do
    ~H"""
    """
  end
end
