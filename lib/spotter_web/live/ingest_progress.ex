defmodule SpotterWeb.IngestProgress do
  @moduledoc """
  Shared ingest progress state management for LiveViews.
  """

  import Phoenix.Component, only: [assign: 2]

  alias Spotter.Transcripts.Jobs.SyncTranscripts

  @doc """
  Assigns initial ingest state to a socket.
  """
  def init_ingest(socket) do
    assign(socket,
      ingest_running: false,
      ingest_run_id: nil,
      ingest_projects: %{}
    )
  end

  @doc """
  Subscribes to sync progress PubSub topic.
  Call in mount/3 when `connected?(socket)` is true.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Spotter.PubSub, "sync:progress")
  end

  @doc """
  Triggers ingestion and returns the updated socket.
  """
  def start_ingest(socket) do
    # Intentional legacy caller — suppress deprecation warning
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    case apply(SyncTranscripts, :sync_all, []) do
      {:ok, %{run_id: run_id, projects_total: _}} ->
        assign(socket,
          ingest_running: true,
          ingest_run_id: run_id,
          ingest_projects: %{}
        )
    end
  end

  @doc """
  Handles a PubSub ingest message. Returns `{:ok, socket}` if handled,
  `:ignore` if the message is stale or unrecognized.
  """
  def handle_progress({:ingest_enqueued, %{run_id: run_id, projects: project_names}}, socket) do
    projects =
      Map.new(project_names, fn name ->
        {name,
         %{
           status: :queued,
           dirs_done: 0,
           dirs_total: 0,
           sessions_done: 0,
           sessions_total: 0,
           duration_ms: nil,
           error: nil
         }}
      end)

    {:ok,
     assign(socket,
       ingest_running: true,
       ingest_run_id: run_id,
       ingest_projects: projects
     )}
  end

  def handle_progress(
        {:sync_started, %{run_id: run_id, project: name} = data},
        %{assigns: %{ingest_run_id: run_id}} = socket
      ) do
    projects =
      Map.update(socket.assigns.ingest_projects, name, default_project(data), fn proj ->
        %{
          proj
          | status: :syncing,
            dirs_total: data.dirs_total,
            sessions_total: data.sessions_total
        }
      end)

    {:ok, assign(socket, ingest_projects: projects)}
  end

  def handle_progress(
        {:sync_progress, %{run_id: run_id, project: name} = data},
        %{assigns: %{ingest_run_id: run_id}} = socket
      ) do
    projects =
      Map.update(socket.assigns.ingest_projects, name, default_project(data), fn proj ->
        %{
          proj
          | dirs_done: data.dirs_done,
            dirs_total: data.dirs_total,
            sessions_done: data.sessions_done,
            sessions_total: data.sessions_total
        }
      end)

    {:ok, assign(socket, ingest_projects: projects)}
  end

  def handle_progress(
        {:sync_completed, %{run_id: run_id, project: name} = data},
        %{assigns: %{ingest_run_id: run_id}} = socket
      ) do
    projects =
      Map.update(socket.assigns.ingest_projects, name, default_project(data), fn proj ->
        %{proj | status: :completed, duration_ms: data.duration_ms}
      end)

    socket = assign(socket, ingest_projects: projects)
    {:ok, maybe_finish_run(socket)}
  end

  def handle_progress(
        {:sync_error, %{run_id: run_id, project: name} = data},
        %{assigns: %{ingest_run_id: run_id}} = socket
      ) do
    projects =
      Map.update(socket.assigns.ingest_projects, name, default_project(data), fn proj ->
        %{proj | status: :error, error: data.error}
      end)

    socket = assign(socket, ingest_projects: projects)
    {:ok, maybe_finish_run(socket)}
  end

  # Stale or unrecognized messages
  def handle_progress(_msg, _socket), do: :ignore

  defp default_project(data) do
    %{
      status: :syncing,
      dirs_done: Map.get(data, :dirs_done, 0),
      dirs_total: Map.get(data, :dirs_total, 0),
      sessions_done: Map.get(data, :sessions_done, 0),
      sessions_total: Map.get(data, :sessions_total, 0),
      duration_ms: nil,
      error: nil
    }
  end

  defp maybe_finish_run(socket) do
    all_terminal =
      socket.assigns.ingest_projects
      |> Map.values()
      |> Enum.all?(&(&1.status in [:completed, :error]))

    if all_terminal do
      assign(socket, ingest_running: false)
    else
      socket
    end
  end
end
