defmodule SpotterWeb.PlanComponents do
  @moduledoc """
  Reusable HEEx components for plans/epics rendering.

  Provides status badges, priority badges, epic table rows, acceptance tables,
  and task rows used by `PlansLive` and `PlanDetailLive`.
  """
  use Phoenix.Component

  @doc """
  Renders a status badge with appropriate color.
  """
  attr(:status, :string, required: true)

  def status_badge(assigns) do
    ~H"""
    <span class={"badge #{status_badge_class(@status)}"} data-status={@status}>
      {@status}
    </span>
    """
  end

  @doc """
  Renders a priority badge (0=Critical .. 4=Backlog).
  """
  attr(:priority, :integer, required: true)

  def priority_badge(assigns) do
    ~H"""
    <span class={"badge #{priority_badge_class(@priority)}"} data-priority={@priority}>
      {priority_label(@priority)}
    </span>
    """
  end

  @doc """
  Renders a full epic table with header and rows.
  """
  attr(:epics, :list, required: true)
  attr(:project, :string, required: true)

  def epic_table(assigns) do
    ~H"""
    <table class="epic-table" data-testid="epic-table">
      <thead>
        <tr>
          <th>ID</th>
          <th>Title</th>
          <th>Status</th>
          <th>Priority</th>
          <th>Tasks</th>
          <th>Created</th>
        </tr>
      </thead>
      <tbody>
        <%= for epic <- @epics do %>
          <.epic_table_row epic={epic} project={@project} />
        <% end %>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders an epic table row.
  """
  attr(:epic, :map, required: true)
  attr(:project, :string, required: true)

  def epic_table_row(assigns) do
    ~H"""
    <tr class="plan-epic-row" data-testid="epic-row">
      <td>
        <.link patch={"/plans/#{URI.encode_www_form(@project)}/#{URI.encode_www_form(@epic.id)}"} class="plan-epic-link">
          {@epic.id}
        </.link>
      </td>
      <td class="plan-epic-title">
        {@epic.title}
      </td>
      <td>
        <.status_badge status={@epic.status} />
      </td>
      <td>
        <.priority_badge priority={@epic.priority} />
      </td>
      <td class="text-muted">
        \u2014
      </td>
      <td class="text-muted">
        {format_date(@epic.created_at)}
      </td>
    </tr>
    """
  end

  @doc """
  Renders a GIVEN/WHEN/THEN acceptance criteria table.
  """
  attr(:rows, :list, required: true)

  def acceptance_table(assigns) do
    ~H"""
    <table class="acceptance-table" data-testid="acceptance-table">
      <thead>
        <tr>
          <th>GIVEN</th>
          <th>WHEN</th>
          <th>THEN</th>
        </tr>
      </thead>
      <tbody>
        <%= for row <- @rows do %>
          <tr>
            <td>{row.given}</td>
            <td>{row.when}</td>
            <td>{row.then}</td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a child task row as a navigable link.
  """
  attr(:task, :map, required: true)
  attr(:project, :string, required: true)

  def task_row(assigns) do
    ~H"""
    <div class="plan-task-row" data-testid="child-task-row" data-task-id={@task.id}>
      <div class="plan-task-row-header">
        <.link
          patch={"/plans/#{URI.encode_www_form(@project)}/#{URI.encode_www_form(@task.id)}"}
          class="plan-task-link"
        >
          <span class="plan-task-id">{@task.id}</span>
          <span class="plan-task-title">{@task.title}</span>
        </.link>
        <.status_badge status={@task.status} />
        <.priority_badge priority={@task.priority} />
      </div>
    </div>
    """
  end

  defp status_badge_class("open"), do: "badge-verified"
  defp status_badge_class("closed"), do: "badge-muted"
  defp status_badge_class("in_progress"), do: "badge-agent"
  defp status_badge_class(_), do: ""

  defp priority_badge_class(0), do: "badge-error"
  defp priority_badge_class(1), do: "badge-inferred"
  defp priority_badge_class(2), do: ""
  defp priority_badge_class(p) when p in [3, 4], do: "badge-muted"
  defp priority_badge_class(_), do: ""

  defp priority_label(0), do: "Critical"
  defp priority_label(1), do: "High"
  defp priority_label(2), do: "Medium"
  defp priority_label(3), do: "Low"
  defp priority_label(4), do: "Backlog"
  defp priority_label(_), do: "Unknown"

  defp format_date(nil), do: "\u2014"

  defp format_date(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d")
  end

  defp format_date(_), do: "\u2014"
end
