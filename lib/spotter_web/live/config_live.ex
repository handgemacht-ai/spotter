defmodule SpotterWeb.ConfigLive do
  use Phoenix.LiveView

  alias Spotter.Config.{Runtime, Setting}
  alias Spotter.Observability.ErrorReport
  alias Spotter.Transcripts.{Config, Project}

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @server_port Application.compile_env(:spotter, [SpotterWeb.Endpoint, :http, :port], 1100)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_all(socket)}
  end

  @impl true
  def handle_event("save_setting", %{"key" => key, "value" => value}, socket) do
    Tracer.with_span "spotter.config_live.save_setting" do
      Tracer.set_attribute("config.key", key)
      value = String.trim(value)

      case upsert_setting(key, value) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, "Saved #{key}") |> load_all()}

        {:error, reason} ->
          ErrorReport.set_trace_error("ash_error", "ash_error", "live.config_live")
          {:noreply, put_flash(socket, :error, "Failed to save #{key}: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("save_transcripts_dir", %{"value" => value}, socket) do
    value = String.trim(value)

    if value == "" do
      {:noreply, put_flash(socket, :error, "Transcripts directory cannot be empty")}
    else
      Tracer.with_span "spotter.config_live.save_setting" do
        Tracer.set_attribute("config.key", "transcripts_dir")

        case upsert_setting("transcripts_dir", value) do
          {:ok, _} ->
            {:noreply, socket |> put_flash(:info, "Saved transcripts_dir") |> load_all()}

          {:error, reason} ->
            ErrorReport.set_trace_error("ash_error", "ash_error", "live.config_live")
            {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(reason)}")}
        end
      end
    end
  end

  def handle_event("save_summary_model", %{"value" => value}, socket) do
    Tracer.with_span "spotter.config_live.save_setting" do
      Tracer.set_attribute("config.key", "summary_model")

      case upsert_setting("summary_model", String.trim(value)) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, "Saved summary_model") |> load_all()}

        {:error, reason} ->
          ErrorReport.set_trace_error("ash_error", "ash_error", "live.config_live")
          {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("save_summary_budget", %{"value" => raw}, socket) do
    Tracer.with_span "spotter.config_live.save_setting" do
      Tracer.set_attribute("config.key", "summary_token_budget")

      case parse_positive_integer(raw) do
        {:ok, _int} ->
          case upsert_setting("summary_token_budget", String.trim(raw)) do
            {:ok, _} ->
              {:noreply, socket |> put_flash(:info, "Saved summary_token_budget") |> load_all()}

            {:error, reason} ->
              ErrorReport.set_trace_error("ash_error", "ash_error", "live.config_live")
              {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(reason)}")}
          end

        :error ->
          ErrorReport.set_trace_error("validation_error", "validation_error", "live.config_live")
          {:noreply, put_flash(socket, :error, "Token budget must be a positive integer")}
      end
    end
  end

  def handle_event("project_create", %{"name" => name, "pattern" => pattern}, socket) do
    Tracer.with_span "spotter.config_live.project_create" do
      Tracer.set_attribute("project.name", name)

      case Regex.compile(pattern) do
        {:ok, _} ->
          case Ash.create(Project, %{name: String.trim(name), pattern: String.trim(pattern)}) do
            {:ok, project} ->
              Tracer.set_attribute("project.id", project.id)
              {:noreply, socket |> put_flash(:info, "Created project #{name}") |> load_all()}

            {:error, reason} ->
              ErrorReport.set_trace_error("ash_error", "ash_error", "live.config_live")

              {:noreply,
               put_flash(socket, :error, "Failed to create project: #{inspect(reason)}")}
          end

        {:error, _} ->
          ErrorReport.set_trace_error("validation_error", "validation_error", "live.config_live")
          {:noreply, put_flash(socket, :error, "Invalid regex pattern")}
      end
    end
  end

  def handle_event("project_update", %{"project_id" => id, "pattern" => pattern}, socket) do
    Tracer.with_span "spotter.config_live.project_update" do
      Tracer.set_attribute("project.id", id)

      case Regex.compile(pattern) do
        {:ok, _} ->
          project = Ash.get!(Project, id)
          Tracer.set_attribute("project.name", project.name)

          case Ash.update(project, %{pattern: String.trim(pattern)}) do
            {:ok, _} ->
              {:noreply, socket |> put_flash(:info, "Updated project pattern") |> load_all()}

            {:error, reason} ->
              ErrorReport.set_trace_error("ash_error", "ash_error", "live.config_live")
              {:noreply, put_flash(socket, :error, "Failed to update: #{inspect(reason)}")}
          end

        {:error, _} ->
          ErrorReport.set_trace_error("validation_error", "validation_error", "live.config_live")
          {:noreply, put_flash(socket, :error, "Invalid regex pattern")}
      end
    end
  end

  def handle_event("project_confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, confirming_delete: id)}
  end

  def handle_event("project_cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirming_delete: nil)}
  end

  def handle_event("project_delete", %{"id" => id}, socket) do
    Tracer.with_span "spotter.config_live.project_delete" do
      Tracer.set_attribute("project.id", id)

      case Ash.get(Project, id) do
        {:ok, nil} ->
          ErrorReport.set_trace_error("not_found", "not_found", "live.config_live")

          {:noreply,
           socket
           |> assign(confirming_delete: nil)
           |> put_flash(:error, "Project not found")
           |> load_all()}

        {:ok, project} ->
          Tracer.set_attribute("project.name", project.name)

          case destroy_project_by_id(id) do
            :ok ->
              {:noreply,
               socket
               |> assign(confirming_delete: nil)
               |> put_flash(:info, "Deleted project #{project.name}")
               |> load_all()}

            {:error, reason} ->
              ErrorReport.set_trace_error("destroy_failed", "destroy_failed", "live.config_live")

              {:noreply,
               socket
               |> assign(confirming_delete: nil)
               |> put_flash(:error, "Failed to delete project: #{inspect(reason)}")
               |> load_all()}
          end

        {:error, _reason} ->
          ErrorReport.set_trace_error("not_found", "not_found", "live.config_live")

          {:noreply,
           socket
           |> assign(confirming_delete: nil)
           |> put_flash(:error, "Project not found")
           |> load_all()}
      end
    end
  end

  def handle_event("import_toml", _params, socket) do
    Tracer.with_span "spotter.config_live.import_projects_from_toml" do
      try do
        case Config.import_projects_from_toml!() do
          {:ok, count} ->
            {:noreply,
             socket |> put_flash(:info, "Imported #{count} projects from TOML") |> load_all()}

          {:error, {:invalid_pattern, name}} ->
            ErrorReport.set_trace_error(
              "validation_error",
              "validation_error",
              "live.config_live"
            )

            {:noreply, put_flash(socket, :error, "Invalid pattern for project #{name}")}
        end
      rescue
        e ->
          ErrorReport.set_trace_error("ash_error", "ash_error", "live.config_live")
          {:noreply, put_flash(socket, :error, "Import failed: #{Exception.message(e)}")}
      end
    end
  end

  defp load_all(socket) do
    {transcripts_dir, transcripts_dir_source} = Runtime.transcripts_dir()
    {summary_model, summary_model_source} = Runtime.summary_model()
    {summary_budget, summary_budget_source} = Runtime.summary_token_budget()

    {session_distiller_system_prompt, session_distiller_system_prompt_source} =
      Runtime.session_distiller_system_prompt()

    {product_spec_system_prompt, product_spec_system_prompt_source} =
      Runtime.product_spec_system_prompt()

    {project_rollup_system_prompt, project_rollup_system_prompt_source} =
      Runtime.project_rollup_system_prompt()

    {waiting_summary_system_prompt, waiting_summary_system_prompt_source} =
      Runtime.waiting_summary_system_prompt()

    {commit_hotspot_explore_system_prompt, commit_hotspot_explore_system_prompt_source} =
      Runtime.commit_hotspot_explore_system_prompt()

    {commit_hotspot_main_system_prompt, commit_hotspot_main_system_prompt_source} =
      Runtime.commit_hotspot_main_system_prompt()

    api_key_present = Runtime.anthropic_key_present?()
    projects = Ash.read!(Project)

    otel_enabled = System.get_env("SPOTTER_OTEL_ENABLED") || "true"
    otel_exporter = System.get_env("OTEL_EXPORTER") || "otlp"
    otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") || "http://localhost:4318"
    server_port = @server_port

    assign(socket,
      transcripts_dir: transcripts_dir,
      transcripts_dir_source: transcripts_dir_source,
      summary_model: summary_model,
      summary_model_source: summary_model_source,
      summary_budget: summary_budget,
      summary_budget_source: summary_budget_source,
      product_spec_system_prompt: product_spec_system_prompt,
      product_spec_system_prompt_source: product_spec_system_prompt_source,
      session_distiller_system_prompt: session_distiller_system_prompt,
      session_distiller_system_prompt_source: session_distiller_system_prompt_source,
      project_rollup_system_prompt: project_rollup_system_prompt,
      project_rollup_system_prompt_source: project_rollup_system_prompt_source,
      waiting_summary_system_prompt: waiting_summary_system_prompt,
      waiting_summary_system_prompt_source: waiting_summary_system_prompt_source,
      commit_hotspot_explore_system_prompt: commit_hotspot_explore_system_prompt,
      commit_hotspot_explore_system_prompt_source: commit_hotspot_explore_system_prompt_source,
      commit_hotspot_main_system_prompt: commit_hotspot_main_system_prompt,
      commit_hotspot_main_system_prompt_source: commit_hotspot_main_system_prompt_source,
      api_key_present: api_key_present,
      projects: projects,
      otel_enabled: otel_enabled,
      otel_exporter: otel_exporter,
      otel_endpoint: otel_endpoint,
      server_port: server_port,
      confirming_delete: nil
    )
  end

  # Cast-safe delete to work around SQLite UUIDv7 type mismatch where
  # Ash.destroy generates `WHERE p0.id = ?` (zero rows) instead of using CAST.
  defp destroy_project_by_id(id) do
    import Ecto.Query

    case Spotter.Repo.delete_all(
           from(p in "projects", where: fragment("CAST(? AS TEXT) = CAST(? AS TEXT)", p.id, ^id))
         ) do
      {n, _} when n > 0 -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  defp upsert_setting(key, value) do
    case Setting
         |> Ash.Query.filter(key == ^key)
         |> Ash.read_one() do
      {:ok, nil} -> Ash.create(Setting, %{key: key, value: value})
      {:ok, existing} -> Ash.update(existing, %{value: value})
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_positive_integer(raw) when is_binary(raw) do
    case Integer.parse(String.trim(raw)) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_positive_integer(_), do: :error

  defp source_label(:db), do: "DB override"
  defp source_label(:toml), do: "TOML"
  defp source_label(:env), do: "env var"
  defp source_label(:default), do: "default"
  defp source_label(other), do: to_string(other)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-header">
        <h1>Settings</h1>
      </div>

      <%!-- Transcripts Section --%>
      <section class="config-section">
        <h2>Transcripts</h2>

        <div class="config-row">
          <div class="config-label-group">
            <label class="config-label">transcripts_dir</label>
            <span class="config-source">{source_label(@transcripts_dir_source)}</span>
          </div>
          <form phx-submit="save_transcripts_dir" class="config-inline-form">
            <input type="text" name="value" value={@transcripts_dir} class="config-input" />
            <button type="submit" class="btn btn-sm">Save</button>
          </form>
        </div>

        <div class="config-projects">
          <h3>Projects</h3>

          <div :if={@projects == []} class="config-empty">
            No projects configured. Import from TOML or create one below.
          </div>

          <div :for={project <- @projects} class="project-row">
            <span class="project-name">{project.name}</span>
            <form phx-submit="project_update" class="config-inline-form">
              <input type="hidden" name="project_id" value={project.id} />
              <input type="text" name="pattern" value={project.pattern} class="config-input" />
              <button type="submit" class="btn btn-sm">Update</button>
            </form>
            <%= if @confirming_delete == project.id do %>
              <button phx-click="project_delete" phx-value-id={project.id} class="btn btn-sm btn-danger">
                Confirm
              </button>
              <button phx-click="project_cancel_delete" class="btn btn-sm btn-ghost">
                Cancel
              </button>
            <% else %>
              <button phx-click="project_confirm_delete" phx-value-id={project.id} class="btn btn-sm btn-ghost">
                Delete
              </button>
            <% end %>
          </div>

          <form phx-submit="project_create" class="project-create-form">
            <input type="text" name="name" placeholder="Project name" class="config-input" required />
            <input type="text" name="pattern" placeholder="Regex pattern" class="config-input" required />
            <button type="submit" class="btn btn-sm">Add project</button>
          </form>

          <button phx-click="import_toml" class="btn btn-ghost" style="margin-top: 0.5rem;">
            Import projects from TOML
          </button>
        </div>
      </section>

      <%!-- LLM Section --%>
      <section class="config-section">
        <h2>LLM</h2>

        <div class="config-row">
          <div class="config-label-group">
            <label class="config-label">Anthropic API key configured?</label>
          </div>
          <span class={"config-status #{if @api_key_present, do: "status-ok", else: "status-missing"}"}>
            {if @api_key_present, do: "Yes", else: "No"}
          </span>
        </div>

        <div class="config-row">
          <div class="config-label-group">
            <label class="config-label">summary_model</label>
            <span class="config-source">{source_label(@summary_model_source)}</span>
          </div>
          <form phx-submit="save_summary_model" class="config-inline-form">
            <input type="text" name="value" value={@summary_model} class="config-input" />
            <button type="submit" class="btn btn-sm">Save</button>
          </form>
        </div>

        <div class="config-row">
          <div class="config-label-group">
            <label class="config-label">summary_token_budget</label>
            <span class="config-source">{source_label(@summary_budget_source)}</span>
          </div>
          <form phx-submit="save_summary_budget" class="config-inline-form">
            <input type="number" name="value" value={@summary_budget} min="1" class="config-input" />
            <button type="submit" class="btn btn-sm">Save</button>
          </form>
        </div>
      </section>

      <%!-- Agent System Prompts Section --%>
      <section class="config-section">
        <h2>Agent System Prompts</h2>

          <div class="config-row">
            <div class="config-label-group">
              <label class="config-label">product_spec_system_prompt</label>
              <span class="config-source">{source_label(@product_spec_system_prompt_source)}</span>
            </div>
            <form phx-submit="save_setting" class="config-inline-form config-inline-form--textarea">
              <input type="hidden" name="key" value="product_spec_system_prompt" />
              <textarea name="value" class="config-textarea" rows="12">{@product_spec_system_prompt}</textarea>
              <button type="submit" class="btn btn-sm">Save</button>
            </form>
          </div>

          <div class="config-row">
            <div class="config-label-group">
              <label class="config-label">session_distiller_system_prompt</label>
              <span class="config-source">{source_label(@session_distiller_system_prompt_source)}</span>
            </div>
            <form phx-submit="save_setting" class="config-inline-form config-inline-form--textarea">
              <input type="hidden" name="key" value="session_distiller_system_prompt" />
              <textarea name="value" class="config-textarea" rows="12">{@session_distiller_system_prompt}</textarea>
              <button type="submit" class="btn btn-sm">Save</button>
            </form>
          </div>

          <div class="config-row">
            <div class="config-label-group">
              <label class="config-label">project_rollup_system_prompt</label>
              <span class="config-source">{source_label(@project_rollup_system_prompt_source)}</span>
            </div>
            <form phx-submit="save_setting" class="config-inline-form config-inline-form--textarea">
              <input type="hidden" name="key" value="project_rollup_system_prompt" />
              <textarea name="value" class="config-textarea" rows="10">{@project_rollup_system_prompt}</textarea>
              <button type="submit" class="btn btn-sm">Save</button>
            </form>
          </div>

          <div class="config-row">
            <div class="config-label-group">
              <label class="config-label">waiting_summary_system_prompt</label>
              <span class="config-source">{source_label(@waiting_summary_system_prompt_source)}</span>
            </div>
            <form phx-submit="save_setting" class="config-inline-form config-inline-form--textarea">
              <input type="hidden" name="key" value="waiting_summary_system_prompt" />
              <textarea name="value" class="config-textarea" rows="8">{@waiting_summary_system_prompt}</textarea>
              <button type="submit" class="btn btn-sm">Save</button>
            </form>
          </div>

          <div class="config-row">
            <div class="config-label-group">
              <label class="config-label">commit_hotspot_explore_system_prompt</label>
              <span class="config-source">{source_label(@commit_hotspot_explore_system_prompt_source)}</span>
            </div>
            <form phx-submit="save_setting" class="config-inline-form config-inline-form--textarea">
              <input type="hidden" name="key" value="commit_hotspot_explore_system_prompt" />
              <textarea
                name="value"
                class="config-textarea"
                rows="12"
              >{@commit_hotspot_explore_system_prompt}</textarea>
              <button type="submit" class="btn btn-sm">Save</button>
            </form>
          </div>

          <div class="config-row">
            <div class="config-label-group">
              <label class="config-label">commit_hotspot_main_system_prompt</label>
              <span class="config-source">{source_label(@commit_hotspot_main_system_prompt_source)}</span>
            </div>
            <form phx-submit="save_setting" class="config-inline-form config-inline-form--textarea">
              <input type="hidden" name="key" value="commit_hotspot_main_system_prompt" />
              <textarea name="value" class="config-textarea" rows="14">{@commit_hotspot_main_system_prompt}</textarea>
              <button type="submit" class="btn btn-sm">Save</button>
            </form>
          </div>
      </section>

      <%!-- OpenTelemetry Section --%>
      <section class="config-section">
        <h2>OpenTelemetry</h2>
        <p class="config-note">Read-only. Changes require restart.</p>

        <div class="config-row">
          <label class="config-label">SPOTTER_OTEL_ENABLED</label>
          <span class="config-value">{@otel_enabled}</span>
        </div>
        <div class="config-row">
          <label class="config-label">OTEL_EXPORTER</label>
          <span class="config-value">{@otel_exporter}</span>
        </div>
        <div class="config-row">
          <label class="config-label">OTEL_EXPORTER_OTLP_ENDPOINT</label>
          <span class="config-value">{@otel_endpoint}</span>
        </div>
      </section>

      <%!-- Server Section --%>
      <section class="config-section">
        <h2>Server</h2>
        <p class="config-note">Read-only. Changes require restart.</p>

        <div class="config-row">
          <label class="config-label">Port</label>
          <span class="config-value">{@server_port}</span>
        </div>
      </section>
    </div>

    <style>
      .config-section {
        margin-bottom: 2rem;
        padding: 1.25rem;
        border: 1px solid #333;
        border-radius: 8px;
        background: #1a1a2e;
      }
      .config-section h2 {
        margin: 0 0 1rem 0;
        font-size: 1.1rem;
        border-bottom: 1px solid #333;
        padding-bottom: 0.5rem;
      }
      .config-section h3 {
        margin: 1rem 0 0.5rem 0;
        font-size: 0.95rem;
        color: #9ca3af;
      }
      .config-row {
        display: flex;
        align-items: center;
        gap: 1rem;
        padding: 0.5rem 0;
      }
      .config-label-group {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        min-width: 220px;
      }
      .config-label {
        font-family: monospace;
        font-size: 0.85rem;
        color: #e5e7eb;
      }
      .config-source {
        font-size: 0.7rem;
        padding: 0.1rem 0.4rem;
        border-radius: 4px;
        background: #374151;
        color: #9ca3af;
      }
      .config-value {
        font-family: monospace;
        font-size: 0.85rem;
        color: #93c5fd;
      }
      .config-note {
        font-size: 0.8rem;
        color: #6b7280;
        margin: 0 0 0.75rem 0;
      }
      .config-inline-form {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        flex: 1;
      }
      .config-inline-form--textarea {
        align-items: flex-start;
        flex-direction: column;
      }
      .config-input {
        font-family: monospace;
        font-size: 0.85rem;
        padding: 0.35rem 0.5rem;
        background: #0d1117;
        border: 1px solid #333;
        border-radius: 4px;
        color: #e5e7eb;
        flex: 1;
      }
      .config-input:focus {
        outline: none;
        border-color: #93c5fd;
      }
      .config-empty {
        font-size: 0.85rem;
        color: #6b7280;
        padding: 0.5rem 0;
      }
      .config-status {
        font-size: 0.85rem;
        font-weight: 500;
      }
      .status-ok { color: #4ade80; }
      .status-missing { color: #f87171; }

      .config-projects { margin-top: 0.5rem; }
      .project-row {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        padding: 0.35rem 0;
      }
      .project-name {
        font-family: monospace;
        font-size: 0.85rem;
        color: #93c5fd;
        min-width: 150px;
      }
      .project-create-form {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        margin-top: 0.75rem;
        padding-top: 0.75rem;
        border-top: 1px solid #333;
      }

      .btn-sm {
        padding: 0.25rem 0.6rem;
        font-size: 0.8rem;
      }
      .btn-danger {
        background: #dc2626;
        color: #fff;
      }
      .btn-danger:hover {
        background: #b91c1c;
      }

      .config-textarea {
        width: 100%;
        min-height: 6rem;
        font-family: monospace;
        font-size: 0.75rem;
        padding: 0.35rem 0.5rem;
        background: #0d1117;
        border: 1px solid #333;
        border-radius: 4px;
        color: #e5e7eb;
        white-space: pre-wrap;
      }
      .config-textarea:focus {
        outline: none;
        border-color: #93c5fd;
      }
    </style>
    """
  end
end
