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

  attr(:rows, :list, required: true)

  def acceptance_cards(assigns) do
    ~H"""
    <div :if={@rows != []} class="bead-acceptance-tests" data-testid="acceptance-cards">
      <h4 class="bead-section-heading">Acceptance Tests</h4>
      <div :for={row <- @rows} class="acceptance-card">
        <div class="acceptance-row">
          <span class="acceptance-label acceptance-given">GIVEN</span>
          <span class="acceptance-value">{row.given}</span>
        </div>
        <hr class="acceptance-divider" />
        <div class="acceptance-row">
          <span class="acceptance-label acceptance-when">WHEN</span>
          <span class="acceptance-value">{row.when}</span>
        </div>
        <hr class="acceptance-divider" />
        <div class="acceptance-row">
          <span class="acceptance-label acceptance-then">THEN</span>
          <span class="acceptance-value">{row.then}</span>
        </div>
      </div>
    </div>
    """
  end

  attr(:items, :list, required: true)

  def classification_chips(assigns) do
    ~H"""
    <div :if={@items != []} class="bead-classification" data-testid="bead-classification">
      <div :for={{key, values} <- @items} class="bead-classification-item">
        <span class="bead-classification-label">{key}</span>
        <span :for={v <- values} class={"badge #{chip_class(key, v)}"}>{v}</span>
      </div>
    </div>
    """
  end

  attr(:deps, :list, required: true)
  attr(:project, :string, required: true)

  def dependency_list(assigns) do
    ~H"""
    <div :if={@deps != []} class="bead-dependencies" data-testid="bead-dependencies">
      <h4 class="bead-section-heading">Dependencies</h4>
      <div
        :for={dep <- @deps}
        class={"bead-dep-row #{if dep.depends_on_status != "closed", do: "bead-dep-row--blocking"}"}
        data-testid="dependency-row"
      >
        <.link
          patch={"/plans/#{URI.encode_www_form(@project)}/#{URI.encode_www_form(dep.depends_on_id)}"}
          class="bead-dep-link"
        >
          <span class="bead-dep-id">{dep.depends_on_id}</span>
          <span :if={dep.depends_on_title} class="bead-dep-title">{dep.depends_on_title}</span>
        </.link>
        <.status_badge :if={dep.depends_on_status} status={dep.depends_on_status} />
        <span class="badge">{dep.type}</span>
      </div>
    </div>
    """
  end

  attr(:bead, :map, required: true)

  def bead_header(assigns) do
    ~H"""
    <div class="bead-detail-header" data-testid="bead-detail-header">
      <div class="bead-header-top">
        <span
          class={"badge bead-type-chip bead-type-#{@bead.issue_type}"}
          data-testid="bead-type-chip"
        >
          {@bead.issue_type}
        </span>
        <span class="bead-header-id" data-testid="bead-id">{@bead.id}</span>
        <h2 class="bead-header-title">{@bead.title}</h2>
      </div>
      <div class="bead-header-meta">
        <.status_badge status={@bead.status} />
        <.priority_badge priority={@bead.priority} />
        <span :if={@bead.assignee} class="bead-header-assignee">@{@bead.assignee}</span>
      </div>
    </div>
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

  defp chip_class(_key, "true"), do: "badge-verified"
  defp chip_class(_key, "false"), do: "badge-muted"
  defp chip_class("Type", _value), do: "badge-agent"
  defp chip_class("Affected Boundaries", _value), do: "badge-inferred"
  defp chip_class("Boundary Operation", _value), do: "badge-inferred"
  defp chip_class(_key, _value), do: ""

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
