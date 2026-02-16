defmodule SpotterWeb.PaneListLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  alias Spotter.Transcripts.{
    Commit,
    CommitHotspot,
    Flashcard,
    ProjectIngestState,
    ProjectRollingSummary,
    ReviewItem,
    Session,
    SessionPresenter,
    SessionRework,
    Subagent,
    ToolCall
  }

  alias Spotter.Services.Tmux

  alias Spotter.Transcripts.Jobs.{
    DistillProjectRollingSummary,
    IngestRecentCommits
  }

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

    input :study_include_upcoming do
      initial false
    end

    input :study_ahead_seen_ids do
      initial []
    end

    input :study_initial_due_count do
      initial nil
    end

    input :browser_timezone do
      initial "Etc/UTC"
    end

    val :due_items do
      compute(fn %{
                   study_scope: scope,
                   study_project_id: project_id,
                   study_include_upcoming: include_upcoming,
                   study_ahead_seen_ids: seen_ids,
                   browser_timezone: tz
                 } ->
        load_due_items(scope, project_id, include_upcoming, tz, seen_ids)
      end)
    end

    val :due_counts do
      compute(fn %{
                   study_project_id: project_id,
                   study_include_upcoming: include_upcoming,
                   study_ahead_seen_ids: seen_ids,
                   browser_timezone: tz
                 } ->
        count_due_items(project_id, include_upcoming, tz, seen_ids)
      end)
    end

    val :empty_context do
      compute(fn %{study_project_id: project_id, browser_timezone: tz} ->
        study_queue_empty_context(project_id, tz)
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
      |> mount_computers()
      |> load_session_data()
      |> ensure_default_project_filter()

    if connected?(socket), do: maybe_enqueue_commit_ingest(socket)

    {:ok, socket}
  end

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
        socket
        |> update_computer_inputs(:project_filter, %{selected_project_id: parsed_id})
        |> refresh_study_queue()

      {:noreply, socket}
    end
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

  def handle_event("refresh_rollup", %{"project-id" => project_id}, socket) do
    %{project_id: project_id}
    |> DistillProjectRollingSummary.new()
    |> Oban.insert()

    {:noreply, load_session_data(socket)}
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

  def handle_event("browser_timezone", %{"timezone" => tz}, socket) do
    tz = if valid_timezone?(tz), do: tz, else: "Etc/UTC"
    {:noreply, update_computer_inputs(socket, :study_queue, %{browser_timezone: tz})}
  end

  def handle_event("set_study_include_upcoming", %{"enabled" => enabled}, socket) do
    include = enabled == "true"

    {:noreply,
     update_computer_inputs(socket, :study_queue, %{
       study_include_upcoming: include,
       study_ahead_seen_ids: []
     })}
  end

  def handle_event("rate_card", %{"id" => id, "importance" => importance}, socket) do
    current_entry = List.first(socket.assigns.study_queue_due_items || [])
    item = Ash.get!(ReviewItem, id)
    today = browser_today(socket)
    importance_atom = String.to_existing_atom(importance)

    # Snapshot initial due count on first rating for progress bar
    socket = snapshot_initial_due_count(socket)

    # Mark seen first — increments seen_count
    item = Ash.update!(item, %{}, action: :mark_seen)

    # Compute interval using SM-2-style progression based on seen_count
    interval = next_interval(importance_atom, item.seen_count)

    Ash.update!(item, %{
      importance: importance_atom,
      interval_days: interval,
      next_due_on: Date.add(today, interval)
    })

    socket = maybe_track_seen_upcoming(socket, current_entry)

    {:noreply, refresh_study_queue(socket)}
  end

  def handle_event("study_keydown", %{"key" => key}, socket) do
    current_entry = List.first(socket.assigns.study_queue_due_items || [])

    importance =
      case key do
        "1" -> "low"
        "2" -> "medium"
        "3" -> "high"
        _ -> nil
      end

    if current_entry && importance do
      handle_event(
        "rate_card",
        %{"id" => current_entry.item.id, "importance" => importance},
        socket
      )
    else
      {:noreply, socket}
    end
  end

  @impl true
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

  # SM-2-style spaced repetition: interval grows exponentially with reviews
  defp next_interval(importance, seen_count) do
    base = base_interval(importance)
    multiplier = interval_multiplier(importance)
    interval = round(base * :math.pow(multiplier, seen_count))
    min(interval, 180)
  end

  defp base_interval(:high), do: 1
  defp base_interval(:medium), do: 3
  defp base_interval(:low), do: 7

  defp interval_multiplier(:high), do: 2.0
  defp interval_multiplier(:medium), do: 2.5
  defp interval_multiplier(:low), do: 3.0

  defp snapshot_initial_due_count(socket) do
    if is_nil(socket.assigns.study_queue_study_initial_due_count) do
      total = socket.assigns.study_queue_due_counts.total
      update_computer_inputs(socket, :study_queue, %{study_initial_due_count: total})
    else
      socket
    end
  end

  defp study_progress_pct(initial, remaining) when is_integer(initial) and initial > 0 do
    reviewed = initial - remaining
    min(100, round(reviewed / initial * 100))
  end

  defp study_progress_pct(_initial, _remaining), do: 0

  defp next_interval_label(importance, seen_count) do
    days = next_interval(importance, seen_count)

    cond do
      days == 1 -> "1d"
      days < 30 -> "#{days}d"
      true -> "#{div(days, 30)}mo"
    end
  end

  defp maybe_track_seen_upcoming(socket, entry)
       when is_map(entry) and is_map_key(entry, :upcoming) do
    if socket.assigns.study_queue_study_include_upcoming and entry.upcoming do
      seen = socket.assigns.study_queue_study_ahead_seen_ids

      update_computer_inputs(socket, :study_queue, %{study_ahead_seen_ids: [entry.item.id | seen]})
    else
      socket
    end
  end

  defp maybe_track_seen_upcoming(socket, _entry), do: socket

  defp refresh_study_queue(socket) do
    project_id = socket.assigns.project_filter_selected_project_id
    update_computer_inputs(socket, :study_queue, %{study_project_id: project_id})
  end

  defp load_due_items(scope, project_id, include_upcoming, tz, seen_ids) do
    today = today_in_tz(tz)
    limit = 20
    base_query = study_base_query(scope, project_id)

    due_items =
      base_query
      |> Ash.Query.filter(is_nil(next_due_on) or next_due_on <= ^today)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(limit)
      |> Ash.read!()

    items =
      if include_upcoming and length(due_items) < limit do
        remaining = limit - length(due_items)
        upcoming_items = load_upcoming_items(base_query, today, remaining, seen_ids)
        due_items ++ upcoming_items
      else
        due_items
      end

    enrich_review_items(items, today)
  rescue
    _ -> []
  end

  defp study_base_query(scope, project_id) do
    query =
      ReviewItem
      |> Ash.Query.filter(is_nil(suspended_at))

    query =
      if project_id,
        do: Ash.Query.filter(query, project_id == ^project_id),
        else: query

    case scope do
      "messages" -> Ash.Query.filter(query, target_kind == :commit_message)
      "hotspots" -> Ash.Query.filter(query, target_kind == :commit_hotspot)
      "flashcards" -> Ash.Query.filter(query, target_kind == :flashcard)
      _ -> query
    end
  end

  defp load_upcoming_items(base_query, today, limit, seen_ids) do
    query =
      base_query
      |> Ash.Query.filter(next_due_on > ^today)
      |> Ash.Query.sort(next_due_on: :asc, inserted_at: :desc)
      |> Ash.Query.limit(limit)

    query =
      if seen_ids != [],
        do: Ash.Query.filter(query, id not in ^seen_ids),
        else: query

    Ash.read!(query)
  end

  defp enrich_review_items(items, today) do
    commit_ids = items |> Enum.map(& &1.commit_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    hotspot_ids =
      items |> Enum.map(& &1.commit_hotspot_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    flashcard_ids =
      items |> Enum.map(& &1.flashcard_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    project_ids = items |> Enum.map(& &1.project_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

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

    flashcards =
      if flashcard_ids != [] do
        Flashcard
        |> Ash.Query.filter(id in ^flashcard_ids)
        |> Ash.read!()
        |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    projects =
      if project_ids != [] do
        Spotter.Transcripts.Project
        |> Ash.Query.filter(id in ^project_ids)
        |> Ash.read!()
        |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    Enum.map(items, fn item ->
      upcoming =
        item.next_due_on != nil and Date.compare(item.next_due_on, today) == :gt

      %{
        item: item,
        commit: Map.get(commits, item.commit_id),
        hotspot: Map.get(hotspots, item.commit_hotspot_id),
        flashcard: Map.get(flashcards, item.flashcard_id),
        project: Map.get(projects, item.project_id),
        upcoming: upcoming
      }
    end)
  end

  defp count_due_items(project_id, include_upcoming, tz, seen_ids) do
    today = today_in_tz(tz)

    base =
      ReviewItem
      |> Ash.Query.filter(is_nil(suspended_at))

    base = if project_id, do: Ash.Query.filter(base, project_id == ^project_id), else: base

    due_query = Ash.Query.filter(base, is_nil(next_due_on) or next_due_on <= ^today)
    due_items = Ash.read!(due_query)

    items =
      if include_upcoming do
        upcoming_query = Ash.Query.filter(base, next_due_on > ^today)

        upcoming_query =
          if seen_ids != [],
            do: Ash.Query.filter(upcoming_query, id not in ^seen_ids),
            else: upcoming_query

        due_items ++ Ash.read!(upcoming_query)
      else
        due_items
      end

    %{
      total: length(items),
      messages: Enum.count(items, &(&1.target_kind == :commit_message)),
      hotspots: Enum.count(items, &(&1.target_kind == :commit_hotspot)),
      flashcards: Enum.count(items, &(&1.target_kind == :flashcard)),
      high: Enum.count(items, &(&1.importance == :high)),
      medium: Enum.count(items, &(&1.importance == :medium)),
      low: Enum.count(items, &(&1.importance == :low))
    }
  rescue
    _ -> %{total: 0, messages: 0, hotspots: 0, flashcards: 0, high: 0, medium: 0, low: 0}
  end

  defp study_queue_empty_context(project_id, tz) do
    projects =
      try do
        Spotter.Transcripts.Project |> Ash.read!()
      rescue
        _ -> []
      end

    if projects == [] do
      :no_project
    else
      classify_review_items(project_id, tz)
    end
  rescue
    _ -> :no_due
  end

  defp classify_review_items(project_id, tz) do
    base =
      if project_id,
        do: ReviewItem |> Ash.Query.filter(project_id == ^project_id),
        else: ReviewItem

    all_items = Ash.read!(base)

    case all_items do
      [] -> :no_items
      items -> classify_due_status(items, tz)
    end
  end

  defp classify_due_status(items, tz) do
    today = today_in_tz(tz)
    next_week = Date.add(today, 7)
    suspended = Enum.count(items, &(not is_nil(&1.suspended_at)))

    upcoming_items =
      Enum.filter(items, fn item ->
        is_nil(item.suspended_at) and not is_nil(item.next_due_on) and
          Date.compare(item.next_due_on, today) == :gt and
          Date.compare(item.next_due_on, next_week) != :gt
      end)

    cond do
      suspended == length(items) ->
        :all_suspended

      upcoming_items != [] ->
        {:future_items, length(upcoming_items), earliest_due(upcoming_items)}

      true ->
        :no_due
    end
  end

  defp earliest_due(items) do
    items |> Enum.min_by(& &1.next_due_on, Date, fn -> nil end) |> then(&(&1 && &1.next_due_on))
  end

  defp today_in_tz(tz) do
    DateTime.now!(tz) |> DateTime.to_date()
  rescue
    _ -> Date.utc_today()
  end

  defp valid_timezone?(tz) when is_binary(tz) do
    DateTime.now!(tz)
    true
  rescue
    _ -> false
  end

  defp valid_timezone?(_), do: false

  defp browser_today(socket) do
    tz = socket.assigns[:study_queue_browser_timezone] || "Etc/UTC"
    today_in_tz(tz)
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

        rolling = load_rolling_summary(project.id)

        Map.merge(project, %{
          visible_sessions: visible,
          hidden_sessions: hidden,
          visible_cursor: visible_meta.next_cursor,
          visible_has_more: visible_meta.has_more,
          hidden_cursor: hidden_meta.next_cursor,
          hidden_has_more: hidden_meta.has_more,
          rolling_summary_text: rolling && rolling.summary_text,
          rolling_computed_at: rolling && rolling.computed_at
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

  defp load_rolling_summary(project_id) do
    ProjectRollingSummary
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.Query.sort(computed_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> List.first()
  rescue
    _ -> nil
  end

  defp load_subagents_for_sessions([]), do: %{}

  defp load_subagents_for_sessions(session_ids) do
    Subagent
    |> Ash.Query.filter(session_id in ^session_ids)
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.read!()
    |> Enum.group_by(& &1.session_id)
  end

  defp normalize_commit_subject(nil), do: "<No subject>"
  defp normalize_commit_subject(""), do: "<No subject>"

  defp normalize_commit_subject(subject) do
    trimmed = subject |> String.trim() |> String.replace(~r/\s+/, " ")
    if trimmed == "", do: "<No subject>", else: trimmed
  end

  defp format_commit_body_for_queue(nil), do: "No commit message body."
  defp format_commit_body_for_queue(""), do: "No commit message body."

  defp format_commit_body_for_queue(body) do
    trimmed = String.trim(body)
    if trimmed == "", do: "No commit message body.", else: trimmed
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
    <div class="container" data-testid="dashboard-root" id="dashboard-root" phx-hook="BrowserTimezone">
      <div class="page-header">
        <h1>Dashboard</h1>
        <div class="page-header-actions">
          <button class="btn" phx-click="refresh">Refresh</button>
        </div>
      </div>

      <%!-- Study Queue Section --%>
      <div class="study-queue mb-4" data-testid="study-queue">
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
            <button
              phx-click={event(:study_queue, :set_study_scope)}
              phx-value-scope="flashcards"
              class={"filter-btn#{if @study_queue_study_scope == "flashcards", do: " is-active"}"}
            >
              Flashcards ({@study_queue_due_counts.flashcards})
            </button>
          </div>
        </div>

        <%= if @study_queue_due_items == [] do %>
          <div class="empty-state" data-testid="study-queue-empty">
            <%= case @study_queue_empty_context do %>
              <% :no_project -> %>
                <p>No projects configured. Add a project in <a href="/settings/config">Settings</a> to start tracking sessions.</p>
                <p class="text-muted text-sm">Review items are created from commits and hotspot analysis during Claude Code sessions.</p>
              <% :no_items -> %>
                <p>No review items yet. Items appear after committing from a Claude Code session.</p>
                <p class="text-muted text-sm">
                  The session end hook persists context, then commit hotspot analysis and flashcard review create study items.
                </p>
              <% :all_suspended -> %>
                <p>All review items are suspended. Unsuspend items to resume studying.</p>
              <% {:future_items, count, next_due} -> %>
                <p>
                  No items due today.
                  {count} {if count == 1, do: "item", else: "items"} due this week
                  <%= if next_due do %>
                    &mdash; next on {Calendar.strftime(next_due, "%b %d")}.
                  <% end %>
                </p>
                <button
                  class="btn btn-success mt-2"
                  phx-click="set_study_include_upcoming"
                  phx-value-enabled="true"
                  data-testid="study-ahead-cta"
                >
                  Study ahead
                </button>
              <% _ -> %>
                <p>No items due today.</p>
            <% end %>
          </div>
        <% else %>
          <% current_entry = List.first(@study_queue_due_items) %>
          <% initial = @study_queue_study_initial_due_count || @study_queue_due_counts.total %>
          <% remaining = @study_queue_due_counts.total %>
          <% pct = study_progress_pct(initial, remaining) %>

          <div class="study-progress-container" id="study-progress" phx-hook="StudyProgress">
            <div class="study-progress-bar">
              <div class={"study-progress-fill#{if pct == 100, do: " is-complete"}"} style={"width: #{pct}%"}></div>
            </div>
            <span class="study-progress-label">
              <strong class="study-progress-number">{remaining}</strong>
              <span class="study-progress-text">/ {initial}</span>
            </span>
          </div>

          <div
            id="study-card-container"
            phx-hook="StudyCard"
            phx-window-keydown="study_keydown"
            class="study-card-container"
          >
            <div class="study-card" data-testid="study-card" data-card-id={current_entry.item.id}>
              <div class="study-card-header">
                <span :if={current_entry.project} class="badge badge-project">
                  {current_entry.project.name}
                </span>
                <span :if={is_nil(current_entry.project)} class="badge badge-project-unavailable">
                  Unknown
                </span>
                <span class={"badge study-kind-#{current_entry.item.target_kind}"}>
                  <%= case current_entry.item.target_kind do %>
                    <% :commit_message -> %>Commit
                    <% :commit_hotspot -> %>Hotspot
                    <% :flashcard -> %>Flashcard
                    <% _ -> %>Review
                  <% end %>
                </span>
                <span :if={current_entry.upcoming} class="badge badge-upcoming">
                  {Calendar.strftime(current_entry.item.next_due_on, "%b %d")}
                </span>
                <span :if={current_entry.item.seen_count > 0} class="badge badge-seen">
                  {current_entry.item.seen_count}&times; reviewed
                </span>
              </div>

              <div class="study-card-body">
                <%= if current_entry.item.target_kind == :commit_message and current_entry.commit do %>
                  <div class="study-commit-hash text-muted text-xs">
                    {String.slice(current_entry.commit.commit_hash, 0, 8)}
                  </div>
                  <div class="study-commit-subject">
                    {normalize_commit_subject(current_entry.commit.subject)}
                  </div>
                  <div class="study-commit-body">
                    {format_commit_body_for_queue(current_entry.commit.body)}
                  </div>
                <% end %>

                <%= if current_entry.item.target_kind == :commit_hotspot and current_entry.hotspot do %>
                  <div class="study-hotspot-path text-muted text-xs">
                    {current_entry.hotspot.relative_path}:{current_entry.hotspot.line_start}-{current_entry.hotspot.line_end}
                    <%= if current_entry.hotspot.symbol_name do %>
                      ({current_entry.hotspot.symbol_name})
                    <% end %>
                  </div>
                  <div class="study-hotspot-reason">{current_entry.hotspot.reason}</div>
                  <div class="study-hotspot-score">
                    Score: {current_entry.hotspot.overall_score}
                  </div>
                <% end %>

                <%= if current_entry.item.target_kind == :flashcard and current_entry.flashcard do %>
                  <div :if={current_entry.flashcard.question} class="study-flashcard-question text-sm font-medium mb-1">
                    {current_entry.flashcard.question}
                  </div>
                  <div class="study-flashcard-snippet">{current_entry.flashcard.front_snippet}</div>
                  <details class="study-flashcard-answer mt-2">
                    <summary>Show answer</summary>
                    <div class="mt-1">{current_entry.flashcard.answer}</div>
                  </details>
                <% end %>
              </div>

              <div class="study-card-actions">
                <button
                  class="btn study-rate-btn study-rate-easy"
                  phx-click="rate_card"
                  phx-value-id={current_entry.item.id}
                  phx-value-importance="low"
                >
                  <span class="study-rate-label">Easy</span>
                  <span class="study-rate-interval">{next_interval_label(:low, current_entry.item.seen_count)}</span>
                  <kbd class="study-kbd">1</kbd>
                </button>
                <button
                  class="btn study-rate-btn study-rate-again"
                  phx-click="rate_card"
                  phx-value-id={current_entry.item.id}
                  phx-value-importance="medium"
                >
                  <span class="study-rate-label">Again</span>
                  <span class="study-rate-interval">{next_interval_label(:medium, current_entry.item.seen_count)}</span>
                  <kbd class="study-kbd">2</kbd>
                </button>
                <button
                  class="btn study-rate-btn study-rate-hard"
                  phx-click="rate_card"
                  phx-value-id={current_entry.item.id}
                  phx-value-importance="high"
                >
                  <span class="study-rate-label">Hard</span>
                  <span class="study-rate-interval">{next_interval_label(:high, current_entry.item.seen_count)}</span>
                  <kbd class="study-kbd">3</kbd>
                </button>
              </div>
              <div class="study-keyboard-hint">
                Press <kbd>1</kbd>, <kbd>2</kbd>, or <kbd>3</kbd> to rate
              </div>
            </div>
          </div>
        <% end %>
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
              <button
                class="btn btn-ghost text-xs"
                phx-click="refresh_rollup"
                phx-value-project-id={project.id}
              >
                Refresh rollup
              </button>
            </div>

            <div :if={project.rolling_summary_text} class="rolling-summary text-sm mb-2">
              <details>
                <summary class="text-muted">
                  Rolling summary
                  <span :if={project.rolling_computed_at} class="text-xs">
                    ({relative_time(project.rolling_computed_at)})
                  </span>
                </summary>
                <div class="mt-1">{project.rolling_summary_text}</div>
              </details>
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
                      <th>Lines</th>
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
                          <.line_stats session={session} />
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
                          <% last_updated = SessionPresenter.last_updated_display(session) %>
                          <%= if last_updated do %>
                            <div>{last_updated.relative}</div>
                            <div class="text-muted text-xs">{last_updated.absolute}</div>
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
                          <th>Lines</th>
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
                              <.line_stats session={session} />
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
                              <% last_updated = SessionPresenter.last_updated_display(session) %>
                              <%= if last_updated do %>
                                <div>{last_updated.relative}</div>
                                <div class="text-muted text-xs">{last_updated.absolute}</div>
                              <% else %>
                                —
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
                              <td></td>
                              <td>{sa.message_count || 0}</td>
                              <td></td>
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

  defp line_stats(%{session: %{lines_added: added, lines_removed: removed}} = assigns)
       when added > 0 or removed > 0 do
    assigns = assign(assigns, added: added, removed: removed)

    ~H"""
    <span class="text-success">+{@added}</span> / <span class="text-error">-{@removed}</span>
    """
  end

  defp line_stats(assigns) do
    ~H"""
    <span>—</span>
    """
  end
end
