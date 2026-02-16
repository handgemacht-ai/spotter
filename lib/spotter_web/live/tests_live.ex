defmodule SpotterWeb.TestsLive do
  use Phoenix.LiveView

  alias Spotter.Services.TestCommitTimeline
  alias Spotter.TestSpec
  alias Spotter.Transcripts.{Commit, Project}

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def mount(_params, _session, socket) do
    projects =
      try do
        Project |> Ash.read!()
      rescue
        _ -> []
      end

    {:ok,
     socket
     |> assign(
       projects: projects,
       selected_project_id: nil,
       # Timeline state
       commit_rows: [],
       commit_cursor: nil,
       commit_has_more: false,
       # Detail state
       selected_commit_id: nil,
       selected_commit: nil,
       spec_view: :diff,
       detail_content: nil,
       detail_error: nil,
       # Tree state (for snapshot view)
       tree: [],
       expanded: MapSet.new(),
       search_query: "",
       # Shared
       dolt_available: TestSpec.dolt_available?(),
       commit_id_cache: %{}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = parse_project_id(params["project_id"])
    project_id = project_id || socket.assigns.projects |> List.first() |> then(&(&1 && &1.id))

    commit_id = params["commit_id"]
    search_q = params["q"]

    spec_view =
      if search_q && search_q != "" && !params["spec_view"],
        do: :snapshot,
        else: parse_spec_view(params["spec_view"])

    project_changed = project_id != socket.assigns.selected_project_id

    socket =
      socket
      |> assign(
        selected_project_id: project_id,
        spec_view: spec_view,
        search_query: search_q || ""
      )
      |> then(fn s ->
        if project_changed, do: load_timeline(s), else: s
      end)
      |> load_selected_commit(commit_id)
      |> load_detail()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = parse_project_id(raw_id)
    path = if project_id, do: "/tests?project_id=#{project_id}", else: "/tests"
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("select_commit", %{"commit-id" => commit_id}, socket) do
    params = build_params(socket.assigns.selected_project_id, commit_id, socket.assigns.spec_view)
    {:noreply, push_patch(socket, to: "/tests?#{URI.encode_query(params)}")}
  end

  def handle_event("set_view", %{"view" => view}, socket) do
    spec_view = parse_spec_view(view)

    params =
      build_params(
        socket.assigns.selected_project_id,
        socket.assigns.selected_commit_id,
        spec_view
      )

    {:noreply, push_patch(socket, to: "/tests?#{URI.encode_query(params)}")}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply, load_more_commits(socket)}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, expanded: expanded)}
  end

  def handle_event("expand_all", _params, socket) do
    ids = Enum.map(socket.assigns.tree, & &1.relative_path)
    {:noreply, assign(socket, expanded: MapSet.new(ids))}
  end

  def handle_event("collapse_all", _params, socket) do
    {:noreply, assign(socket, expanded: MapSet.new())}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, assign(socket, search_query: String.trim(q))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-header">
        <div>
          <h1>Tests</h1>
          <p class="text-muted text-sm">Test specifications extracted from commits</p>
        </div>
      </div>

      <div class="filter-section">
        <div>
          <label class="filter-label">Project</label>
          <div class="filter-bar">
            <button
              :for={project <- @projects}
              phx-click="filter_project"
              phx-value-project-id={project.id}
              class={"filter-btn#{if @selected_project_id == project.id, do: " is-active"}"}
            >
              {project.name}
            </button>
          </div>
        </div>
      </div>

      <div :if={not @dolt_available} class="product-callout">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
          <circle cx="8" cy="8" r="6" /><line x1="8" y1="5" x2="8" y2="8" /><circle cx="8" cy="11" r="0.5" fill="currentColor" />
        </svg>
        <span>Dolt is unavailable. Start it with <code>docker compose -f docker-compose.dolt.yml up -d</code></span>
      </div>

      <div :if={@selected_project_id != nil} class="product-layout">
        <div class="product-timeline">
          <div class="product-timeline-header">
            <span class="product-timeline-title">Commits</span>
            <span class="product-timeline-count">{length(@commit_rows)}</span>
          </div>

          <div :if={@commit_rows == []} class="product-timeline-empty">
            <p>No commits linked to this project yet.</p>
          </div>

          <button
            :for={row <- @commit_rows}
            class={"product-timeline-row#{if @selected_commit_id == row.commit.id, do: " is-selected"}"}
            phx-click="select_commit"
            phx-value-commit-id={row.commit.id}
            aria-current={if @selected_commit_id == row.commit.id, do: "true"}
          >
            <div class="product-timeline-row-main">
              <code class="product-timeline-hash">{String.slice(row.commit.commit_hash, 0, 8)}</code>
              <span class="product-timeline-subject">{row.commit.subject || "(no subject)"}</span>
            </div>
            <div class="product-timeline-row-meta">
              <span class="product-timeline-date">{format_date(row.commit)}</span>
              <.test_run_badge run={row.test_run} />
            </div>
          </button>

          <div :if={@commit_has_more} class="product-timeline-more">
            <button phx-click="load_more" class="btn btn-ghost btn-sm">Load more</button>
          </div>
        </div>

        <div class="product-detail">
          <div :if={@selected_commit == nil} class="product-detail-empty">
            <p>Select a commit to view its test specification.</p>
          </div>

          <div :if={@selected_commit != nil}>
            <div class="product-detail-header">
              <div class="product-detail-commit-info">
                <code class="product-detail-hash">{@selected_commit.commit_hash}</code>
                <span class="product-detail-subject">{@selected_commit.subject || "(no subject)"}</span>
              </div>
              <div class="product-detail-toggle">
                <button
                  phx-click="set_view"
                  phx-value-view="diff"
                  class={"btn btn-sm#{if @spec_view == :diff, do: " btn-active", else: " btn-ghost"}"}
                >
                  Diff
                </button>
                <button
                  phx-click="set_view"
                  phx-value-view="snapshot"
                  class={"btn btn-sm#{if @spec_view == :snapshot, do: " btn-active", else: " btn-ghost"}"}
                >
                  Snapshot
                </button>
              </div>
            </div>

            <div :if={not @dolt_available} class="product-callout" style="margin-top: var(--space-4);">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
                <circle cx="8" cy="8" r="6" /><line x1="8" y1="5" x2="8" y2="8" /><circle cx="8" cy="11" r="0.5" fill="currentColor" />
              </svg>
              <span>Dolt is unavailable. Test data cannot be loaded.</span>
            </div>

            <div :if={@dolt_available}>
              <.detail_diff
                :if={@spec_view == :diff}
                content={@detail_content}
                error={@detail_error}
              />
              <.detail_snapshot
                :if={@spec_view == :snapshot}
                content={@detail_content}
                error={@detail_error}
                tree={@tree}
                expanded={@expanded}
                search_query={@search_query}
                commit_id_cache={@commit_id_cache}
              />
            </div>
          </div>
        </div>
      </div>

      <div :if={@selected_project_id == nil} class="empty-state">
        <p>Select a project to view its test specifications.</p>
      </div>
    </div>
    """
  end

  # -- Components --------------------------------------------------------------

  defp test_run_badge(assigns) do
    assigns = assign(assigns, :run_status, normalize_run_status(assigns.run))

    ~H"""
    <span :if={@run_status == :none} class="product-spec-badge is-none">none</span>
    <span :if={@run_status == :ok_no_changes} class="product-spec-badge is-ok">
      ok (no changes)
    </span>
    <span
      :if={@run_status not in [:none, :ok_no_changes]}
      class={"product-spec-badge is-#{@run_status}"}
    >
      {@run_status}
    </span>
    """
  end

  defp normalize_run_status(nil), do: :none
  defp normalize_run_status(%{status: :completed, dolt_commit_hash: nil}), do: :ok_no_changes
  defp normalize_run_status(%{status: :completed}), do: :ok

  defp normalize_run_status(%{status: status})
       when status in [:queued, :running, :error],
       do: status

  defp normalize_run_status(_), do: :none

  defp detail_diff(assigns) do
    ~H"""
    <div :if={@error != nil} class="product-detail-message">
      <p>{error_message(@error)}</p>
    </div>

    <div :if={@error == nil and @content != nil and @content[:kind] == :no_changes} class="product-detail-message">
      <p>No test changes in this commit.</p>
    </div>

    <div :if={@error == nil and @content != nil and @content[:kind] != :no_changes} class="product-diff">
      <.test_diff_section
        :if={@content.added != []}
        label="Added"
        kind="added"
        items={@content.added}
      />
      <.test_diff_section
        :if={@content.changed != []}
        label="Changed"
        kind="changed"
        items={@content.changed}
      />
      <.test_diff_section
        :if={@content.removed != []}
        label="Removed"
        kind="removed"
        items={@content.removed}
      />
      <div
        :if={@content.added == [] and @content.changed == [] and @content.removed == []}
        class="product-detail-message"
      >
        <p>No test changes in this commit.</p>
      </div>
    </div>
    """
  end

  defp test_diff_section(assigns) do
    ~H"""
    <div class={"product-diff-section is-#{@kind}"}>
      <h3 class="product-diff-section-label">{@label}</h3>
      <div :for={item <- @items} class="product-diff-item">
        <.test_diff_item item={item} kind={@kind} />
      </div>
    </div>
    """
  end

  defp test_diff_item(%{kind: "changed"} = assigns) do
    ~H"""
    <div class="product-diff-change">
      <div class="product-diff-change-header">
        <code class="product-key">{@item.test_key}</code>
      </div>
      <div :for={field <- @item.changed_fields} class="product-diff-field">
        <span class="product-diff-field-name">{field}</span>
        <div class="product-diff-before">{format_field_value(Map.get(@item.before, field))}</div>
        <div class="product-diff-after">{format_field_value(Map.get(@item.after, field))}</div>
      </div>
    </div>
    """
  end

  defp test_diff_item(assigns) do
    ~H"""
    <div class="product-diff-entry">
      <code class="product-key">{format_test_key(@item)}</code>
      <span :if={test_name(@item)} class="product-name">{test_name(@item)}</span>
    </div>
    """
  end

  defp detail_snapshot(assigns) do
    ~H"""
    <div :if={@error != nil} class="product-detail-message">
      <p>{error_message(@error)}</p>
    </div>

    <div :if={@error == nil and @content != nil and @content.tree == [] and @content.effective_dolt_commit_hash == nil} class="product-detail-message">
      <p>No test specifications available yet for this project.</p>
    </div>

    <div :if={@error == nil and @content != nil and (@content.tree != [] or @content.effective_dolt_commit_hash != nil)}>
      <div class="product-toolbar">
        <div class="product-search">
          <input
            type="text"
            placeholder="Search files, tests, frameworks..."
            phx-change="search"
            phx-debounce="200"
            name="q"
            value={@search_query}
            class="product-search-input"
          />
        </div>
        <div class="product-actions">
          <button phx-click="expand_all" class="btn btn-ghost btn-sm">Expand all</button>
          <button phx-click="collapse_all" class="btn btn-ghost btn-sm">Collapse all</button>
        </div>
      </div>

      <div :if={filtered_tree(@tree, @search_query) == []} class="empty-state">
        <p :if={@search_query != ""}>No results for "<strong>{@search_query}</strong>"</p>
        <p :if={@search_query == ""}>No test files in this snapshot.</p>
      </div>

      <div :for={file <- filtered_tree(@tree, @search_query)} class="product-domain">
        <button class="product-row product-row--domain" phx-click="toggle" phx-value-id={file.relative_path}>
          <span class={"product-chevron#{if MapSet.member?(@expanded, file.relative_path), do: " is-open"}"}>&#9656;</span>
          <code class="product-key">{file.relative_path}</code>
          <span class="product-count">{length(file.tests)} tests</span>
        </button>

        <div :if={MapSet.member?(@expanded, file.relative_path)} class="product-children">
          <div :for={test <- file.tests} class="product-requirement">
            <div class="product-row product-row--req">
              <span :if={test[:framework]} class="product-spec-badge is-ok" style="font-size: 9px;">{test.framework}</span>
              <span :if={test[:describe_path] && test.describe_path != []} class="product-name">
                {Enum.join(test.describe_path, " > ")}
              </span>
              <span class="product-statement">{test.test_name}</span>
              <.commit_hash hash={test[:source_commit_hash]} cache={@commit_id_cache} />
            </div>
            <div :if={test[:given] && test.given != []} class="product-rationale">
              <strong>Given:</strong> {Enum.join(test.given, ", ")}
            </div>
            <div :if={test[:when] && test.when != []} class="product-rationale">
              <strong>When:</strong> {Enum.join(test.when, ", ")}
            </div>
            <div :if={test[:then] && test.then != []} class="product-rationale">
              <strong>Then:</strong> {Enum.join(test.then, ", ")}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp commit_hash(assigns) do
    ~H"""
    <span :if={@hash} class="product-commit">
      <a :if={@cache[@hash]} href={"/history/commits/#{@cache[@hash]}"}>
        <code>{String.slice(@hash, 0, 7)}</code>
      </a>
      <code :if={!@cache[@hash]}>{String.slice(@hash, 0, 7)}</code>
    </span>
    """
  end

  # -- Data loading ------------------------------------------------------------

  defp load_timeline(socket) do
    project_id = socket.assigns.selected_project_id

    if project_id do
      Tracer.with_span "spotter.tests_live.load_timeline" do
        Tracer.set_attribute("spotter.project_id", project_id)

        result =
          try do
            TestCommitTimeline.list(%{project_id: project_id})
          rescue
            e ->
              Tracer.set_status(:error, Exception.message(e))
              %{rows: [], cursor: nil, has_more: false}
          end

        assign(socket,
          commit_rows: result.rows,
          commit_cursor: result.cursor,
          commit_has_more: result.has_more
        )
      end
    else
      assign(socket, commit_rows: [], commit_cursor: nil, commit_has_more: false)
    end
  end

  defp load_more_commits(socket) do
    project_id = socket.assigns.selected_project_id
    cursor = socket.assigns.commit_cursor

    if project_id && cursor do
      Tracer.with_span "spotter.tests_live.load_more" do
        Tracer.set_attribute("spotter.project_id", project_id)

        result =
          try do
            TestCommitTimeline.list(%{project_id: project_id}, %{after: cursor})
          rescue
            e ->
              Tracer.set_status(:error, Exception.message(e))
              %{rows: [], cursor: nil, has_more: false}
          end

        assign(socket,
          commit_rows: socket.assigns.commit_rows ++ result.rows,
          commit_cursor: result.cursor,
          commit_has_more: result.has_more
        )
      end
    else
      socket
    end
  end

  defp load_selected_commit(socket, nil) do
    assign(socket, selected_commit_id: nil, selected_commit: nil)
  end

  defp load_selected_commit(socket, commit_id) do
    case Commit |> Ash.Query.filter(id == ^commit_id) |> Ash.read_one() do
      {:ok, %Commit{} = commit} ->
        assign(socket, selected_commit_id: commit_id, selected_commit: commit)

      _ ->
        assign(socket, selected_commit_id: nil, selected_commit: nil)
    end
  end

  defp load_detail(socket) do
    commit = socket.assigns.selected_commit
    project_id = socket.assigns.selected_project_id

    if commit && project_id && socket.assigns.dolt_available do
      Tracer.with_span "spotter.tests_live.load_detail" do
        view = socket.assigns.spec_view
        Tracer.set_attribute("spotter.project_id", project_id)
        Tracer.set_attribute("spotter.commit_hash", commit.commit_hash)
        Tracer.set_attribute("spotter.view_mode", Atom.to_string(view))

        load_detail_for_view(socket, view, project_id, commit)
      end
    else
      assign(socket, detail_content: nil, detail_error: nil, tree: [], commit_id_cache: %{})
    end
  end

  defp load_detail_for_view(socket, :diff, project_id, commit) do
    case TestSpec.diff_for_commit(project_id, commit.commit_hash) do
      {:ok, diff} ->
        assign(socket, detail_content: diff, detail_error: nil, tree: [], commit_id_cache: %{})

      {:error, reason} ->
        assign(socket,
          detail_content: nil,
          detail_error: reason,
          tree: [],
          commit_id_cache: %{}
        )
    end
  rescue
    e ->
      Tracer.set_status(:error, Exception.message(e))

      assign(socket,
        detail_content: nil,
        detail_error: {:error, Exception.message(e)},
        tree: [],
        commit_id_cache: %{}
      )
  end

  defp load_detail_for_view(socket, :snapshot, project_id, commit) do
    case TestSpec.tree_for_commit(project_id, commit.commit_hash) do
      {:ok, %{tree: tree} = result} ->
        cache = build_commit_cache(collect_commit_hashes(tree))

        assign(socket,
          detail_content: result,
          detail_error: nil,
          tree: tree,
          expanded: MapSet.new(),
          commit_id_cache: cache
        )

      {:error, reason} ->
        assign(socket,
          detail_content: nil,
          detail_error: reason,
          tree: [],
          commit_id_cache: %{}
        )
    end
  rescue
    e ->
      Tracer.set_status(:error, Exception.message(e))

      assign(socket,
        detail_content: nil,
        detail_error: {:error, Exception.message(e)},
        tree: [],
        commit_id_cache: %{}
      )
  end

  defp error_message(:no_test_run) do
    "Test analysis not available for this commit yet."
  end

  defp error_message({:dolt_query_failed, reason}) do
    "Unable to load test specs from Dolt snapshot: #{error_reason_to_string(reason)}"
  end

  defp error_message({:error, reason}) do
    "Failed to load test data: #{error_reason_to_string(reason)}"
  end

  defp error_message(reason) do
    "Failed to load test data: #{error_reason_to_string(reason)}"
  end

  defp error_reason_to_string(reason) when is_binary(reason), do: reason
  defp error_reason_to_string(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp error_reason_to_string({:dolt_query_failed, reason}),
    do: "dolt_query_failed: #{error_reason_to_string(reason)}"

  defp error_reason_to_string({:error, reason}), do: "error: #{error_reason_to_string(reason)}"
  defp error_reason_to_string(reason), do: inspect(reason)

  # -- Helpers -----------------------------------------------------------------

  defp build_params(project_id, commit_id, spec_view) do
    params = %{}
    params = if project_id, do: Map.put(params, "project_id", project_id), else: params
    params = if commit_id, do: Map.put(params, "commit_id", commit_id), else: params
    if spec_view != :diff, do: Map.put(params, "spec_view", spec_view), else: params
  end

  defp format_date(commit) do
    date = commit.committed_at || commit.inserted_at

    if date do
      Calendar.strftime(date, "%Y-%m-%d %H:%M")
    else
      ""
    end
  end

  defp format_test_key(%{test_key: key}) when is_binary(key), do: key
  defp format_test_key(%{relative_path: p, test_name: n}), do: "#{p} > #{n}"
  defp format_test_key(_), do: ""

  defp test_name(%{test_name: name}) when is_binary(name), do: name
  defp test_name(_), do: nil

  defp format_field_value(val) when is_list(val), do: inspect(val)
  defp format_field_value(val) when is_map(val), do: inspect(val)
  defp format_field_value(nil), do: ""
  defp format_field_value(val), do: to_string(val)

  defp collect_commit_hashes(tree) do
    tree
    |> Enum.flat_map(fn file ->
      Enum.map(file.tests, & &1[:source_commit_hash])
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp build_commit_cache([]), do: %{}

  defp build_commit_cache(hashes) do
    case Commit |> Ash.Query.filter(commit_hash in ^hashes) |> Ash.read() do
      {:ok, commits} -> Map.new(commits, &{&1.commit_hash, &1.id})
      _ -> %{}
    end
  end

  defp filtered_tree(tree, ""), do: tree

  defp filtered_tree(tree, q) do
    q = String.downcase(q)

    tree
    |> Enum.map(&filter_file(&1, q))
    |> Enum.filter(fn file ->
      file.tests != [] || matches?(file.relative_path, q)
    end)
  end

  defp filter_file(file, q) do
    if matches?(file.relative_path, q) do
      file
    else
      tests =
        Enum.filter(file.tests, fn test ->
          matches?(test.test_name, q) ||
            matches?(test[:framework], q) ||
            matches_list?(test[:describe_path], q)
        end)

      %{file | tests: tests}
    end
  end

  defp matches?(nil, _q), do: false
  defp matches?(text, q), do: text |> String.downcase() |> String.contains?(q)

  defp matches_list?(nil, _q), do: false
  defp matches_list?(list, q), do: Enum.any?(list, &matches?(&1, q))

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil
  defp parse_project_id(id), do: id

  defp parse_spec_view("snapshot"), do: :snapshot
  defp parse_spec_view(_), do: :diff
end
