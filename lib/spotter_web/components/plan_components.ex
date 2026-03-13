defmodule SpotterWeb.PlanComponents do
  @moduledoc """
  Reusable HEEx components for plans/epics rendering.

  Provides status badges, priority badges, project chips, and epic table rows
  used by `PlansLive`.
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
  Renders a project filter chip with epic count.
  """
  attr(:project, :string, required: true)
  attr(:epic_count, :integer, required: true)
  attr(:active, :boolean, default: false)

  def project_chip(assigns) do
    ~H"""
    <button
      phx-click="select_project"
      phx-value-project={@project}
      class={"filter-btn#{if @active, do: " is-active"}"}
      data-project={@project}
    >
      {@project}
      <span class="plan-chip-count">{@epic_count}</span>
    </button>
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
        <a href={"/plans/#{@project}/#{@epic.id}"} class="plan-epic-link">
          {@epic.id}
        </a>
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
        {format_date(@epic.created_at)}
      </td>
    </tr>
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
