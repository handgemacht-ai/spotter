defmodule SpotterWeb.CommitDetailLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  alias Spotter.Transcripts.SessionPresenter

  import SpotterWeb.TranscriptComponents

  attach_computer(SpotterWeb.Live.CommitDetailComputers, :commit_detail)

  @impl true
  def mount(%{"commit_id" => commit_id}, _session, socket) do
    socket =
      socket
      |> mount_computers(%{commit_detail: %{commit_id: commit_id}})

    {:ok, socket}
  end

  @impl true
  def handle_event("select_session", %{"session-id" => session_id}, socket) do
    {:noreply, update_computer_inputs(socket, :commit_detail, %{selected_session_id: session_id})}
  end

  def handle_event("toggle_full_diff", _params, socket) do
    new_val = !socket.assigns.commit_detail_show_full_diff

    {:noreply, update_computer_inputs(socket, :commit_detail, %{show_full_diff: new_val})}
  end

  # No-op for transcript expand events
  def handle_event("transcript_view_toggle_tool_result_group", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("transcript_view_toggle_hook_group", _params, socket) do
    {:noreply, socket}
  end

  defp session_label(session) do
    SessionPresenter.primary_label(session)
  end

  defp badge_text(:observed_in_session, _confidence), do: "Verified"

  defp badge_text(_type, confidence) do
    "Inferred #{round(confidence * 100)}%"
  end

  defp badge_class(:observed_in_session), do: "badge badge-verified"
  defp badge_class(_), do: "badge badge-inferred"

  defp format_timestamp(nil), do: "\u2014"

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div data-testid="commit-detail-root">
      <%= case @commit_detail_error_state do %>
        <% :not_found -> %>
          <div class="breadcrumb">
            <a href="/">Dashboard</a>
            <span class="breadcrumb-sep">/</span>
            <a href="/history">History</a>
            <span class="breadcrumb-sep">/</span>
            <span class="breadcrumb-current">Commit not found</span>
          </div>
          <div class="terminal-connecting">
            <div>
              <div class="terminal-connecting-title">Commit not found</div>
              <div class="terminal-connecting-subtitle">
                The requested commit could not be found.
              </div>
            </div>
          </div>
        <% _ -> %>
          <div class="breadcrumb">
            <a href="/">Dashboard</a>
            <span class="breadcrumb-sep">/</span>
            <a href="/history">History</a>
            <span class="breadcrumb-sep">/</span>
            <span :if={@commit_detail_commit} class="breadcrumb-current">
              {String.slice(@commit_detail_commit.commit_hash, 0, 8)}
            </span>
          </div>

          <%= if @commit_detail_commit do %>
            <div class="commit-detail-layout">
              <%!-- Diff panel --%>
              <div class="commit-detail-diff" data-testid="diff-panel">
                <div class="commit-detail-header">
                  <div class="commit-detail-meta">
                    <code class="commit-hash">{@commit_detail_commit.commit_hash}</code>
                    <span :if={@commit_detail_commit.git_branch} class="commit-branch">
                      {@commit_detail_commit.git_branch}
                    </span>
                  </div>
                  <h2 class="commit-detail-subject">
                    {@commit_detail_commit.subject || "(no subject)"}
                  </h2>
                  <p
                    :if={@commit_detail_commit.body not in [nil, ""]}
                    class="commit-detail-body"
                  >
                    {@commit_detail_commit.body}
                  </p>
                  <div class="commit-detail-info">
                    <span :if={@commit_detail_commit.author_name} class="text-secondary text-sm">
                      {@commit_detail_commit.author_name}
                    </span>
                    <span class="text-muted text-xs">
                      {format_timestamp(@commit_detail_commit.committed_at)}
                    </span>
                    <span :if={@commit_detail_commit.changed_files != []} class="text-muted text-xs">
                      {length(@commit_detail_commit.changed_files)} files changed
                    </span>
                  </div>
                </div>

                <%!-- Project rollup summary --%>
                <div class="commit-detail-summary-section">
                  <div class="commit-detail-section-title">Project Rollup</div>
                  <%= if @commit_detail_rolling_summary do %>
                    <pre class="project-rollup">{@commit_detail_rolling_summary.summary_text}</pre>
                    <div class="text-muted text-xs">
                      Computed: {format_timestamp(@commit_detail_rolling_summary.computed_at)}
                    </div>
                  <% else %>
                    <p class="text-muted text-sm">No rolling summary computed yet.</p>
                  <% end %>
                </div>

                <%!-- Bucket summary --%>
                <div class="commit-detail-summary-section">
                  <div class="commit-detail-section-title">Bucket Summary</div>
                  <%= if @commit_detail_period_summary do %>
                    <pre class="bucket-summary">{@commit_detail_period_summary.summary_text}</pre>
                    <div class="text-muted text-xs">
                      {@commit_detail_period_summary.bucket_kind} starting {@commit_detail_period_summary.bucket_start_date}
                    </div>
                  <% else %>
                    <p class="text-muted text-sm">No bucket summary computed yet.</p>
                  <% end %>
                </div>

                <%!-- Changed files list --%>
                <div :if={@commit_detail_commit.changed_files != []} class="commit-detail-files">
                  <div class="commit-detail-section-title">Changed Files</div>
                  <div :for={file <- @commit_detail_commit.changed_files} class="commit-detail-file">
                    <a
                      :if={@commit_detail_project}
                      href={"/projects/#{@commit_detail_project.id}/files/#{file}"}
                      class="file-link"
                    >
                      {file}
                    </a>
                    <span :if={!@commit_detail_project}>{file}</span>
                  </div>
                </div>

                <%!-- Diff content --%>
                <div
                  class="commit-detail-diff-content"
                  data-testid="diff-content"
                  id="diff-highlighter"
                  phx-hook="DiffHighlighter"
                >
                  <div class="commit-detail-section-title">Diff</div>
                  <pre><code class="language-diff">{@commit_detail_diff_text}</code></pre>
                </div>

                <%!-- Co-change overlaps --%>
                <div :if={@commit_detail_co_change_rows != []} class="commit-detail-cochange">
                  <div class="commit-detail-section-title">
                    Co-Change Groups ({length(@commit_detail_co_change_rows)})
                  </div>
                  <div
                    :for={group <- @commit_detail_co_change_rows}
                    class="commit-detail-cochange-group"
                  >
                    <span class="text-muted text-xs">
                      {group.frequency_30d}x/30d
                    </span>
                    <%= for member <- group.members do %>
                      <a
                        :if={@commit_detail_project}
                        href={"/projects/#{@commit_detail_project.id}/files/#{member}"}
                        class="commit-detail-cochange-member file-link"
                      >
                        {member}
                      </a>
                      <span :if={!@commit_detail_project} class="commit-detail-cochange-member">
                        {member}
                      </span>
                    <% end %>
                  </div>
                </div>
              </div>

              <%!-- Transcript panel --%>
              <div class="commit-detail-transcript" data-testid="transcript-panel">
                <div class="commit-detail-section-title mb-2">
                  Linked Sessions ({length(@commit_detail_linked_sessions)})
                </div>

                <%= if @commit_detail_linked_sessions == [] do %>
                  <p class="text-muted text-sm">No linked sessions.</p>
                <% else %>
                  <div class="commit-detail-session-list">
                    <div :for={entry <- @commit_detail_linked_sessions} class="commit-detail-session-entry">
                      <button
                        phx-click="select_session"
                        phx-value-session-id={entry.session.id}
                        class={"commit-detail-session-btn#{if @commit_detail_selected_session_id == entry.session.id, do: " is-active"}"}
                      >
                        <span class="commit-detail-session-name">
                          {session_label(entry.session)}
                        </span>
                        <span
                          :for={lt <- entry.link_types}
                          class={badge_class(lt)}
                        >
                          {badge_text(lt, entry.max_confidence)}
                        </span>
                      </button>
                      <%= if entry.session.distilled_status == :completed do %>
                        <pre class="session-distilled-summary text-sm">{entry.session.distilled_summary}</pre>
                      <% end %>
                    </div>
                  </div>

                  <%= if @commit_detail_selected_session_id do %>
                    <div class="mt-3">
                      <.transcript_panel
                        rendered_lines={@commit_detail_transcript_rendered_lines}
                        panel_id="commit-transcript-messages"
                        empty_message="No transcript available for this session."
                      />
                    </div>
                  <% else %>
                    <p class="text-muted text-sm mt-3">
                      Select a session to view its transcript.
                    </p>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
      <% end %>
    </div>
    """
  end
end
