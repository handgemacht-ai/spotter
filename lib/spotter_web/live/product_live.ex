defmodule SpotterWeb.ProductLive do
  use Phoenix.LiveView

  alias Spotter.ProductSpec
  alias Spotter.Services.ProductCommitTimeline
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
       dolt_available: dolt_available?(),
       commit_id_cache: %{}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = parse_project_id(params["project_id"])
    project_id = project_id || socket.assigns.projects |> List.first() |> then(&(&1 && &1.id))

    commit_id = params["commit_id"]
    spec_view = parse_spec_view(params["spec_view"])

    project_changed = project_id != socket.assigns.selected_project_id

    socket =
      socket
      |> assign(selected_project_id: project_id, spec_view: spec_view)
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
    path = if project_id, do: "/product?project_id=#{project_id}", else: "/product"
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("select_commit", %{"commit-id" => commit_id}, socket) do
    params = build_params(socket.assigns.selected_project_id, commit_id, socket.assigns.spec_view)
    {:noreply, push_patch(socket, to: "/product?#{URI.encode_query(params)}")}
  end

  def handle_event("set_view", %{"view" => view}, socket) do
    spec_view = parse_spec_view(view)

    params =
      build_params(
        socket.assigns.selected_project_id,
        socket.assigns.selected_commit_id,
        spec_view
      )

    {:noreply, push_patch(socket, to: "/product?#{URI.encode_query(params)}")}
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
    ids =
      for domain <- socket.assigns.tree,
          id <- [domain.id | Enum.map(domain.features, & &1.id)],
          do: id

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
          <h1>Product</h1>
          <p class="text-muted text-sm">Rolling spec derived from commits</p>
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
              <.spec_badge run={row.spec_run} />
            </div>
          </button>

          <div :if={@commit_has_more} class="product-timeline-more">
            <button phx-click="load_more" class="btn btn-ghost btn-sm">Load more</button>
          </div>
        </div>

        <div class="product-detail">
          <div :if={@selected_commit == nil} class="product-detail-empty">
            <p>Select a commit to view its product spec.</p>
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
              <span>Dolt is unavailable. Spec data cannot be loaded.</span>
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
        <p>Select a project to view its product specification.</p>
      </div>
    </div>
    """
  end

  # -- Components --------------------------------------------------------------

  defp spec_badge(assigns) do
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
  defp normalize_run_status(%{status: :ok, dolt_commit_hash: nil}), do: :ok_no_changes

  defp normalize_run_status(%{status: status})
       when status in [:pending, :running, :ok, :error, :skipped],
       do: status

  defp normalize_run_status(_), do: :none

  defp detail_diff(assigns) do
    ~H"""
    <div :if={@error != nil} class="product-detail-message">
      <p>{error_message(@error)}</p>
    </div>

    <div :if={@error == nil and @content != nil and @content[:kind] == :no_changes} class="product-detail-message">
      <p>No product spec changes in this commit.</p>
    </div>

    <div :if={@error == nil and @content != nil and @content[:kind] != :no_changes} class="product-diff">
      <.diff_section
        :if={@content.added != []}
        label="Added"
        kind="added"
        items={@content.added}
      />
      <.diff_section
        :if={@content.changed != []}
        label="Changed"
        kind="changed"
        items={@content.changed}
      />
      <.diff_section
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

  defp diff_section(assigns) do
    ~H"""
    <div class={"product-diff-section is-#{@kind}"}>
      <h3 class="product-diff-section-label">{@label}</h3>
      <div :for={item <- @items} class="product-diff-item">
        <.diff_item_content item={item} kind={@kind} />
      </div>
    </div>
    """
  end

  defp diff_item_content(%{kind: "changed"} = assigns) do
    ~H"""
    <div class="product-diff-change">
      <div class="product-diff-change-header">
        <span class="product-diff-level">{@item.level}</span>
        <code class="product-key">{format_diff_key(@item.key)}</code>
      </div>
      <div :for={field <- @item.changed_fields} class="product-diff-field">
        <span class="product-diff-field-name">{field}</span>
        <div class="product-diff-before">{Map.get(@item.before, field)}</div>
        <div class="product-diff-after">{Map.get(@item.after, field)}</div>
      </div>
    </div>
    """
  end

  defp diff_item_content(assigns) do
    ~H"""
    <div class="product-diff-entry">
      <span class="product-diff-level">{@item.level}</span>
      <code class="product-key">{format_diff_key(@item.key)}</code>
      <span :if={@item.data[:name]} class="product-name">{@item.data.name}</span>
      <span :if={@item.data[:statement]} class="product-statement">{@item.data.statement}</span>
    </div>
    """
  end

  defp detail_snapshot(assigns) do
    ~H"""
    <div :if={@error != nil} class="product-detail-message">
      <p>{error_message(@error)}</p>
    </div>

    <div :if={@error == nil and @content != nil and @content.tree == [] and @content.effective_dolt_commit_hash == nil} class="product-detail-message">
      <p>No product spec available yet for this project.</p>
    </div>

    <div :if={@error == nil and @content != nil and (@content.tree != [] or @content.effective_dolt_commit_hash != nil)}>
      <div class="product-toolbar">
        <div class="product-search">
          <input
            type="text"
            placeholder="Search domains, features, requirements..."
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
        <p :if={@search_query == ""}>No domains in this snapshot.</p>
      </div>

      <div :for={domain <- filtered_tree(@tree, @search_query)} class="product-domain">
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
              <div :for={req <- feature.requirements} class="product-requirement">
                <div class="product-row product-row--req">
                  <code class="product-key">{req.spec_key}</code>
                  <span class="product-statement">{req.statement}</span>
                  <.commit_hash hash={req.updated_by_git_commit} cache={@commit_id_cache} />
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
      Tracer.with_span "spotter.product_live.load_timeline" do
        Tracer.set_attribute("spotter.project_id", project_id)

        result =
          try do
            ProductCommitTimeline.list(%{project_id: project_id})
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
      Tracer.with_span "spotter.product_live.load_more" do
        Tracer.set_attribute("spotter.project_id", project_id)

        result =
          try do
            ProductCommitTimeline.list(%{project_id: project_id}, %{after: cursor})
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
      Tracer.with_span "spotter.product_live.load_detail" do
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
    case ProductSpec.diff_for_commit(project_id, commit.commit_hash) do
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
    case ProductSpec.tree_for_commit(project_id, commit.commit_hash) do
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

  defp error_message(:no_spec_run) do
    "Spec not available for this commit yet."
  end

  defp error_message({:dolt_query_failed, reason}) do
    "Unable to load product spec from Dolt snapshot: #{error_reason_to_string(reason)}"
  end

  defp error_message({:error, reason}) do
    "Failed to load product spec: #{error_reason_to_string(reason)}"
  end

  defp error_message(reason) do
    "Failed to load product spec: #{error_reason_to_string(reason)}"
  end

  defp error_reason_to_string(reason) when is_binary(reason), do: reason
  defp error_reason_to_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_reason_to_string({:dolt_query_failed, reason}), do: "dolt_query_failed: #{error_reason_to_string(reason)}"
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

  defp format_diff_key(key) when is_tuple(key), do: key |> Tuple.to_list() |> Enum.join(".")

  defp collect_commit_hashes(tree) do
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
    |> Enum.map(&filter_domain(&1, q))
    |> Enum.filter(fn domain ->
      domain.features != [] ||
        matches?(domain.name, q) ||
        matches?(domain.spec_key, q)
    end)
  end

  defp filter_domain(domain, q) do
    features =
      domain.features
      |> Enum.map(&filter_feature(&1, q))
      |> Enum.filter(fn feature ->
        feature.requirements != [] ||
          matches?(feature.name, q) ||
          matches?(feature.spec_key, q) ||
          matches?(feature.description, q)
      end)

    %{domain | features: features}
  end

  defp filter_feature(feature, q) do
    reqs =
      Enum.filter(feature.requirements, fn req ->
        matches?(req.spec_key, q) ||
          matches?(req.statement, q) ||
          matches?(req.rationale, q)
      end)

    %{feature | requirements: reqs}
  end

  defp matches?(nil, _q), do: false
  defp matches?(text, q), do: text |> String.downcase() |> String.contains?(q)

  defp dolt_available? do
    case Process.whereis(Spotter.ProductSpec.Repo) do
      nil -> false
      _pid -> true
    end
  end

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil
  defp parse_project_id(id), do: id

  defp parse_spec_view("snapshot"), do: :snapshot
  defp parse_spec_view(_), do: :diff
end
