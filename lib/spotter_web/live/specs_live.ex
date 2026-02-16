defmodule SpotterWeb.SpecsLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  alias Spotter.Services.ProductCommitTimeline
  alias Spotter.Services.SpecTestLinks
  alias Spotter.Services.TestCommitTimeline
  alias Spotter.Transcripts.{Commit, Project}

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  attach_computer(SpotterWeb.Live.SpecsComputers, :specs_view)

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
       # Timeline pagination (managed outside computer for append semantics)
       commit_cursor: nil,
       commit_has_more: false,
       # Tree UI state
       tree: [],
       expanded: MapSet.new(),
       commit_id_cache: %{},
       spec_test_link_counts: %{},
       # Focus cross-link keys
       focus_test_key: nil,
       focus_spec_key: nil
     )
     |> mount_computers(%{
       specs_view: %{project_id: first_project_id(projects)}
     })}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id =
      normalize_project_id(socket.assigns.projects, parse_project_id(params["project_id"]))

    commit_id = params["commit_id"]
    search_q = params["q"] || ""
    artifact = parse_artifact(params["artifact"])

    spec_view =
      if search_q != "" && !params["spec_view"],
        do: :snapshot,
        else: parse_spec_view(params["spec_view"])

    focus_test_key = params["focus_test_key"]
    focus_spec_key = params["focus_spec_key"]

    project_changed = project_id != socket.assigns.specs_view_project_id

    socket =
      socket
      |> assign(
        focus_test_key: focus_test_key,
        focus_spec_key: focus_spec_key
      )
      |> update_computer_inputs(:specs_view, %{
        project_id: project_id,
        commit_id: commit_id,
        artifact: artifact,
        spec_view: spec_view,
        search_query: search_q
      })
      |> then(fn s ->
        if project_changed do
          load_timeline(s)
        else
          s
        end
      end)
      |> load_detail_ui_state()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = normalize_project_id(socket.assigns.projects, parse_project_id(raw_id))
    {:noreply, push_patch(socket, to: specs_path(%{project_id: project_id}))}
  end

  def handle_event("select_commit", %{"commit-id" => commit_id}, socket) do
    params =
      current_params(socket)
      |> Map.put(:commit_id, commit_id)

    {:noreply, push_patch(socket, to: specs_path(params))}
  end

  def handle_event("set_artifact", %{"artifact" => artifact}, socket) do
    params =
      current_params(socket)
      |> Map.put(:artifact, parse_artifact(artifact))

    {:noreply, push_patch(socket, to: specs_path(params))}
  end

  def handle_event("set_view", %{"view" => view}, socket) do
    params =
      current_params(socket)
      |> Map.put(:spec_view, parse_spec_view(view))

    {:noreply, push_patch(socket, to: specs_path(params))}
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
    ids = collect_expandable_ids(socket.assigns.tree, socket.assigns.specs_view_artifact)
    {:noreply, assign(socket, expanded: MapSet.new(ids))}
  end

  def handle_event("collapse_all", _params, socket) do
    {:noreply, assign(socket, expanded: MapSet.new())}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, assign(socket, search_query: String.trim(q))}
  end

  # -- Render ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-header">
        <div>
          <h1>Specs</h1>
          <p class="text-muted text-sm">Product and test specifications derived from commits</p>
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
              class={"filter-btn#{if @specs_view_project_id == project.id, do: " is-active"}"}
            >
              {project.name}
            </button>
          </div>
        </div>
      </div>

      <.dolt_callout
        product_available={@specs_view_product_dolt_available}
        tests_available={@specs_view_tests_dolt_available}
        artifact={@specs_view_artifact}
      />

      <div :if={@specs_view_project_id != nil} class="product-layout">
        <div class="product-timeline">
          <div class="product-timeline-header">
            <span class="product-timeline-title">Commits</span>
            <span class="product-timeline-count">{length(@specs_view_commit_rows)}</span>
          </div>

          <div :if={@specs_view_commit_rows == []} class="product-timeline-empty">
            <p>No commits linked to this project yet.</p>
          </div>

          <button
            :for={row <- @specs_view_commit_rows}
            class={"product-timeline-row#{if @specs_view_commit_id == row.commit.id, do: " is-selected"}"}
            phx-click="select_commit"
            phx-value-commit-id={row.commit.id}
            aria-current={if @specs_view_commit_id == row.commit.id, do: "true"}
          >
            <div class="product-timeline-row-main">
              <code class="product-timeline-hash">{String.slice(row.commit.commit_hash, 0, 8)}</code>
              <span class="product-timeline-subject">{row.commit.subject || "(no subject)"}</span>
            </div>
            <div class="product-timeline-row-meta">
              <span class="product-timeline-date">{format_date(row.commit)}</span>
              <.spec_badge run={row.spec_run} label="product" />
              <.test_run_badge run={row.test_run} label="tests" />
            </div>
          </button>

          <div :if={@commit_has_more} class="product-timeline-more">
            <button phx-click="load_more" class="btn btn-ghost btn-sm">Load more</button>
          </div>
        </div>

        <div class="product-detail">
          <div :if={@specs_view_selected_commit == nil} class="product-detail-empty">
            <p>Select a commit to view its specifications.</p>
          </div>

          <div :if={@specs_view_selected_commit != nil}>
            <div class="product-detail-header">
              <div class="product-detail-commit-info">
                <code class="product-detail-hash">{@specs_view_selected_commit.commit_hash}</code>
                <span class="product-detail-subject">{@specs_view_selected_commit.subject || "(no subject)"}</span>
              </div>
              <div class="specs-controls">
                <div class="specs-artifact-toggle">
                  <button
                    phx-click="set_artifact"
                    phx-value-artifact="product"
                    class={"btn btn-sm#{if @specs_view_artifact == :product, do: " btn-active", else: " btn-ghost"}"}
                  >
                    Product
                  </button>
                  <button
                    phx-click="set_artifact"
                    phx-value-artifact="tests"
                    class={"btn btn-sm#{if @specs_view_artifact == :tests, do: " btn-active", else: " btn-ghost"}"}
                  >
                    Tests
                  </button>
                </div>
                <div class="product-detail-toggle">
                  <button
                    phx-click="set_view"
                    phx-value-view="diff"
                    class={"btn btn-sm#{if @specs_view_spec_view == :diff, do: " btn-active", else: " btn-ghost"}"}
                  >
                    Diff
                  </button>
                  <button
                    phx-click="set_view"
                    phx-value-view="snapshot"
                    class={"btn btn-sm#{if @specs_view_spec_view == :snapshot, do: " btn-active", else: " btn-ghost"}"}
                  >
                    Snapshot
                  </button>
                </div>
              </div>
            </div>

            <.artifact_dolt_callout
              available={artifact_dolt_available?(assigns)}
              artifact={@specs_view_artifact}
            />

            <div :if={artifact_dolt_available?(assigns)}>
              <.artifact_detail
                artifact={@specs_view_artifact}
                spec_view={@specs_view_spec_view}
                active_detail={@specs_view_active_detail}
                tree={@tree}
                expanded={@expanded}
                search_query={@specs_view_search_query}
                commit_id_cache={@commit_id_cache}
                spec_test_link_counts={@spec_test_link_counts}
                selected_project_id={@specs_view_project_id}
                selected_commit_id={@specs_view_commit_id}
                focus_test_key={@focus_test_key}
                focus_spec_key={@focus_spec_key}
              />
            </div>
          </div>
        </div>
      </div>

      <div :if={@specs_view_project_id == nil} class="empty-state">
        <p>Select a project to view its specifications.</p>
      </div>
    </div>
    """
  end

  # -- Components --------------------------------------------------------------

  defp dolt_callout(assigns) do
    ~H"""
    <div
      :if={not @product_available and @artifact == :product}
      class="product-callout"
    >
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
        <circle cx="8" cy="8" r="6" /><line x1="8" y1="5" x2="8" y2="8" /><circle cx="8" cy="11" r="0.5" fill="currentColor" />
      </svg>
      <span>Product Dolt is unavailable. Start it with <code>docker compose -f docker-compose.dolt.yml up -d</code></span>
    </div>
    <div
      :if={not @tests_available and @artifact == :tests}
      class="product-callout"
    >
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
        <circle cx="8" cy="8" r="6" /><line x1="8" y1="5" x2="8" y2="8" /><circle cx="8" cy="11" r="0.5" fill="currentColor" />
      </svg>
      <span>Tests Dolt is unavailable. Start it with <code>docker compose -f docker-compose.dolt.yml up -d</code></span>
    </div>
    """
  end

  defp artifact_dolt_callout(assigns) do
    ~H"""
    <div :if={not @available} class="product-callout" style="margin-top: var(--space-4);">
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
        <circle cx="8" cy="8" r="6" /><line x1="8" y1="5" x2="8" y2="8" /><circle cx="8" cy="11" r="0.5" fill="currentColor" />
      </svg>
      <span>
        Dolt is unavailable. {if @artifact == :product, do: "Product spec", else: "Test"} data cannot be loaded.
      </span>
    </div>
    """
  end

  defp artifact_detail(%{active_detail: nil} = assigns) do
    ~H"""
    <div class="product-detail-message">
      <p>{no_data_message(@artifact)}</p>
    </div>
    """
  end

  defp artifact_detail(%{spec_view: :diff} = assigns) do
    ~H"""
    <div :if={@active_detail.error != nil} class="product-detail-message">
      <p>{error_message(@artifact, @active_detail.error)}</p>
    </div>

    <div :if={@active_detail.error == nil and @active_detail.content != nil}>
      <.diff_view artifact={@artifact} content={@active_detail.content} />
    </div>
    """
  end

  defp artifact_detail(%{spec_view: :snapshot} = assigns) do
    ~H"""
    <div :if={@active_detail.error != nil} class="product-detail-message">
      <p>{error_message(@artifact, @active_detail.error)}</p>
    </div>

    <div :if={@active_detail.error == nil and @active_detail.content != nil}>
      <.snapshot_view
        artifact={@artifact}
        content={@active_detail.content}
        tree={@tree}
        expanded={@expanded}
        search_query={@search_query}
        commit_id_cache={@commit_id_cache}
        spec_test_link_counts={@spec_test_link_counts}
        selected_project_id={@selected_project_id}
        selected_commit_id={@selected_commit_id}
        focus_test_key={@focus_test_key}
        focus_spec_key={@focus_spec_key}
      />
    </div>
    """
  end

  # -- Diff views --------------------------------------------------------------

  defp diff_view(%{artifact: :product} = assigns) do
    ~H"""
    <div :if={@content[:kind] == :no_changes} class="product-detail-message">
      <p>No product spec changes in this commit.</p>
    </div>

    <div :if={@content[:kind] != :no_changes} class="product-diff">
      <.product_diff_section
        :if={@content.added != []}
        label="Added"
        kind="added"
        items={@content.added}
      />
      <.product_diff_section
        :if={@content.changed != []}
        label="Changed"
        kind="changed"
        items={@content.changed}
      />
      <.product_diff_section
        :if={@content.removed != []}
        label="Removed"
        kind="removed"
        items={@content.removed}
      />
      <div
        :if={@content.added == [] and @content.changed == [] and @content.removed == []}
        class="product-detail-message"
      >
        <p>No product spec changes in this commit.</p>
      </div>
    </div>
    """
  end

  defp diff_view(%{artifact: :tests} = assigns) do
    ~H"""
    <div :if={@content[:kind] == :no_changes} class="product-detail-message">
      <p>No test changes in this commit.</p>
    </div>

    <div :if={@content[:kind] != :no_changes} class="product-diff">
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

  defp product_diff_section(assigns) do
    ~H"""
    <div class={"product-diff-section is-#{@kind}"}>
      <h3 class="product-diff-section-label">{@label}</h3>
      <div :for={item <- @items} class="product-diff-item">
        <.product_diff_item_content item={item} kind={@kind} />
      </div>
    </div>
    """
  end

  defp product_diff_item_content(%{kind: "changed"} = assigns) do
    ~H"""
    <div class="product-diff-change">
      <div class="product-diff-change-header">
        <span class="product-diff-level">{@item.level}</span>
        <code class="product-key">{format_diff_key(@item.key)}</code>
      </div>
      <div :for={field <- @item.changed_fields} class="product-diff-field">
        <span class="product-diff-field-name">{field}</span>
        <div class="product-diff-before">{format_changed_field_value(field, Map.get(@item.before, field))}</div>
        <div class="product-diff-after">{format_changed_field_value(field, Map.get(@item.after, field))}</div>
      </div>
    </div>
    """
  end

  defp product_diff_item_content(assigns) do
    ~H"""
    <div class="product-diff-entry">
      <span class="product-diff-level">{@item.level}</span>
      <code class="product-key">{format_diff_key(@item.key)}</code>
      <span :if={@item.data[:name]} class="product-name">{@item.data.name}</span>
      <span :if={@item.data[:statement]} class="product-statement">{@item.data.statement}</span>
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

  # -- Snapshot views ----------------------------------------------------------

  defp snapshot_view(%{artifact: :product} = assigns) do
    ~H"""
    <div :if={@content.tree == [] and @content.effective_dolt_commit_hash == nil} class="product-detail-message">
      <p>No product spec available yet for this project.</p>
    </div>

    <div :if={@content.tree != [] or @content.effective_dolt_commit_hash != nil}>
      <.snapshot_toolbar search_query={@search_query} placeholder="Search domains, features, requirements..." />

      <div :if={filtered_product_tree(@tree, @search_query) == []} class="empty-state">
        <p :if={@search_query != ""}>No results for "<strong>{@search_query}</strong>"</p>
        <p :if={@search_query == ""}>No domains in this snapshot.</p>
      </div>

      <div :for={domain <- filtered_product_tree(@tree, @search_query)} class="product-domain">
        <button class="product-row product-row--domain" phx-click="toggle" phx-value-id={domain.id}>
          <span class={"product-chevron#{if MapSet.member?(@expanded, domain.id), do: " is-open"}"}>&#9656;</span>
          <span class="product-name">{domain.name}</span>
          <code class="product-key">{domain.spec_key}</code>
          <.commit_hash hash={domain.updated_by_git_commit} cache={@commit_id_cache} />
          <span class="product-count">{length(domain.features)} features</span>
        </button>

        <div :if={MapSet.member?(@expanded, domain.id)} class="product-children">
          <div :for={feature <- domain.features} class="product-feature">
            <button class="product-row product-row--feature" phx-click="toggle" phx-value-id={feature.id}>
              <span class={"product-chevron#{if MapSet.member?(@expanded, feature.id), do: " is-open"}"}>&#9656;</span>
              <span class="product-name">{feature.name}</span>
              <code class="product-key">{feature.spec_key}</code>
              <.commit_hash hash={feature.updated_by_git_commit} cache={@commit_id_cache} />
              <span class="product-count">{length(feature.requirements)} reqs</span>
            </button>

            <div :if={MapSet.member?(@expanded, feature.id)} class="product-children">
              <div
                :for={req <- feature.requirements}
                class={"product-requirement#{if @focus_test_key && Map.get(@spec_test_link_counts, req.spec_key, 0) > 0, do: " is-highlight", else: ""}"}
              >
                <div class="product-row product-row--req">
                  <code class="product-key">{req.spec_key}</code>
                  <span class="product-statement">{req.statement}</span>
                  <.commit_hash hash={req.updated_by_git_commit} cache={@commit_id_cache} />
                  <.linked_test_count
                    count={Map.get(@spec_test_link_counts, req.spec_key, 0)}
                    project_id={@selected_project_id}
                    commit_id={@selected_commit_id}
                    spec_key={req.spec_key}
                  />
                </div>
                <p :if={req.rationale} class="product-rationale">{req.rationale}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp snapshot_view(%{artifact: :tests} = assigns) do
    ~H"""
    <div :if={@content.tree == [] and @content.effective_dolt_commit_hash == nil} class="product-detail-message">
      <p>No test specifications available yet for this project.</p>
    </div>

    <div :if={@content.tree != [] or @content.effective_dolt_commit_hash != nil}>
      <.snapshot_toolbar search_query={@search_query} placeholder="Search files, tests, frameworks..." />

      <div :if={filtered_test_tree(@tree, @search_query) == []} class="empty-state">
        <p :if={@search_query != ""}>No results for "<strong>{@search_query}</strong>"</p>
        <p :if={@search_query == ""}>No test files in this snapshot.</p>
      </div>

      <div :for={file <- filtered_test_tree(@tree, @search_query)} class="product-domain">
        <button class="product-row product-row--domain" phx-click="toggle" phx-value-id={file.relative_path}>
          <span class={"product-chevron#{if MapSet.member?(@expanded, file.relative_path), do: " is-open"}"}>&#9656;</span>
          <code class="product-key">{file.relative_path}</code>
          <span class="product-count">{length(file.tests)} tests</span>
        </button>

        <div :if={MapSet.member?(@expanded, file.relative_path)} class="product-children">
          <div
            :for={test <- file.tests}
            class={"product-requirement#{if @focus_spec_key && Map.get(@spec_test_link_counts, test[:test_key], 0) > 0, do: " is-highlight", else: ""}"}
          >
            <div class="product-row product-row--req">
              <span :if={test[:framework]} class="product-spec-badge is-ok" style="font-size: 9px;">{test.framework}</span>
              <span :if={test[:describe_path] && test.describe_path != []} class="product-name">
                {Enum.join(test.describe_path, " > ")}
              </span>
              <span class="product-statement">{test.test_name}</span>
              <.commit_hash hash={test[:source_commit_hash]} cache={@commit_id_cache} />
              <.linked_req_count
                count={Map.get(@spec_test_link_counts, test[:test_key], 0)}
                project_id={@selected_project_id}
                commit_id={@selected_commit_id}
                test_key={test[:test_key] || ""}
              />
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

  defp snapshot_toolbar(assigns) do
    ~H"""
    <div class="product-toolbar">
      <div class="product-search">
        <input
          type="text"
          placeholder={@placeholder}
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
    """
  end

  # -- Badge components --------------------------------------------------------

  defp spec_badge(assigns) do
    assigns = assign(assigns, :run_status, normalize_product_run_status(assigns.run))

    ~H"""
    <span :if={@run_status == :none} class="product-spec-badge is-none">product: none</span>
    <span :if={@run_status == :ok_no_changes} class="product-spec-badge is-ok">
      product: ok
    </span>
    <span
      :if={@run_status not in [:none, :ok_no_changes]}
      class={"product-spec-badge is-#{@run_status}"}
    >
      product: {@run_status}
    </span>
    """
  end

  defp test_run_badge(assigns) do
    assigns = assign(assigns, :run_status, normalize_test_run_status(assigns.run))

    ~H"""
    <span :if={@run_status == :none} class="product-spec-badge is-none">tests: none</span>
    <span :if={@run_status == :ok_no_changes} class="product-spec-badge is-ok">
      tests: ok
    </span>
    <span
      :if={@run_status not in [:none, :ok_no_changes]}
      class={"product-spec-badge is-#{@run_status}"}
    >
      tests: {@run_status}
    </span>
    """
  end

  defp normalize_product_run_status(nil), do: :none
  defp normalize_product_run_status(%{status: :ok, dolt_commit_hash: nil}), do: :ok_no_changes

  defp normalize_product_run_status(%{status: status})
       when status in [:pending, :running, :ok, :error, :skipped],
       do: status

  defp normalize_product_run_status(_), do: :none

  defp normalize_test_run_status(nil), do: :none
  defp normalize_test_run_status(%{status: :completed, dolt_commit_hash: nil}), do: :ok_no_changes
  defp normalize_test_run_status(%{status: :completed}), do: :ok

  defp normalize_test_run_status(%{status: status})
       when status in [:queued, :running, :error],
       do: status

  defp normalize_test_run_status(_), do: :none

  # -- Cross-link components ---------------------------------------------------

  defp linked_test_count(%{count: 0} = assigns) do
    ~H"""
    <span class="product-link-count is-zero">0 linked tests</span>
    """
  end

  defp linked_test_count(assigns) do
    ~H"""
    <a
      href={"/specs?project_id=#{@project_id}&commit_id=#{@commit_id}&artifact=tests&focus_spec_key=#{URI.encode_www_form(@spec_key)}&spec_view=snapshot"}
      class="product-link-count"
    >
      {@count} linked {if @count == 1, do: "test", else: "tests"}
    </a>
    """
  end

  defp linked_req_count(%{count: 0} = assigns) do
    ~H"""
    <span class="product-link-count is-zero">0 linked reqs</span>
    """
  end

  defp linked_req_count(assigns) do
    ~H"""
    <a
      href={"/specs?project_id=#{@project_id}&commit_id=#{@commit_id}&artifact=product&focus_test_key=#{URI.encode_www_form(@test_key)}&spec_view=snapshot"}
      class="product-link-count"
    >
      {@count} linked {if @count == 1, do: "req", else: "reqs"}
    </a>
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
    project_id = socket.assigns.specs_view_project_id

    if project_id do
      Tracer.with_span "spotter.specs_live.load_timeline" do
        Tracer.set_attribute("spotter.project_id", project_id)

        product_result =
          try do
            ProductCommitTimeline.list(%{project_id: project_id})
          rescue
            _ -> %{rows: [], cursor: nil, has_more: false}
          end

        test_result =
          try do
            TestCommitTimeline.list(%{project_id: project_id})
          rescue
            _ -> %{rows: [], cursor: nil, has_more: false}
          end

        test_runs_by_commit_id =
          Map.new(test_result.rows, &{&1.commit.id, &1.test_run})

        merged_rows =
          Enum.map(product_result.rows, fn row ->
            %{
              commit: row.commit,
              spec_run: row.spec_run,
              test_run: Map.get(test_runs_by_commit_id, row.commit.id)
            }
          end)

        socket
        |> update_computer_inputs(:specs_view, %{})
        |> assign(
          specs_view_commit_rows: merged_rows,
          commit_cursor: product_result.cursor,
          commit_has_more: product_result.has_more
        )
      end
    else
      assign(socket, commit_cursor: nil, commit_has_more: false)
    end
  end

  defp load_more_commits(socket) do
    project_id = socket.assigns.specs_view_project_id
    cursor = socket.assigns.commit_cursor

    if project_id && cursor do
      Tracer.with_span "spotter.specs_live.load_more" do
        Tracer.set_attribute("spotter.project_id", project_id)

        product_result =
          try do
            ProductCommitTimeline.list(%{project_id: project_id}, %{
              after: cursor
            })
          rescue
            _ -> %{rows: [], cursor: nil, has_more: false}
          end

        test_result =
          try do
            TestCommitTimeline.list(%{project_id: project_id}, %{after: cursor})
          rescue
            _ -> %{rows: [], cursor: nil, has_more: false}
          end

        test_runs_by_commit_id =
          Map.new(test_result.rows, &{&1.commit.id, &1.test_run})

        new_rows =
          Enum.map(product_result.rows, fn row ->
            %{
              commit: row.commit,
              spec_run: row.spec_run,
              test_run: Map.get(test_runs_by_commit_id, row.commit.id)
            }
          end)

        # Append to existing computer rows
        existing = socket.assigns.specs_view_commit_rows

        assign(socket,
          specs_view_commit_rows: existing ++ new_rows,
          commit_cursor: product_result.cursor,
          commit_has_more: product_result.has_more
        )
      end
    else
      socket
    end
  end

  defp load_detail_ui_state(socket) do
    detail = socket.assigns.specs_view_active_detail
    artifact = socket.assigns.specs_view_artifact
    spec_view = socket.assigns.specs_view_spec_view
    link_counts = maybe_load_link_counts(socket, detail, artifact)

    has_snapshot_tree? =
      detail != nil and detail.error == nil and detail.content != nil and spec_view == :snapshot

    if has_snapshot_tree? do
      tree = detail.content.tree || []
      cache = build_commit_cache(collect_commit_hashes(tree, artifact))

      assign(socket,
        tree: tree,
        expanded: MapSet.new(),
        commit_id_cache: cache,
        spec_test_link_counts: link_counts
      )
    else
      assign(socket,
        tree: [],
        commit_id_cache: %{},
        spec_test_link_counts: link_counts
      )
    end
  end

  defp maybe_load_link_counts(socket, detail, artifact) do
    commit = socket.assigns.specs_view_selected_commit
    project_id = socket.assigns.specs_view_project_id

    if commit && project_id && detail && detail.error == nil do
      load_link_counts(artifact, project_id, commit.commit_hash)
    else
      %{}
    end
  end

  defp load_link_counts(:product, project_id, commit_hash) do
    SpecTestLinks.linked_test_counts(project_id, commit_hash)
  end

  defp load_link_counts(:tests, project_id, commit_hash) do
    SpecTestLinks.linked_requirement_counts(project_id, commit_hash)
  end

  # -- Helpers -----------------------------------------------------------------

  defp artifact_dolt_available?(assigns) do
    case assigns.specs_view_artifact do
      :product -> assigns.specs_view_product_dolt_available
      :tests -> assigns.specs_view_tests_dolt_available
    end
  end

  defp specs_path(params) do
    query =
      %{}
      |> maybe_put("project_id", params[:project_id])
      |> maybe_put("commit_id", params[:commit_id])
      |> maybe_put("artifact", artifact_to_param(params[:artifact]))
      |> maybe_put("spec_view", spec_view_to_param(params[:spec_view]))
      |> maybe_put("q", non_empty(params[:q]))

    case URI.encode_query(query) do
      "" -> "/specs"
      qs -> "/specs?#{qs}"
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp artifact_to_param(:product), do: nil
  defp artifact_to_param(:tests), do: "tests"
  defp artifact_to_param(val), do: val

  defp spec_view_to_param(:diff), do: nil
  defp spec_view_to_param(:snapshot), do: "snapshot"
  defp spec_view_to_param(val), do: val

  defp non_empty(""), do: nil
  defp non_empty(nil), do: nil
  defp non_empty(val), do: val

  defp current_params(socket) do
    %{
      project_id: socket.assigns.specs_view_project_id,
      commit_id: socket.assigns.specs_view_commit_id,
      artifact: socket.assigns.specs_view_artifact,
      spec_view: socket.assigns.specs_view_spec_view,
      q: socket.assigns.specs_view_search_query
    }
  end

  defp format_date(commit) do
    date = commit.committed_at || commit.inserted_at

    if date do
      Calendar.strftime(date, "%Y-%m-%d %H:%M")
    else
      ""
    end
  end

  defp format_diff_key(key) when is_tuple(key), do: key |> Tuple.to_list() |> Enum.join(".")

  defp format_test_key(%{test_key: key}) when is_binary(key), do: key
  defp format_test_key(%{relative_path: p, test_name: n}), do: "#{p} > #{n}"
  defp format_test_key(_), do: ""

  defp test_name(%{test_name: name}) when is_binary(name), do: name
  defp test_name(_), do: nil

  defp format_changed_field_value(:acceptance_criteria, nil), do: ""
  defp format_changed_field_value(:acceptance_criteria, value) do
    value
    |> normalize_acceptance_criteria()
    |> format_acceptance_criteria_lines()
  end

  defp format_changed_field_value("acceptance_criteria", nil), do: ""
  defp format_changed_field_value("acceptance_criteria", value) do
    value
    |> normalize_acceptance_criteria()
    |> format_acceptance_criteria_lines()
  end

  defp format_changed_field_value(_field, value), do: format_field_value(value)

  defp normalize_acceptance_criteria(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, decoded} -> decoded
      {:error, _} -> raw
    end
  end

  defp normalize_acceptance_criteria(raw), do: raw

  defp format_acceptance_criteria_lines(list) when is_list(list) do
    Enum.map_join(list, "\n", &to_string/1)
  end

  defp format_acceptance_criteria_lines(value), do: to_string(value)

  defp format_field_value(val) when is_list(val), do: inspect(val)
  defp format_field_value(val) when is_map(val), do: inspect(val)
  defp format_field_value(nil), do: ""
  defp format_field_value(val), do: to_string(val)

  defp no_data_message(:product), do: "Spec not available for this commit yet."
  defp no_data_message(:tests), do: "Test analysis not available for this commit yet."

  defp error_message(:product, :no_spec_run), do: "Spec not available for this commit yet."
  defp error_message(:tests, :no_test_run), do: "Test analysis not available for this commit yet."

  defp error_message(_artifact, {:dolt_query_failed, reason}) do
    "Unable to load from Dolt snapshot: #{error_reason_to_string(reason)}"
  end

  defp error_message(_artifact, {:error, reason}) do
    "Failed to load data: #{error_reason_to_string(reason)}"
  end

  defp error_message(_artifact, reason) do
    "Failed to load data: #{error_reason_to_string(reason)}"
  end

  defp error_reason_to_string(reason) when is_binary(reason), do: reason
  defp error_reason_to_string(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp error_reason_to_string({:dolt_query_failed, reason}),
    do: "dolt_query_failed: #{error_reason_to_string(reason)}"

  defp error_reason_to_string({:error, reason}), do: "error: #{error_reason_to_string(reason)}"
  defp error_reason_to_string(reason), do: inspect(reason)

  defp collect_commit_hashes(tree, :product) do
    tree
    |> Enum.flat_map(fn domain ->
      [domain.updated_by_git_commit] ++
        Enum.flat_map(domain.features, fn feature ->
          [feature.updated_by_git_commit] ++
            Enum.map(feature.requirements, & &1.updated_by_git_commit)
        end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp collect_commit_hashes(tree, :tests) do
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

  defp collect_expandable_ids(tree, :product) do
    for domain <- tree,
        id <- [domain.id | Enum.map(domain.features, & &1.id)],
        do: id
  end

  defp collect_expandable_ids(tree, :tests) do
    Enum.map(tree, & &1.relative_path)
  end

  # -- Product tree filtering --------------------------------------------------

  defp filtered_product_tree(tree, ""), do: tree

  defp filtered_product_tree(tree, q) do
    q = String.downcase(q)

    tree
    |> Enum.map(&filter_product_domain(&1, q))
    |> Enum.filter(fn domain ->
      domain.features != [] ||
        matches?(domain.name, q) ||
        matches?(domain.spec_key, q)
    end)
  end

  defp filter_product_domain(domain, q) do
    features =
      domain.features
      |> Enum.map(&filter_product_feature(&1, q))
      |> Enum.filter(fn feature ->
        feature.requirements != [] ||
          matches?(feature.name, q) ||
          matches?(feature.spec_key, q) ||
          matches?(feature.description, q)
      end)

    %{domain | features: features}
  end

  defp filter_product_feature(feature, q) do
    reqs =
      Enum.filter(feature.requirements, fn req ->
        matches?(req.spec_key, q) ||
          matches?(req.statement, q) ||
          matches?(req.rationale, q)
      end)

    %{feature | requirements: reqs}
  end

  # -- Test tree filtering -----------------------------------------------------

  defp filtered_test_tree(tree, ""), do: tree

  defp filtered_test_tree(tree, q) do
    q = String.downcase(q)

    tree
    |> Enum.map(&filter_test_file(&1, q))
    |> Enum.filter(fn file ->
      file.tests != [] || matches?(file.relative_path, q)
    end)
  end

  defp filter_test_file(file, q) do
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

  defp first_project_id(projects), do: List.first(projects) |> then(&(&1 && &1.id))

  defp normalize_project_id(projects, project_id) do
    first = first_project_id(projects)

    case project_id do
      nil -> first
      _ -> if Enum.any?(projects, &(&1.id == project_id)), do: project_id, else: first
    end
  end

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil
  defp parse_project_id(id), do: id

  defp parse_artifact("tests"), do: :tests
  defp parse_artifact(_), do: :product

  defp parse_spec_view("snapshot"), do: :snapshot
  defp parse_spec_view(_), do: :diff
end
